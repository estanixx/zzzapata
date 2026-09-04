data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # GitHub's default OIDC `sub` prefix. The exact per-role `sub` values append
  # `:pull_request` (plan) and `:ref:refs/heads/main` (apply) — see iam.tf.
  oidc_sub_prefix = "repo:${var.github_org}@${var.github_org_id}/${var.github_repo}@${var.github_repo_id}"

  plan_role_name        = "${var.name_prefix}-github-actions-plan"
  apply_role_name       = "${var.name_prefix}-github-actions-apply"
  plan_permissions_name = "${var.name_prefix}-github-actions-plan-permissions"
  runtime_boundary_name = "${var.name_prefix}-runtime-boundary"
  apply_boundary_name   = "${var.name_prefix}-apply-boundary"

  # Computed as strings, NOT read off the resource attributes: the apply-role
  # permissions boundary must reference the apply role's own ARN (and the
  # boundary policy ARNs), which is circular if taken from the resource —
  # aws_iam_role.apply needs aws_iam_policy.apply_boundary.arn to be created.
  plan_role_arn        = "arn:aws:iam::${local.account_id}:role/${local.plan_role_name}"
  apply_role_arn       = "arn:aws:iam::${local.account_id}:role/${local.apply_role_name}"
  plan_permissions_arn = "arn:aws:iam::${local.account_id}:policy/${local.plan_permissions_name}"
  runtime_boundary_arn = "arn:aws:iam::${local.account_id}:policy/${local.runtime_boundary_name}"
  apply_boundary_arn   = "arn:aws:iam::${local.account_id}:policy/${local.apply_boundary_name}"

  state_bucket_arn = "arn:aws:s3:::${var.state_bucket_name}"

  # The prod root (a later slice) keys its state under this prefix. The plan /
  # apply roles are scoped to it; they must never touch zzzapata/bootstrap/*
  # (this root's own trust-anchor state).
  prod_state_key       = "zzzapata/prod/terraform.tfstate"
  prod_state_lock_key  = "zzzapata/prod/terraform.tfstate.tflock"
  prod_state_prefix    = "zzzapata/prod/*"
  bootstrap_state_glob = "zzzapata/bootstrap/*"
}
