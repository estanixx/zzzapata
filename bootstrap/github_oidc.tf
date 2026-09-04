# The account's single GitHub Actions OIDC provider already exists
# (arn:aws:iam::871696174477:oidc-provider/token.actions.githubusercontent.com,
# verified live). It is data-sourced here, never created:
#
#   - AWS rejects a second provider registration for the same URL, so an
#     `aws_iam_openid_connect_provider` resource would hard-fail on apply.
#   - This root is one consumer of the account trust anchor; it has no business
#     owning it. `terraform destroy` on bootstrap/ must not remove it.
#
# `aws_iam_openid_connect_provider` has no get-by-URL API — the provider lists
# every OIDC provider in the account and matches the URL client-side. That is
# why the plan/apply roles keep `iam:List*` (see iam.tf).
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}
