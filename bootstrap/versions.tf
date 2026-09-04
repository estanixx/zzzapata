terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # No `tls` provider: a thumbprint is only needed when *creating* an
  # aws_iam_openid_connect_provider. This root data-sources the account's
  # existing GitHub OIDC provider (see github_oidc.tf), so no TLS lookup.
}
