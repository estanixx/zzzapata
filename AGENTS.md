# AGENTS.md

Mechanical conventions for this repository. Written for an agent or a rushed
contributor — terse, numbered, no prose padding. If something here conflicts
with a `.tf` file's own comments, the `.tf` file wins; open a PR fixing this
doc. For the "what is this and how does it work" narrative, see
[`README.md`](./README.md) (Spanish — see §8 below).

## 1. Delivery model

Trunk-based. Every PR merges to `main` (squash-merge by default, so `main`
stays one commit per PR). One logical change per PR — an unrelated fix found
along the way gets its own branch.

**Chained/stacked PRs are an explicit exception**, used only when a single
logical change would otherwise exceed the review budget (~400-800 changed
lines). A chained PR's branch bases on the previous PR's branch, not `main`;
it retargets to `main` once the parent PR merges, and its GitHub diff must
show only its own files before merging.

## 2. Branch & commit naming

README §3 is authoritative — this repo does not use dcuero-iac's
`<type>/<short-uuid>-<slug>` scheme.

- **Branches**: `<tipo>/<kebab-case-slug>`, no uppercase, no spaces.
  `<tipo>` is one of `feat`, `fix`, `chore`, `infra`, `ci`, `docs`,
  `refactor`. Examples: `infra/bootstrap-trust-anchor`, `fix/join-timeout-handling`.
- **Commits and PR titles**: Conventional Commits, `<tipo>(<scope opcional>):
  <summary>` — imperative mood, lowercase, no trailing period. `test` is also
  a valid commit type (not used for PR titles). Examples:
  `infra(bootstrap): add github oidc trust anchor and ecr repo`,
  `fix(bot): handle "ask to join" approval timeout`.
- **Never** add a `Co-Authored-By` line or any AI-attribution trailer to a
  commit or PR description.

## 3. Terraform change discipline

- **Always `terraform plan` before `apply`.** `bootstrap/` is never applied
  by CI (see §5 rationale) — it is applied manually from local `iamadmin`
  credentials; read the plan output every time before applying.
- **Treat any `-/+` (replace) or bare `-` (destroy) on a stateful resource as
  a stop-and-check moment.** Once the EFS module and its file system exist,
  call it out by name: destroying it deletes the authenticated Chrome
  profile and forces a manual, interactive Google 2FA re-login. Same
  scrutiny for the `aws_ecr_repository.join_bot` repository (image history
  loss) and either OIDC role's trust policy.
- **State/backend**: every root uses a partial S3 backend (`bucket` omitted
  from `backend.tf` on purpose — it is only known once `bootstrap/` has
  been applied). Init with `./scripts/tf-init.sh <root>` (needs
  `TF_STATE_BUCKET` exported), never raw `terraform init`. Locking is native
  S3 conditional writes (`use_lockfile = true`) — no DynamoDB lock table —
  which requires the state bucket to have versioning enabled (verified
  `Enabled` on `central-tfstate-estanix-871696174477`).
- `bootstrap/` is never touched by CI, in any workflow, in any slice.

## 4. IAM / security conventions

- **Resource-name-prefix scoping.** Every resource this repo's CI creates is
  named `zzzapata-*`, and every management-level IAM grant in
  `bootstrap/iam.tf` is scoped to that prefix, not the whole account
  (`role/zzzapata-*`, `repository/zzzapata-*`, `parameter/zzzapata/prod/*`,
  `schedule/zzzapata*/*`, `log-group:/ecs/zzzapata-*`, ...). A resource named
  outside `zzzapata-*`, or a new AWS service, needs its own explicit
  `bootstrap/iam.tf` grant — nothing is implicitly covered.
- **Mandatory permissions boundary on every CI-created role.** The apply
  role's `iam:CreateRole`/`iam:PutRolePermissionsBoundary` grant is
  conditioned on `zzzapata-runtime-boundary` being attached
  (`CreateScopedRuntimeRoles` in `iam.tf`) — a role created without it 403s.
- **Runtime roles use inline `aws_iam_role_policy` only.** The apply role has
  no `iam:CreatePolicy*` grant, by design — this keeps the blast radius
  inside `role/zzzapata-*` and avoids an account-wide policy-creation grant.
- **Explicit `Deny` always wins over any `Allow`.** Before assuming a new
  apply-role `Allow` statement is sufficient, check it against both
  `zzzapata-apply-boundary` and (for CI-created runtime roles)
  `zzzapata-runtime-boundary` — see `bootstrap/iam.tf`'s own
  boundary-vs-allow cross-check comment tables for the reasoning and the
  exact shadowing class this guards against (a blanket `Deny iam:*` would
  block the scheduler role's required `iam:PassRole`).
- **A `SecureString` is never a Terraform resource, nor a data source.**
  Either would force a plan role's `ssm:GetParameter` grant to decrypt and
  persist the plaintext into state on every plan.

## 5. "The apply role lags the feature"

A new AWS service, or a resource named outside `zzzapata-*`, has no implicit
grant. CI fails first, by design — this is expected, not a bug to route
around. Procedure:

1. Read the exact denied action + resource from the `cd.yml` failure.
2. Add the narrowest possible statement to `bootstrap/iam.tf`.
3. Verify `zzzapata-apply-boundary` (and `zzzapata-runtime-boundary`, if the
   grant is for a CI-created role) does not `Deny` it — see §4.
4. Open an `infra(iam): ...` PR.
5. An admin re-applies `bootstrap/` locally with `iamadmin` credentials.
6. Re-run `cd.yml`.

If the fix was already applied live to unblock the pipeline, say so in the
PR description — the PR is syncing code to already-applied state, it is not
proposing an untested change.

## 6. Pre-PR checklist

Run from the repo root before pushing:

```bash
terraform fmt -check -recursive
tflint --recursive
```

Plus, for every root module the change touches:

```bash
cd bootstrap    # or environments/prod once it exists
terraform validate
terraform plan  # or -backend=false + validate only, if no backend is configured locally
```

Plus, from the repo root:

```bash
checkov -d . --config-file .checkov.yml
```

`.checkov.yml` is a closed skip-list with a one-line rationale per skipped
ID — a new finding not already listed blocks the PR.

**PR description must always include:**

- **Summary** — what changed and why.
- **Test plan** — commands actually run and their outcome (`terraform
  validate`/`plan`, `tflint`, `checkov`). "Verified locally" alone is not a
  test plan.
- If a fix was already applied directly against live infra, say so
  explicitly (see §5).

## 7. Where things live

```
bootstrap/                 trust anchor (OIDC IAM roles, ECR repo) — remote
                            state, admin-applied only, never touched by CI
  backend.tf                 partial S3 backend, key zzzapata/bootstrap/terraform.tfstate
  iam.tf                     2 OIDC roles (plan/apply), 3 permissions boundaries
  ecr.tf                     zzzapata-join-bot (IMMUTABLE, scan-on-push)
  README.md                  manual apply runbook
environments/prod/         (not yet created — slice 2+) runtime infra root,
                            key zzzapata/prod/terraform.tfstate
modules/                    (not yet created) network, efs-chrome-profile,
                            ecs-join-bot, scheduler — see .tflint.hcl's comment
scripts/tf-init.sh          wraps terraform init for a root's partial S3 backend
.github/workflows/          (not yet created — slice ci-cd-skeleton)
.tflint.hcl                 aws ruleset pinned 0.48.0
.checkov.yml                repo-root checkov skip-list, with rationale per finding
```

## 8. Repo language

`README.md` stays Spanish, as authored. Every new technical artifact — code
comments, this file, future docs — is English.
