variable "certificate_arn" {
  description = "The ARN of the SSL certificate to attach to the ALB"
  type        = string
  default     = "arn:aws:acm:eu-west-1:597088032758:certificate/425ad047-58bb-49a1-9925-faccf1cacde0"
}

variable "hosted_zone_id" {
  description = "The ID of the Route53 hosted zone where the DNS record will be created."
  type        = string
  default     = "Z09193361LF7GGPR453HY"
}