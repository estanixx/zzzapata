# `bootstrap/` — GitHub Actions trust anchor (manual apply)

Creates the account-level resources every CI workflow in this repo depends on:

| Resource | Purpose |
|---|---|
| `zzzapata-github-actions-plan` (IAM role) | Assumed by `pr.yml` via OIDC on `pull_request`. Read-only. Its permissions boundary is its own identity policy. |
| `zzzapata-github-actions-apply` (IAM role) | Assumed by `cd.yml` via OIDC on push to `main`. Scoped write (`zzzapata-*`). Boundary: `zzzapata-apply-boundary`. |
| `zzzapata-github-actions-plan-permissions` (IAM policy) | Read-only grant; attached twice (identity + boundary). |
| `zzzapata-runtime-boundary` (IAM policy) | Permissions boundary every CI-created runtime role (`zzzapata-ecs-task`, `-ecs-exec`, `-scheduler`) must carry. |
| `zzzapata-apply-boundary` (IAM policy) | Caps the apply role — see `iam.tf`. |
| `zzzapata-join-bot` (ECR repo + lifecycle policy) | Meeting join-bot image. `IMMUTABLE` tags, scan-on-push, keep last 10. |

A clean `terraform plan` here adds **9 resources, 0 to change, 0 to destroy**.
The GitHub OIDC provider and the S3 state bucket are **data sources**, never
created.

**This root is never applied by CI.** It is applied by a human admin with
`iamadmin` credentials. CI only ever *assumes* the roles it produces — the
"apply role lags the feature" convention in `AGENTS.md` is the routine path for
extending its grants.

State is stored remotely (S3 key `zzzapata/bootstrap/terraform.tfstate`,
native `use_lockfile` locking, no DynamoDB). Unlike dcuero-iac, there is no
chicken-and-egg problem: the bucket `central-tfstate-estanix-871696174477` is
pre-existing and externally owned.

## Prerequisites

- Terraform `>= 1.11`, AWS provider `~> 5.0`
- `iamadmin` credentials active in your shell for account `871696174477`
- The GitHub OIDC provider already registered in the account (it is — verified)

## Apply runbook

```bash
# 0. Preconditions — ALREADY VERIFIED 2026-09-03, re-run only if the account
#    or the bucket may have changed since. All four were clear:
aws sts get-caller-identity                                                     # -> account 871696174477
aws s3api get-bucket-versioning  --bucket central-tfstate-estanix-871696174477  # -> Enabled
aws s3api get-bucket-encryption  --bucket central-tfstate-estanix-871696174477  # -> AES256 (SSE-S3), NOT a KMS CMK
aws s3api get-bucket-policy      --bucket central-tfstate-estanix-871696174477  # -> NoSuchBucketPolicy (nothing restricting principals)
```

Because encryption is SSE-S3 (not a KMS CMK) and there is no restrictive bucket
policy, the OIDC roles need **no** out-of-band `kms:*` grant or bucket-policy
principal entry for state access. If either fact ever changes, both roles need
matching grants added before they can read/write state.

```bash
# 1. Init against the shared bucket. scripts/tf-init.sh does not exist yet in
#    this PR (it ships in the repo-meta PR), so init directly:
cd bootstrap
terraform init \
  -backend-config="bucket=central-tfstate-estanix-871696174477" \
  -backend-config="region=us-east-1"

# 2. Plan and REVIEW. Expect: 9 to add, 0 to change, 0 to destroy.
#    Confirm the GitHub OIDC provider appears as a data source, never a create.
terraform plan
terraform apply

# 3. Publish outputs as GitHub Actions VARIABLES (not secrets — the sub
#    StringEquals condition is the control, and readable values help debug a 403).
gh variable set TF_STATE_BUCKET      --body "$(terraform output -raw state_bucket_name)"
gh variable set AWS_REGION           --body "us-east-1"
gh variable set AWS_PLAN_ROLE_ARN    --body "$(terraform output -raw plan_role_arn)"
gh variable set AWS_APPLY_ROLE_ARN   --body "$(terraform output -raw apply_role_arn)"
gh variable set RUNTIME_BOUNDARY_ARN --body "$(terraform output -raw runtime_boundary_arn)"
gh variable set ECR_REPOSITORY_URL   --body "$(terraform output -raw ecr_repository_url)"

# 4. Commit bootstrap/.terraform.lock.hcl into this PR.
```

## Post-apply verification (live probes)

- Assume `zzzapata-github-actions-plan` → `terraform plan` on the prod root
  succeeds; any write call is denied.
- Assume `zzzapata-github-actions-apply` → `iam:UpdateAssumeRolePolicy` on
  itself is denied; `s3:PutBucketVersioning` on the state bucket is denied.
- `aws ecr describe-repositories --repository-names zzzapata-join-bot` shows
  `imageTagMutability = IMMUTABLE` and `scanOnPush = true`.

## Rollback

`terraform destroy` in `bootstrap/` removes the 9 resources. The data-sourced
OIDC provider and the state bucket are untouched. Then delete the
`zzzapata/bootstrap/terraform.tfstate` object and unset the six GitHub
variables. Nothing else consumes these resources until the CI slice lands.

## EFS-deletion escape hatch

`zzzapata-apply-boundary` denies `elasticfilesystem:DeleteFileSystem`. A PR
that legitimately removes the EFS module will 403 at `cd.yml` apply and wedge
`main`. This is deliberate — the file system holds the authenticated Chrome
profile, and re-creating it costs a manual, interactive Google 2FA login. To
proceed: an admin removes the `DenyEfsFileSystemDeletion` statement from
`iam.tf`, re-applies `bootstrap/` locally, merges the EFS-removal PR, then
restores the statement in a follow-up. The EFS module itself should also carry
`lifecycle { prevent_destroy = true }` as defence in depth.

## Why bootstrap is never CI-applied

Applying this root requires broad IAM privileges (creating roles, boundaries,
policies). Handing those to an OIDC role would make the CI pipeline able to
rewrite its own trust anchor — exactly what the two-role plan/apply split and
the boundaries exist to prevent. The manual apply is rare (only when the apply
role's grants need widening) and always runs under a human admin's credentials.
