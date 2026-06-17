output "cluster_name" {
  description = "EKS 클러스터 이름 (kubectl 설정에 사용)"
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS API 서버 엔드포인트"
  value = aws_eks_cluster.main.endpoint
}

output "configure_kubectl" {
  description = "kubeconfig 설정 명령"
  value  = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

output "irsa_app_role_arn" {
  description = "파드 ServiceAccount(default:fin-app)에 연결할 IAM 역할 ARN"
  value = aws_iam_role.irsa_app.arn
}

output "waf_web_acl_arn" {
  description = "Ingress 어노테이션에 넣을 WAF WebACL ARN"
  value = aws_wafv2_web_acl.main.arn
}

output "rds_endpoint" {
  description = "RDS 엔드포인트"
  value = aws_db_instance.main.endpoint
}

output "db_secret_arn" {
  description = "DB 자격증명 Secrets Manager ARN"
  value = aws_secretsmanager_secret.db.arn
}
