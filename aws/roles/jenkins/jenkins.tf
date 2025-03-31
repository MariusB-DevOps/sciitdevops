############################################
# Terraform Remote State - outputs din modulul principal
############################################

data "terraform_remote_state" "terraform" {
  backend = "s3"
  config = {
    bucket = "mariusb-tf-state"
    key    = "terraform/state/terraform.tfstate"
    region = "eu-west-1"
  }
}

############################################
# Kubernetes & Helm Providers pentru EKS
############################################

provider "kubernetes" {
  host                   = data.terraform_remote_state.terraform.outputs.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.terraform.outputs.eks_cluster_certificate_authority)
  token                  = data.aws_eks_cluster_auth.main.token
}

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.7"
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.terraform.outputs.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.terraform.outputs.eks_cluster_certificate_authority)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

# Autentificare pentru EKS – folosită în providerii Kubernetes și Helm
data "aws_eks_cluster_auth" "main" {
  name = data.terraform_remote_state.terraform.outputs.eks_cluster_name
}

############################################
# Security Group pentru Jenkins
############################################

resource "aws_security_group" "jenkins_sg" {
  name_prefix = "jenkins-sg"
  vpc_id      = data.terraform_remote_state.terraform.outputs.vpc_id

  # Permit acces HTTPS, Jenkins UI și agent
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Permit tot traficul outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

############################################
# Load Balancer + Target Group + Listener pentru Jenkins
############################################

resource "aws_lb" "jenkins_alb" {
  name               = "jenkins-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.jenkins_sg.id]
  subnets            = data.terraform_remote_state.terraform.outputs.subnet_ids

  enable_deletion_protection = false
}

resource "aws_lb_target_group" "jenkins_tg" {
  name        = "jenkins-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = data.terraform_remote_state.terraform.outputs.vpc_id
  target_type = "ip"

  # Health check pentru endpoint-ul de login Jenkins
  health_check {
    path                = "/login"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "jenkins_https" {
  load_balancer_arn = aws_lb.jenkins_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins_tg.arn
  }
}

############################################
# Salvează DNS-ul ALB Jenkins în SSM Parameter Store
############################################

resource "aws_ssm_parameter" "jenkins_alb_dns" {
  name  = "/eks/jenkins-alb"
  type  = "String"
  value = aws_lb.jenkins_alb.dns_name
  overwrite = true
}

############################################
# Service Account pentru AWS Load Balancer Controller
############################################

resource "kubernetes_service_account" "alb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = data.terraform_remote_state.terraform.outputs.alb_controller_role_arn
    }
  }
}

############################################
# Helm Release pentru AWS EBS CSI Driver
############################################

resource "helm_release" "aws_ebs_csi_driver" {
  name       = "aws-ebs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart      = "aws-ebs-csi-driver"
  namespace  = "kube-system"

  set {
    name  = "controller.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "controller.serviceAccount.name"
    value = "ebs-csi-controller"
  }
}

############################################
# IAM Policy pentru EBS CSI Driver
############################################

resource "aws_iam_policy" "ebs_csi_policy" {
  name        = "AmazonEBSControllerPolicy"
  description = "Policy for EBS CSI driver to manage EBS volumes"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateVolume",
          "ec2:AttachVolume",
          "ec2:DeleteVolume",
          "ec2:DetachVolume",
          "ec2:ModifyVolume",
          "ec2:DescribeVolumes",
          "ec2:DescribeInstances",
          "ec2:DescribeAvailabilityZones",
          "ec2:CreateTags"
        ]
        Resource = "*"
      }
    ]
  })
}

# Atașează politica de EBS CSI la rolul nodurilor EKS
resource "aws_iam_role_policy_attachment" "ebs_csi_attach" {
  policy_arn = aws_iam_policy.ebs_csi_policy.arn
  role       = data.terraform_remote_state.terraform.outputs.eks_node_role_name
}

############################################
# DNS Records în Route53 pentru Jenkins și ArgoCD
############################################

resource "aws_route53_record" "jenkins" {
  zone_id = var.hosted_zone_id
  name    = "jenkins.k8s.it.com"
  type    = "A"
  alias {
    name                   = aws_lb.jenkins_alb.dns_name
    zone_id                = aws_lb.jenkins_alb.zone_id
    evaluate_target_health = true
  }

  depends_on = [aws_lb.jenkins_alb]
}

# Obține hostname-ul ArgoCD din SSM pentru DNS
data "aws_ssm_parameter" "argocd_server_load_balancer" {
  name = "/argocd/server/loadbalancer"
}

# Creează un record CNAME pentru ArgoCD
resource "aws_route53_record" "argocd" {
  zone_id = var.hosted_zone_id
  name    = "argocd.k8s.it.com"
  type    = "CNAME"
  ttl     = 300
  records = [data.aws_ssm_parameter.argocd_server_load_balancer.value]
}

############################################
# Atașează SG Jenkins la interfețele de rețea ale nodurilor EKS
############################################

data "aws_network_interfaces" "eks_instances" {
  filter {
    name   = "tag:cluster.k8s.amazonaws.com/name"
    values = ["main-eks-cluster"]
  }
}

resource "aws_network_interface_sg_attachment" "jenkins" {
  count                = length(data.aws_network_interfaces.eks_instances.ids)
  security_group_id    = aws_security_group.jenkins_sg.id
  network_interface_id = element(data.aws_network_interfaces.eks_instances.ids, count.index)
}
