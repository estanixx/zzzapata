variable "github_org" {
  description = "GitHub organization or user that owns the repository. Scopes the OIDC trust policy `sub` condition."
  type        = string
  default     = "estanixx"
}

variable "github_repo" {
  description = "GitHub repository name. Scopes the OIDC trust policy `sub` condition."
  type        = string
  default     = "zzzapata"
}

# GitHub's default OIDC `sub` claim prefix embeds these immutable numeric IDs
# (`repo:<org>@<org_id>/<repo>@<repo_id>:...`), not the plain `repo:<org>/<repo>`
# form older docs show. The IDs survive an org/repo rename, which is why the
# trust policy pins them under StringEquals. Re-derive with:
#   gh api repos/estanixx/zzzapata --jq '.owner.id, .id'
variable "github_org_id" {
  description = "Immutable GitHub organization/user ID, embedded in the default OIDC `sub` claim prefix."
  type        = string
  default     = "43096620"
}

variable "github_repo_id" {
  description = "Immutable GitHub repository ID, embedded in the default OIDC `sub` claim prefix."
  type        = string
  default     = "1356201610"
}

variable "region" {
  description = "AWS region for all bootstrap IAM and ECR resources."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix applied to every bootstrap resource name (IAM roles, IAM policies, ECR repository)."
  type        = string
  default     = "zzzapata"
}

variable "profile" {
  description = "AWS profile for the manual bootstrap apply. Empty string (default) means no override — ambient credentials are used (required in CI, which has no named local profile). Set via TF_VAR_profile or -var locally if your account needs a specific profile."
  type        = string
  default     = ""
}

variable "state_bucket_name" {
  description = "Name of the externally-owned S3 bucket that holds Terraform state for every root module in this repo. Not a resource — this repo consumes the bucket but never creates it. Needed to build the state-object ARNs the OIDC roles are scoped to."
  type        = string
  default     = "central-tfstate-estanix-871696174477"
}
