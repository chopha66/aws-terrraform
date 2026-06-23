variable "aws_region" {
  description = "AWS Region"
  type = string
  default = "ap-northeast-2"
}

variable "project_name" {
  description = "Resource Name Prefix"
  type = string
  default = "shop-eks"
}

variable "environment" {
  description = "Deploy Environment (dev/stage/prod)"
  type = string
  default = "dev"
}

variable "vpc_cidr" {
  description = "The VPC CIDR Block"
  type = string
  default = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "AZ List"
  type = list(string)
  default = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "eks_version" {
  description = "EKS Version"
  type = string
  default  = "1.35"
}

variable "node_instance_types" {
  description = "EKS Node Group Instance Type"
  type = list(string)
  default = ["t3.medium"]
}

variable "node_desired_size" {
  description = "EKS Node Group Desired Size"
  type = number
  default = 2
}

variable "node_min_size" {
  description = "EKS Node Group Mininum Size"
  type = number
  default = 2
}

variable "node_max_size" {
  description = "EKS Node Group Maximum Size"
  type = number
  default = 6
}
