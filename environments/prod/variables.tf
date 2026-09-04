variable "project_name" {
  description = "Project name, used for resource naming and tagging."
  type        = string
  default     = "zzzapata"
}

variable "aws_region" {
  description = "AWS region this root deploys into."
  type        = string
  default     = "us-east-1"
}

variable "profile" {
  description = "Named AWS CLI profile for local runs. Default \"\" is treated as null in providers.tf — an empty-string profile argument would make the AWS SDK look up a profile literally named \"\" and fail. CI authenticates via OIDC-issued env credentials and needs no profile."
  type        = string
  default     = ""
}
