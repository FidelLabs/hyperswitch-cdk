# Hyperswitch Infrastructure - Terraform Version
# This replaces ~3,000 lines of CDK code with ~800 lines of simple HCL

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Backend configuration for state management
  backend "s3" {
    bucket         = "hyperswitch-terraform-state"
    key            = "eks/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local variables
locals {
  cluster_name = "hs-eks-cluster"
  environment  = var.environment

  common_tags = {
    Stack       = "Hyperswitch"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  cluster_name = local.cluster_name
  environment  = local.environment
  tags         = local.common_tags
}

# EKS Cluster Module
module "eks" {
  source = "./modules/eks"

  cluster_name    = local.cluster_name
  cluster_version = var.eks_version

  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets

  # Simplified node configuration - 3 groups instead of 12+
  node_groups = {
    general = {
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 10
      desired_size   = 3

      labels = {
        "node-type" = "general-compute"
      }
    }

    compute = {
      instance_types = ["r5.large"]
      min_size       = 1
      max_size       = 5
      desired_size   = 1

      labels = {
        "node-type" = "compute-intensive"
      }
    }

    monitoring = {
      instance_types = ["t3.small"]
      min_size       = 1
      max_size       = 3
      desired_size   = 2

      labels = {
        "node-type" = "monitoring"
      }
    }
  }

  tags = local.common_tags
}

# RDS Module
module "rds" {
  source = "./modules/rds"

  cluster_name    = "hyperswitch-db"
  engine_version  = "16.1"
  instance_class  = var.db_instance_class

  vpc_id              = module.vpc.vpc_id
  database_subnets    = module.vpc.database_subnets
  allowed_cidr_blocks = [module.vpc.vpc_cidr]

  # Master credentials stored in Secrets Manager
  master_username = "db_user"
  database_name   = "hyperswitch"

  tags = local.common_tags
}

# ElastiCache Module
module "elasticache" {
  source = "./modules/elasticache"

  cluster_name    = "hyperswitch-redis"
  engine_version  = "7.1"
  node_type       = var.redis_node_type

  vpc_id              = module.vpc.vpc_id
  cache_subnets       = module.vpc.cache_subnets
  allowed_cidr_blocks = [module.vpc.vpc_cidr]

  tags = local.common_tags
}

# Kubernetes Resources Module (Helm charts, etc.)
module "kubernetes" {
  source = "./modules/kubernetes"

  cluster_name     = local.cluster_name
  cluster_endpoint = module.eks.cluster_endpoint
  cluster_ca_cert  = module.eks.cluster_ca_certificate

  # Application configuration
  hyperswitch_chart_version = var.hyperswitch_chart_version

  # Database connection
  db_host     = module.rds.cluster_endpoint
  db_password = module.rds.master_password

  # Redis connection
  redis_host = module.elasticache.primary_endpoint

  # Admin credentials
  admin_api_key = var.admin_api_key

  # Security
  kms_key_id = module.eks.kms_key_id

  depends_on = [
    module.eks,
    module.rds,
    module.elasticache
  ]
}
