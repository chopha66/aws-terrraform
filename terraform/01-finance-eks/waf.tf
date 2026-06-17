# WAF: REGIONAL WebACL
resource "aws_wafv2_web_acl" "main" {
  name = "${local.name}-waf"
  scope = "REGIONAL"
  description = "EKS Ingress ALB protection"

  default_action {
    allow {}
  }

  rule {
    name = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name = "${local.name}-common"
      sampled_requests_enabled = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name = "${local.name}-waf"
    sampled_requests_enabled   = true
  }
}
