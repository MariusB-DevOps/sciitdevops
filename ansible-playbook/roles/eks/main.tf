provider "aws" {
  region = "eu-west-1"
}
terraform {
  backend "s3" {
    bucket = "mariusb-tf-state"
    key    = "terraform/state/terraform.tfstate"
    region = "eu-west-1"
  }
}

locals {
  policies = ["arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy", "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy", "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"]
}

##############################################
#NETWORKING RESOURCES
##############################################


data "aws_availability_zones" "available" {}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "main-vpc"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [tags]
  }
}

resource "aws_subnet" "public_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "public-subnet-${count.index}"
    "kubernetes.io/role/elb" = "1"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [tags]
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "main-route-table"
  }
}

resource "aws_route_table_association" "a" {
  count          = 2
  subnet_id      = aws_subnet.public_subnet.*.id[count.index]
  route_table_id = aws_route_table.public.id
}

##############################################
#EKS RESOURCES
##############################################


resource "aws_eks_cluster" "main" {
  name     = "main-eks-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.32"

  vpc_config {
    subnet_ids             = aws_subnet.public_subnet.*.id
    endpoint_public_access = true
    security_group_ids = [aws_security_group.eks_node_sg.id]
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [version, vpc_config]
  }

  tags = {
    Name = "main-eks-cluster"
  }
}


resource "aws_security_group" "eks_node_sg" {
  name        = "eks-node-sg"
  description = "Security group for EKS nodes"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "eks-node-sg"
  }
}

# Permite acces pe porturile 8080 și 443 din internet
resource "aws_security_group_rule" "allow_http_https" {
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  security_group_id = aws_security_group.eks_node_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow HTTP from anywhere"
}

resource "aws_security_group_rule" "allow_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.eks_node_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow HTTPS from anywhere"
}

# Permite acces pe portul 50000 doar din CIDR-ul VPC
resource "aws_security_group_rule" "allow_jenkins_agent" {
  type              = "ingress"
  from_port         = 50000
  to_port           = 50000
  protocol          = "tcp"
  security_group_id = aws_security_group.eks_node_sg.id
  cidr_blocks       = [aws_vpc.main.cidr_block] # Permite doar în rețeaua internă VPC
  description       = "Allow Jenkins agent communication over JNLP port"
}

# Permite tot traficul de ieșire (obligatoriu pentru ca nodurile să se conecteze la Internet)
resource "aws_security_group_rule" "allow_all_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.eks_node_sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow all outbound traffic"
}



resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "main-eks-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = aws_subnet.public_subnet[*].id

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [scaling_config]
  }

  tags = {
    Name = "main-eks-node-group"
  }
}



##############################################
#IAM RESOURCES
##############################################

resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    },
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = {
    Name = "eks-role"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [tags]
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_role_attachment" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_policy" "load_balancer_controller" {
  name        = "CustomLoadBalancerControllerPolicy"
  description = "Policy for AWS Load Balancer Controller"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "acm:DescribeCertificate",
          "acm:ListCertificates",
          "acm:GetCertificate"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags",
          "ec2:DeleteSecurityGroup",
          "ec2:DeleteTags",
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeTags",
          "ec2:DescribeVpcs",
          "ec2:ModifyInstanceAttribute",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:RevokeSecurityGroupIngress"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DeleteRule",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:Describe*",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "iam:CreateServiceLinkedRole",
          "iam:GetRole",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfiles",
          "iam:ListPolicies",
          "iam:ListRoles",
          "iam:ListUsers"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "cognito-idp:DescribeUserPoolClient",
          "acm:ListCertificates",
          "ec2:DescribeVpcs",
          "ec2:DescribeAddresses"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "waf-regional:GetWebACLForResource",
          "waf-regional:GetWebACL",
          "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "tag:GetResources",
          "tag:TagResources"
        ],
        Resource = "*"
      }
    ]
  })
}

# ✅ Policy pentru gestionarea nodurilor EKS
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# ✅ Policy pentru acces la ECR (container registry)
resource "aws_iam_role_policy_attachment" "eks_ecr_read_only" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ✅ Permisiuni suplimentare pentru gestionarea ALB-ului
resource "aws_iam_policy" "alb_custom_policy" {
  name = "ALBControllerCustomPolicy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:Describe*",
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "elasticloadbalancing:*",
          "iam:CreateServiceLinkedRole",
          "iam:AttachRolePolicy",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "tag:GetResources",
          "tag:TagResources"
        ],
        Resource = "*"
      }
    ]
  })
}

# ✅ Atașăm policy-ul personalizat pentru ALB Controller
resource "aws_iam_role_policy_attachment" "alb_custom_policy_attachment" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = aws_iam_policy.alb_custom_policy.arn
}

resource "aws_iam_role" "eks_node_role" {
  name = "eks-node-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = {
    Name = "eks-node-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_role_attachment" {
  for_each   = toset(local.policies)
  role       = aws_iam_role.eks_node_role.name
  policy_arn = each.value
}

data "aws_eks_cluster" "main" {
  name       = "main-eks-cluster"
  depends_on = [aws_eks_cluster.main]
}

data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
}

data "tls_certificate" "eks" {
  url = data.aws_eks_cluster.main.identity[0].oidc[0].issuer
}

#data "aws_instances" "eks_nodes" {
#  filter {
#    name   = "tag:eks:nodegroup-name"
#    values = ["main-eks-node-group"]
#  }
#}

resource "aws_iam_openid_connect_provider" "eks_oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = data.aws_eks_cluster.main.identity[0].oidc[0].issuer

  lifecycle {
    prevent_destroy = true
    ignore_changes = [client_id_list, thumbprint_list]
  }
}

resource "aws_iam_role" "alb_controller" {
  name = "alb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks_oidc.arn
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          }
        }
      }
    ]
  })
    lifecycle {
    prevent_destroy = true
    ignore_changes = [assume_role_policy]
  }
}

resource "aws_iam_role_policy_attachment" "alb_controller_attachment" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.load_balancer_controller.arn
}

##############################################
#SSM PARAMETER STORE
##############################################

resource "aws_ssm_parameter" "eks_cluster_name" {
  name  = "/eks/cluster/name"
  type  = "String"
  value = aws_eks_cluster.main.name
}

resource "aws_ssm_parameter" "eks_cluster_endpoint" {
  name  = "/eks/cluster/endpoint"
  type  = "String"
  value = aws_eks_cluster.main.endpoint
}

resource "aws_ssm_parameter" "eks_cluster_certificate_authority" {
  name  = "/eks/cluster-ca"
  type  = "String"
  value = aws_eks_cluster.main.certificate_authority[0].data
}

resource "aws_ssm_parameter" "vpc_id" {
  name  = "/eks/vpc/id"
  type  = "String"
  value = aws_vpc.main.id
}

data "aws_instances" "eks_nodes" {
  filter {
    name   = "instance-state-name"
    values = ["running"] # doar instanțele active
  }

  filter {
    name   = "tag:eks-nodegroup"
    values = ["main"]
  }
}

resource "null_resource" "enable_imds_on_nodes" {
  for_each = toset(data.aws_instances.eks_nodes.ids)

  provisioner "local-exec" {
    command = <<EOT
    status=$(aws ec2 describe-instances --instance-ids ${each.value} --query "Reservations[].Instances[].MetadataOptions.HttpEndpoint" --output text)
    if [[ "$status" != "enabled" ]]; then
      aws ec2 modify-instance-metadata-options --instance-id ${each.value} --http-endpoint enabled --http-put-response-hop-limit 2 --http-tokens optional
    else
      echo "IMDS already enabled for instance ${each.value}"
    fi
    EOT
  }

  depends_on = [aws_eks_node_group.main]
}

