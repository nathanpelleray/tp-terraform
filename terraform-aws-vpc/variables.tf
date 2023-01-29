variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "cidr_block" {
  type        = string
  description = "The CIDR block use by the vpc"
}

variable "vpc_name" {
  type        = string
  description = "The name of the vpc"
}

variable "azs" {
  type = map(any)
  default = {
    "a" = 0,
    "b" = 1,
    "c" = 2,
  }
  description = "List of AZs to the vpc"
}
