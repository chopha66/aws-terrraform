data "aws_caller_identity" "current" {}

# ECR: Container Registry
resource "aws_ecr_repository" "app" {
  name = "${local.name}-app"
  image_tag_mutability = "MUTABLE"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
  tags = { Name = "${local.name}-app" }
}

# S3: Static
resource "aws_s3_bucket" "static" {
  bucket = "${local.name}-static-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags = { Name = "${local.name}-static" }
}

resource "aws_s3_bucket_public_access_block" "static" {
  bucket = aws_s3_bucket.static.id
  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "static" {
  name = "${local.name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior  = "always"
  signing_protocol = "sigv4"
}

resource "aws_cloudfront_distribution" "main" {
  enabled  = true
  default_root_object = "index.html"
  comment  = "${local.name} static assets"

  origin {
    domain_name = aws_s3_bucket.static.bucket_regional_domain_name
    origin_id  = "s3-static"
    origin_access_control_id = aws_cloudfront_origin_access_control.static.id
  }

  default_cache_behavior {
    target_origin_id = "s3-static"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods = ["GET", "HEAD"]
    cached_methods = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = { Name = "${local.name}-cdn" }
}

# CloudFront(OAC)만 S3 읽기 허용
resource "aws_s3_bucket_policy" "static" {
  bucket = aws_s3_bucket.static.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action = "s3:GetObject"
      Resource = "${aws_s3_bucket.static.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
        }
      }
    }]
  })
}
