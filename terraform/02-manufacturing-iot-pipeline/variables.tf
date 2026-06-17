variable "aws_region" {
  description = "AWS Region"
  type = string
  default = "ap-northeast-2"
}

variable "project_name" {
  description = "Resource Name Prefix"
  type = string
  default = "manufacturing-iot"
}

variable "environment" {
  description = "Deploy Environment (dev/stage/prod)"
  type = string
  default = "dev"
}

variable "kinesis_shard_count" {
  description = "The number of Kinesis Stream Shard"
  type = number
  default = 1
}

variable "temperature_threshold" {
  description = "Temperature threshold for alert(℃)"
  type = number
  default = 80
}

variable "alert_email" {
  description = "E-mail address for alert"
  type = string
  default = ""
}
