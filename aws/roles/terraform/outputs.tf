output "eks_connect" {
  value = "aws eks --region eu-west-1 update-kubeconfig --name ${aws_eks_cluster.main.name}"
}

output "eks_cluster_name" {
  description = "The name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "The endpoint for EKS control plane"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_certificate_authority" {
  description = "The certificate authority for EKS"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "subnet_ids" {
  value = [for s in aws_subnet.public_subnet : s.id]
}

output "public_subnets" {
  value = aws_subnet.public_subnet[*].id
}

output "alb_controller_role_arn" {
  value = aws_iam_role.alb_controller.arn
}

output "eks_cluster_auth_token" {
  description = "Token for EKS cluster authentication"
  value       = data.aws_eks_cluster_auth.main.token
  sensitive   = true
}

output "eks_node_role_name" {
  value = aws_iam_role.eks_node_role.name
}

output "eks_node_ids" {
  value = tolist(data.aws_instances.eks_nodes.ids)
}