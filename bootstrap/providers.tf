provider "aws" {
  region = var.region

  # null (not "") when unset: an empty-string profile argument still makes the
  # AWS SDK look up a profile literally named "" and fail. CI authenticates via
  # OIDC-issued env credentials and has no named local profile; a human running
  # the manual bootstrap apply sets TF_VAR_profile or -var if their account
  # needs one.
  profile = var.profile != "" ? var.profile : null

  default_tags {
    tags = {
      Project     = "zzzapata"
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}
