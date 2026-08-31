output "eks_cluster_name" {
  description = "Nome do Cluster EKS"
  value       = aws_eks_cluster.eks.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint do Cluster EKS"
  value       = aws_eks_cluster.eks.endpoint
}

output "eks_cluster_certificate_authority" {
  description = "Autoridade de certificação do Cluster EKS"
  value       = aws_eks_cluster.eks.certificate_authority[0].data
}

output "eks_nodes_security_group_id" {
  description = "ID do Security Group dos nós e pods do EKS"
  value       = aws_security_group.eks_nodes.id
}
