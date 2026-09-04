provider "aws" {
  region  = var.aws_region
  profile = var.profile != "" ? var.profile : null

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}
