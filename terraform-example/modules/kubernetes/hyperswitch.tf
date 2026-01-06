# Hyperswitch Helm Chart - No Image Mirroring Required!

resource "kubernetes_namespace" "hyperswitch" {
  metadata {
    name = "hyperswitch"
  }
}

# IAM role for Hyperswitch service account
resource "aws_iam_role" "hyperswitch" {
  name = "${var.cluster_name}-hyperswitch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider}:aud" = "sts.amazonaws.com"
          "${var.oidc_provider}:sub" = "system:serviceaccount:hyperswitch:hyperswitch-router-role"
        }
      }
    }]
  })
}

# Grant KMS and Secrets Manager access
resource "aws_iam_role_policy" "hyperswitch" {
  name = "hyperswitch-permissions"
  role = aws_iam_role.hyperswitch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.kms_key_arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:*:*:secret:hyperswitch/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/hyperswitch/*"
      }
    ]
  })
}

# Hyperswitch Helm Release
resource "helm_release" "hyperswitch" {
  name       = "hypers-v1"
  repository = "https://juspay.github.io/hyperswitch-helm/"
  chart      = "hyperswitch-stack"
  version    = var.hyperswitch_chart_version
  namespace  = kubernetes_namespace.hyperswitch.metadata[0].name

  timeout = 900  # 15 minutes for initial image pulls

  # Use public Docker Hub images directly - NO MIRRORING NEEDED!
  values = [yamlencode({
    global = {
      imageRegistry = ""  # Empty to use default registries
      imagePullPolicy = "IfNotPresent"
    }

    clusterName = var.cluster_name

    "hyperswitch-monitoring" = {
      enabled = false
    }

    "hyperswitch-app" = {
      redis = {
        enabled = false
      }

      services = {
        router = {
          # Use Docker Hub directly
          image = "juspaydotin/hyperswitch-router:v1.116.0-standalone"
          imagePullPolicy = "IfNotPresent"
        }
        producer = {
          image = "juspaydotin/hyperswitch-producer:v1.116.0-standalone"
          imagePullPolicy = "IfNotPresent"
        }
        consumer = {
          image = "juspaydotin/hyperswitch-consumer:v1.116.0-standalone"
          imagePullPolicy = "IfNotPresent"
        }
        controlCenter = {
          image = "juspaydotin/hyperswitch-control-center:v1.37.3"
          imagePullPolicy = "IfNotPresent"
        }
      }

      server = {
        # Node affinity simplified
        nodeAffinity = {
          requiredDuringSchedulingIgnoredDuringExecution = {
            nodeSelectorTerms = [{
              matchExpressions = [{
                key      = "node-type"
                operator = "In"
                values   = ["general-compute"]
              }]
            }]
          }
        }

        # Service account with IRSA
        serviceAccountAnnotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.hyperswitch.arn
        }

        # Database configuration
        externalPostgresql = {
          enabled = true
          primary = {
            host = var.db_host
            auth = {
              username     = "db_user"
              database     = "hyperswitch"
              password     = var.db_password
              plainpassword = var.db_password
            }
          }
        }

        # Redis configuration
        externalRedis = {
          enabled = true
          host    = var.redis_host
          port    = 6379
        }

        # KMS configuration
        secrets_management = {
          secrets_manager = "aws_kms"
          aws_kms = {
            key_id = var.kms_key_id
            region = data.aws_region.current.name
          }
        }

        # Autoscaling
        autoscaling = {
          enabled                        = true
          minReplicas                    = 3
          maxReplicas                    = 10
          targetCPUUtilizationPercentage = 80
        }
      }

      # PostgreSQL (external)
      postgresql = {
        enabled = false
      }
    }

    # Disable embedded services
    "hyperswitch-web" = {
      enabled = false
    }
  })]

  depends_on = [
    kubernetes_namespace.hyperswitch
  ]
}
