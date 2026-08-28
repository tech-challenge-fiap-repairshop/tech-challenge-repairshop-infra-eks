data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.s3_tfstate_bucket
    key    = var.remote_state_network_key != "" ? var.remote_state_network_key : "network/${var.environment}.tfstate"
    region = var.aws_region
  }
}

# Security Group gerenciado para os Worker Nodes e Pods do EKS
resource "aws_security_group" "eks_nodes" {
  name        = "${var.cluster_name}-nodes-sg"
  description = "Security Group para Worker Nodes e Pods do EKS (${var.environment})"
  vpc_id      = try(data.terraform_remote_state.network.outputs.vpc_id, null)

  ingress {
    description = "Porta da aplicacao Spring Boot vinda da VPC"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [try(data.terraform_remote_state.network.outputs.vpc_cidr_block, "10.0.0.0/16")]
  }

  ingress {
    description = "OTel Collector OTLP gRPC vindo da VPC"
    from_port   = 4317
    to_port     = 4317
    protocol    = "tcp"
    cidr_blocks = [try(data.terraform_remote_state.network.outputs.vpc_cidr_block, "10.0.0.0/16")]
  }

  ingress {
    description = "OTel Collector OTLP HTTP vindo da VPC"
    from_port   = 4318
    to_port     = 4318
    protocol    = "tcp"
    cidr_blocks = [try(data.terraform_remote_state.network.outputs.vpc_cidr_block, "10.0.0.0/16")]
  }

  egress {
    description = "Egress irrestrito para download de imagens no ECR e comunicacao externa"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-nodes-sg"
  }
}

# EKS Cluster Control Plane
resource "aws_eks_cluster" "eks" {
  name     = var.cluster_name
  role_arn = local.lab_role_arn
  version  = "1.31"

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = concat(try(data.terraform_remote_state.network.outputs.public_subnet_ids, []), try(data.terraform_remote_state.network.outputs.private_subnet_ids, []))
    endpoint_private_access = true
    endpoint_public_access  = true
  }
}

# Node Group gerenciado para execução dos pods da aplicação
resource "aws_eks_node_group" "nodes" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "${var.cluster_name}-node-group"
  node_role_arn   = local.lab_role_arn
  subnet_ids      = try(data.terraform_remote_state.network.outputs.private_subnet_ids, [])

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  instance_types = [var.eks_node_instance_type]
}

# Instalação automática do Metrics Server no EKS via Helm
resource "helm_release" "metrics_server" {
  name             = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  version          = "3.12.1" # Versão estável do Chart do Metrics Server
  namespace        = "kube-system"
  create_namespace = false

  # Garante que o Metrics Server seja instalado apenas após os nós estarem prontos
  depends_on = [aws_eks_node_group.nodes]
}
