terraform {
  backend "s3" {
    key          = "zzzapata/prod/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
