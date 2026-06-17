data "aws_caller_identity" "current" {}

locals {
  name = "${var.project_name}-${var.environment}"
}

# Cold: S3 (Origin Data)
resource "aws_s3_bucket" "raw" {
  bucket = "${local.name}-raw-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags = { Name = "${local.name}-raw" }
}

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket = aws_s3_bucket.raw.id
  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}

# Hot: DynamoDB (Realtime)
resource "aws_dynamodb_table" "sensor" {
  name = "${local.name}-sensor-data"
  billing_mode = "PAY_PER_REQUEST"
  hash_key = "device_id"
  range_key = "timestamp"

  attribute {
    name = "device_id"
    type = "S"
  }
  attribute {
    name = "timestamp"
    type = "N"
  }

  tags = { Name = "${local.name}-sensor-data" }
}

# Alert: SNS
resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
  tags = { Name = "${local.name}-alerts" }
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol = "email"
  endpoint = var.alert_email
}

# Stream: Kinesis Data Stream
resource "aws_kinesis_stream" "ingest" {
  name = "${local.name}-ingest"
  shard_count = var.kinesis_shard_count
  retention_period = 24

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }
  tags = { Name = "${local.name}-ingest" }
}

# Lambda: Processing stream
data "archive_file" "lambda" {
  type = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_iam_role" "lambda" {
  name = "${local.name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "${local.name}-lambda-policy"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = ["kinesis:GetRecords", "kinesis:GetShardIterator", "kinesis:DescribeStream", "kinesis:ListShards"]
        Resource = aws_kinesis_stream.ingest.arn
      },
      {
        Effect = "Allow"
        Action = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.sensor.arn
      },
      {
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.raw.arn}/*"
      },
      {
        Effect = "Allow"
        Action = ["sns:Publish"]
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

resource "aws_lambda_function" "processor" {
  function_name = "${local.name}-processor"
  role = aws_iam_role.lambda.arn
  handler = "handler.handler"
  runtime = "python3.12"
  timeout = 60
  filename = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.sensor.name
      BUCKET_NAME = aws_s3_bucket.raw.bucket
      TOPIC_ARN = aws_sns_topic.alerts.arn
      TEMP_THRESHOLD = tostring(var.temperature_threshold)
    }
  }
  tags = { Name = "${local.name}-processor" }
}

resource "aws_lambda_event_source_mapping" "kinesis" {
  event_source_arn = aws_kinesis_stream.ingest.arn
  function_name = aws_lambda_function.processor.arn
  starting_position = "LATEST"
  batch_size = 100
}

# IoT Core: Topic rule → Kinesis
resource "aws_iam_role" "iot" {
  name = "${local.name}-iot-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "iot.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "iot" {
  name = "${local.name}-iot-policy"
  role = aws_iam_role.iot.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["kinesis:PutRecord"]
      Resource = aws_kinesis_stream.ingest.arn
    }]
  })
}

resource "aws_iot_topic_rule" "to_kinesis" {
  name = replace("${local.name}_to_kinesis", "-", "_")
  enabled = true
  sql = "SELECT * FROM 'factory/sensors/+'"
  sql_version = "2016-03-23"

  kinesis {
    role_arn = aws_iam_role.iot.arn
    stream_name = aws_kinesis_stream.ingest.name
    partition_key = "$${newuuid()}"
  }
}
