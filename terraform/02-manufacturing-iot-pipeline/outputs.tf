output "iot_topic_rule" {
  description = "센서가 발행할 MQTT 토픽 (factory/sensors/+)"
  value = "factory/sensors/<device_id>"
}

output "kinesis_stream_name" {
  description = "데이터 수집 Kinesis 스트림 이름"
  value = aws_kinesis_stream.ingest.name
}

output "dynamodb_table" {
  description = "실시간 조회용 DynamoDB 테이블"
  value = aws_dynamodb_table.sensor.name
}

output "raw_bucket" {
  description = "원본 데이터 적재 S3 버킷"
  value = aws_s3_bucket.raw.bucket
}

output "alerts_topic_arn" {
  description = "임계치 알림 SNS 토픽 ARN"
  value = aws_sns_topic.alerts.arn
}
