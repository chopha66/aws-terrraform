output "cluster_name" {
  description = "EKS 클러스터 이름"
  value       = aws_eks_cluster.main.name
}

output "configure_kubectl" {
  description = "kubeconfig 설정 명령"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

output "ecr_repository_url" {
  description = "이미지 푸시 대상 ECR URL"
  value       = aws_ecr_repository.app.repository_url
}

output "cloudfront_domain" {
  description = "정적 자산 CDN 도메인"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "static_bucket" {
  description = "정적 자산 S3 버킷"
  value       = aws_s3_bucket.static.bucket
}

output "oidc_provider_arn" {
  description = "IRSA용 OIDC 공급자 ARN (LB Controller / Cluster Autoscaler 설치 시 사용)"
  value       = aws_iam_openid_connect_provider.eks.arn
}
