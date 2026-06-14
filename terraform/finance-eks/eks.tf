# IAM: EKS Cluster Role
resource "aws_iam_role" "cluster" {
  name = "${local.name}-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# 시크릿 봉투 암호화를 위해 클러스터 역할에 KMS 권한 부여
resource "aws_iam_role_policy" "cluster_kms" {
  name = "${local.name}-cluster-kms"
  role = aws_iam_role.cluster.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey", "kms:CreateGrant", "kms:ListGrants"]
      Resource = aws_kms_key.main.arn
    }]
  })
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name = "${local.name}-cluster"
  role_arn = aws_iam_role.cluster.arn
  version = var.eks_version

  vpc_config {
    subnet_ids = concat(aws_subnet.app[*].id, aws_subnet.public[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.main.arn
    }
    resources = ["secrets"]
  }

  tags = { Name = "${local.name}-cluster" }
  depends_on = [aws_iam_role_policy_attachment.cluster, aws_iam_role_policy.cluster_kms]
}

# IAM: Node Group Role
resource "aws_iam_role" "node" {
  name = "${local.name}-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])
  role = aws_iam_role.node.name
  policy_arn = each.value
}

# EKS Node Group
resource "aws_eks_node_group" "main" {
  cluster_name = aws_eks_cluster.main.name
  node_group_name = "${local.name}-ng"
  node_role_arn = aws_iam_role.node.arn
  subnet_ids = aws_subnet.app[*].id
  instance_types  = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    min_size = var.node_min_size
    max_size = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = { Name = "${local.name}-ng" }
  depends_on = [aws_iam_role_policy_attachment.node]
}

# OIDC Provider
data "tls_certificate" "oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
}

# IRSA
data "aws_iam_policy_document" "irsa_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect = "Allow"
    principals {
      type = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    condition {
      test = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values = ["system:serviceaccount:default:fin-app"]
    }
  }
}

resource "aws_iam_role" "irsa_app" {
  name = "${local.name}-irsa-app"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume.json
}

resource "aws_iam_role_policy" "irsa_app" {
  name = "${local.name}-irsa-app-policy"
  role = aws_iam_role.irsa_app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.db.arn
      },
      {
        Effect = "Allow"
        Action = ["kms:Decrypt"]
        Resource = aws_kms_key.main.arn
      }
    ]
  })
}

# EKS Add-On
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name = "vpc-cni"
  depends_on = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name = "coredns"
  depends_on = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name = "kube-proxy"
  depends_on = [aws_eks_node_group.main]
}
