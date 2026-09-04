terraform {
  # Partial backend config: `bucket` is injected at `terraform init` time via
  # -backend-config (see README.md). The state bucket
  # (central-tfstate-estanix-871696174477) is externally owned — this repo
  # consumes it but never declares or manages it.
  #
  # Native S3 locking (`use_lockfile = true`, Terraform >= 1.11) writes a
  # `<key>.tflock` object; the bucket already has versioning Enabled, which is
  # the only precondition. No DynamoDB lock table.
  backend "s3" {
    key          = "zzzapata/bootstrap/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
