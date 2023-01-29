variable "aws_region" {
  type        = string
  description = "AWS Region"
  default     = "us-east-1"
}

variable "vpc_name" {
  type    = string
  description = "VPC name"
  default = "upjv-cloud"
}

variable "app_name" {
  type = string
  description = "Application name"
  default = "restaurant"
}
