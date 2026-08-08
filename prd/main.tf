data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "fiap-repairshop2"
    key    = "network/prd.tfstate"
    region = "us-east-1"
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
    subnet_ids              = concat(data.terraform_remote_state.network.outputs.public_subnet_ids, data.terraform_remote_state.network.outputs.private_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true
  }
}

# Node Group gerenciado para execução dos pods da aplicação
resource "aws_eks_node_group" "nodes" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "${var.cluster_name}-node-group"
  node_role_arn   = local.lab_role_arn
  subnet_ids      = data.terraform_remote_state.network.outputs.private_subnet_ids

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
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
