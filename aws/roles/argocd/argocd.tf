####################################################
# Obține starea Terraform dintr-un backend S3
####################################################
data "terraform_remote_state" "terraform" {
  backend = "s3"
  config = {
    bucket = "mariusb-tf-state"
    key    = "terraform/state/terraform.tfstate"
    region = "eu-west-1"
  }
}

####################################################
# Providers and Cluster Authentication
####################################################

# Obține token-ul pentru autentificare în EKS
data "aws_eks_cluster_auth" "main" {
  name = "main-eks-cluster"
}

# Configurare provider Kubernetes pentru a interacționa cu clusterul EKS
provider "kubernetes" {
  host                   = data.terraform_remote_state.terraform.outputs.eks_cluster_endpoint
  token                  = data.aws_eks_cluster_auth.main.token
  cluster_ca_certificate = base64decode(data.terraform_remote_state.terraform.outputs.eks_cluster_certificate_authority)
}

# Configurare provider Helm pentru a instala charts în clusterul EKS
provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.terraform.outputs.eks_cluster_endpoint
    token                  = data.aws_eks_cluster_auth.main.token
    cluster_ca_certificate = base64decode(data.terraform_remote_state.terraform.outputs.eks_cluster_certificate_authority)
  }
}

##############################
# Deploy ArgoCD via Helm (using ClusterIP for the server)
##############################

# Instalează ArgoCD în clusterul EKS folosind Helm, cu serviciul de tip LoadBalancer (NLB)
resource "helm_release" "argocd" {
  depends_on = [data.terraform_remote_state.terraform]
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "4.5.2"

  namespace = "argocd"
  create_namespace = true

  # Setează tipul serviciului ArgoCD Server la LoadBalancer
  set {
    name  = "server.service.type"
    value = "LoadBalancer"
  }

  # Specifică folosirea unui NLB (Network Load Balancer) pe AWS
  set {
    name  = "server.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "nlb"
  }
}

# Obține detalii despre serviciul Kubernetes creat pentru ArgoCD (pentru a extrage DNS-ul ALB)
data "kubernetes_service" "argocd_server" {
  metadata {
    name      = "argocd-server"
    namespace = helm_release.argocd.namespace
  }
}

# Citește parola de admin generată automat de ArgoCD din secretul Kubernetes
data "kubernetes_secret" "argocd_admin" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = "argocd"
  }

  depends_on = [helm_release.argocd]
}

# Salvează parola de admin ArgoCD în AWS SSM Parameter Store (ca SecureString)
resource "aws_ssm_parameter" "argocd_admin_password" {
  name  = "/eks/argocd/admin-password"
  type  = "SecureString"
  value = data.kubernetes_secret.argocd_admin.data["password"]

  depends_on = [data.kubernetes_secret.argocd_admin]
}

# Salvează DNS-ul Load Balancer-ului pentru ArgoCD în AWS SSM Parameter Store (ca String simplu)
resource "aws_ssm_parameter" "argocd_server_load_balancer" {
  name        = "/argocd/server/loadbalancer"
  type        = "String"
  value       = data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].hostname
  description = "Load Balancer DNS for ArgoCD server"
  overwrite   = true
}
