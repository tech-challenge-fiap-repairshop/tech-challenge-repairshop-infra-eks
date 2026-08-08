variable "aws_region" {
  description = "Região da AWS para provisionamento"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Nome do Cluster EKS"
  type        = string
}

variable "eks_node_instance_type" {
  description = "Tipo de instância EC2 para os worker nodes do EKS"
  type        = string
  default     = "t3.small"
}

# Busca dinâmica do ID da conta AWS
data "aws_caller_identity" "current" {}

locals {
  # Constrói o ARN da role dinamicamente utilizando a conta atual logada
  lab_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
}
