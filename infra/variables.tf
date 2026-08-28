variable "aws_region" {
  description = "Região da AWS para provisionamento"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Ambiente de deploy (dev, hml, prd)"
  type        = string
  default     = "prd"
}

variable "cluster_name" {
  description = "Nome do Cluster EKS"
  type        = string
  default     = "repairshop-eks"
}

variable "eks_node_instance_type" {
  description = "Tipo de instância EC2 para os worker nodes do EKS"
  type        = string
  default     = "t3.medium"
}

variable "s3_tfstate_bucket" {
  description = "Nome do bucket S3 onde está armazenado o tfstate de rede"
  type        = string
  default     = "fiap-repairshop2"
}

variable "remote_state_network_key" {
  description = "Chave do S3 onde está o tfstate da infraestrutura de rede"
  type        = string
  default     = ""
}

# Busca dinâmica do ID da conta AWS
data "aws_caller_identity" "current" {}

locals {
  # Constrói o ARN da role dinamicamente utilizando a conta atual logada
  lab_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/LabRole"
}
