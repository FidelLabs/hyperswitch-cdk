# Input Variables

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "production"
}

variable "eks_version" {
  description = "EKS cluster version"
  type        = string
  default     = "1.32"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.r6g.large"
}

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.r6g.large"
}

variable "hyperswitch_chart_version" {
  description = "Hyperswitch Helm chart version"
  type        = string
  default     = "0.2.19"
}

variable "admin_api_key" {
  description = "Admin API key for Hyperswitch"
  type        = string
  sensitive   = true
}

variable "vpn_allowed_ips" {
  description = "List of IP addresses allowed to access EKS API"
  type        = list(string)
  default     = []
}
