# =============================================================================
# GitHub Actions OIDC trust anchor — two roles
#
#   zzzapata-github-actions-plan   read-only,  trusted for the `pull_request` event
#   zzzapata-github-actions-apply  scoped write, trusted only for push -> refs/heads/main
#
# Every trust policy uses StringEquals (never StringLike) on both `aud` and
# `sub`. The repo is PUBLIC, so a fork's `pull_request` OIDC token is only
# stopped from assuming the plan role by the exact `sub` match — a wildcard
# would be directly exploitable.
#
# Build order in this file (each layer only references things above it):
#   1. plan trust doc
#   2. plan_permissions doc  (identity policy AND its own permissions boundary)
#   3. runtime_boundary doc  (cap on the CI-created ECS/scheduler roles)
#   4. apply trust doc
#   5. apply_permissions doc (23-Sid scoped-write identity policy)
#   6. apply_boundary doc    (cap on the apply role itself)
#   7. policy + role + attachment resources
#   8. boundary-vs-allow cross-check (comment tables at the end)
# =============================================================================

# --- 1. Plan role: trust -----------------------------------------------------

data "aws_iam_policy_document" "plan_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.oidc_sub_prefix}:pull_request"]
    }
  }
}

# --- 2. Plan role: read-only permissions (also its own permissions boundary) -
#
# `terraform plan` never persists state, so s3:PutObject on the state object
# itself is deliberately absent — the only write grant is the `.tflock` object.
# This same policy is attached as the role's identity policy AND as its
# permissions boundary, so a future mis-attached AdministratorAccess still
# cannot make the plan role mutating. No zzzapata/bootstrap/* grant: the plan
# role must never read its own trust anchor's state.

data "aws_iam_policy_document" "plan_permissions" {
  statement {
    sid    = "ReadAwsSurface"
    effect = "Allow"
    actions = [
      "ecs:Describe*",
      "ecs:List*",
      "elasticfilesystem:Describe*",
      "elasticfilesystem:ListTagsForResource",
      "ec2:Describe*",
      "scheduler:Get*",
      "scheduler:List*",
      "logs:Describe*",
      "logs:ListTagsForResource",
      "ecr:Describe*",
      "ecr:List*",
      "ecr:GetLifecyclePolicy",
      "ecr:GetRepositoryPolicy",
      "sns:Get*",
      "sns:List*",
      "iam:Get*",
      "iam:List*",
      "ssm:DescribeParameters",
      "ssm:GetParameter*",
      "ssm:ListTagsForResource",
      "kms:DescribeKey",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ReadState"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${local.state_bucket_arn}/${local.prod_state_key}"]
  }

  statement {
    sid    = "TakeStateLock"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${local.state_bucket_arn}/${local.prod_state_lock_key}"]
  }

  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [local.prod_state_prefix]
    }
  }
}

# --- 3. Runtime boundary ----------------------------------------------------
#
# `zzzapata-runtime-boundary` caps every role the apply role creates at
# runtime: zzzapata-ecs-task, zzzapata-ecs-exec, zzzapata-scheduler.
#
# NOT dcuero's blanket `Deny iam:*`: the EventBridge Scheduler invoke role must
# call iam:PassRole to hand the task/exec roles to ECS RunTask. A blanket deny
# would shadow that grant and 403 every scheduled meeting at invocation.
# DenyIamMutation + DenyPassRoleOutsideEcs denies all mutating IAM while
# leaving a PassedToService-constrained PassRole reachable. iam:Get*/List* are
# not denied.

data "aws_iam_policy_document" "runtime_boundary" {
  statement {
    sid       = "AllowWithinBoundary"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyIamMutation"
    effect = "Deny"
    actions = [
      "iam:Create*",
      "iam:Delete*",
      "iam:Update*",
      "iam:Put*",
      "iam:Attach*",
      "iam:Detach*",
      "iam:Add*",
      "iam:Remove*",
      "iam:Tag*",
      "iam:Untag*",
      "iam:Set*",
      "iam:Upload*",
      "iam:ChangePassword",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DenyPassRoleOutsideEcs"
    effect    = "Deny"
    actions   = ["iam:PassRole"]
    resources = ["*"]

    condition {
      test     = "StringNotEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid    = "DenyRoleChaining"
    effect = "Deny"
    actions = [
      "sts:AssumeRole",
      "sts:AssumeRoleWithSAML",
      "sts:AssumeRoleWithWebIdentity",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DenyStateBucketAccess"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [local.state_bucket_arn, "${local.state_bucket_arn}/*"]
  }

  statement {
    sid    = "DenyAccountAndOrgManagement"
    effect = "Deny"
    actions = [
      "organizations:*",
      "account:*",
    ]
    resources = ["*"]
  }
}

# --- 4. Apply role: trust --------------------------------------------------

data "aws_iam_policy_document" "apply_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.oidc_sub_prefix}:ref:refs/heads/main"]
    }
  }
}

# --- 5. Apply role: scoped-write identity policy (23 Sids) ----------------
#
# Everything is resource-scoped to zzzapata-* / role/zzzapata-* /
# parameter/zzzapata/prod/*. `*` appears only for actions with no IAM
# resource-level support (Describe*, RegisterTaskDefinition, GetAuthorizationToken,
# List*, GetCallerIdentity, CreateFileSystem). No statement is `*:*`.

data "aws_iam_policy_document" "apply_permissions" {
  # 1
  statement {
    sid     = "EcsScopedManagement"
    effect  = "Allow"
    actions = ["ecs:*"]
    resources = [
      "arn:aws:ecs:${var.region}:${local.account_id}:cluster/zzzapata-*",
      "arn:aws:ecs:${var.region}:${local.account_id}:task-definition/zzzapata-*:*",
      "arn:aws:ecs:${var.region}:${local.account_id}:service/zzzapata-*/*",
    ]
  }

  # 2 — no IAM resource-level support (a fresh task-def revision ARN does not
  # exist before Register).
  statement {
    sid    = "EcsNonScopableActions"
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:ListClusters",
      "ecs:ListTaskDefinitions",
      "ecs:ListTaskDefinitionFamilies",
    ]
    resources = ["*"]
  }

  # 3 — EFS IDs are AWS-generated and unprefixable; capped by runtime/apply boundary.
  statement {
    sid     = "EfsResourceManagement"
    effect  = "Allow"
    actions = ["elasticfilesystem:*"]
    resources = [
      "arn:aws:elasticfilesystem:${var.region}:${local.account_id}:file-system/*",
      "arn:aws:elasticfilesystem:${var.region}:${local.account_id}:access-point/*",
    ]
  }

  # 4
  statement {
    sid       = "EfsCreate"
    effect    = "Allow"
    actions   = ["elasticfilesystem:CreateFileSystem"]
    resources = ["*"]
  }

  # 5 — VPC/SG/RT/IGW IDs are unknown pre-creation.
  statement {
    sid    = "Ec2NetworkManagement"
    effect = "Allow"
    actions = [
      "ec2:*Vpc*",
      "ec2:*Subnet*",
      "ec2:*RouteTable*",
      "ec2:*Route",
      "ec2:*InternetGateway*",
      "ec2:*SecurityGroup*",
      "ec2:Describe*",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["*"]
  }

  # 6 — defensive: ENI attachment at task launch is done by
  # AWSServiceRoleForECS, not this role; covers refresh/Describe paths.
  statement {
    sid       = "Ec2NetworkInterface"
    effect    = "Allow"
    actions   = ["ec2:*NetworkInterface*"]
    resources = ["*"]
  }

  # 7
  statement {
    sid     = "SchedulerManagement"
    effect  = "Allow"
    actions = ["scheduler:*"]
    resources = [
      "arn:aws:scheduler:${var.region}:${local.account_id}:schedule/zzzapata*/*",
      "arn:aws:scheduler:${var.region}:${local.account_id}:schedule-group/zzzapata*",
    ]
  }

  # 8
  statement {
    sid    = "SchedulerList"
    effect = "Allow"
    actions = [
      "scheduler:ListSchedules",
      "scheduler:ListScheduleGroups",
    ]
    resources = ["*"]
  }

  # 9
  statement {
    sid     = "LogsManagement"
    effect  = "Allow"
    actions = ["logs:*"]
    resources = [
      "arn:aws:logs:${var.region}:${local.account_id}:log-group:/ecs/zzzapata-*",
      "arn:aws:logs:${var.region}:${local.account_id}:log-group:/ecs/zzzapata-*:*",
    ]
  }

  # 10
  statement {
    sid       = "LogsDescribe"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  # 11
  statement {
    sid       = "EcrManagement"
    effect    = "Allow"
    actions   = ["ecr:*"]
    resources = ["arn:aws:ecr:${var.region}:${local.account_id}:repository/zzzapata-*"]
  }

  # 12 — non-scopable; required for `docker login` in cd.yml.
  statement {
    sid       = "EcrAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # 13
  statement {
    sid       = "SsmParameterAccess"
    effect    = "Allow"
    actions   = ["ssm:*"]
    resources = ["arn:aws:ssm:${var.region}:${local.account_id}:parameter/zzzapata/prod/*"]
  }

  # 14 — DescribeParameters has no resource-level support; scoping it silently 403s.
  statement {
    sid       = "SsmDescribeParameters"
    effect    = "Allow"
    actions   = ["ssm:DescribeParameters"]
    resources = ["*"]
  }

  # 15
  statement {
    sid       = "SnsManagement"
    effect    = "Allow"
    actions   = ["sns:*"]
    resources = ["arn:aws:sns:${var.region}:${local.account_id}:zzzapata-*"]
  }

  # 16
  statement {
    sid    = "SnsList"
    effect = "Allow"
    actions = [
      "sns:ListTopics",
      "sns:ListSubscriptions",
    ]
    resources = ["*"]
  }

  # 17
  statement {
    sid    = "StateObjectCrud"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${local.state_bucket_arn}/${local.prod_state_prefix}"]
  }

  # 18
  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [local.prod_state_prefix]
    }
  }

  # 19 — CreateRole only for zzzapata-* roles that carry the runtime boundary.
  statement {
    sid    = "CreateScopedRuntimeRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:PutRolePermissionsBoundary",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/zzzapata-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.runtime_boundary_arn]
    }
  }

  # 20
  statement {
    sid    = "ManageScopedRuntimeRoles"
    effect = "Allow"
    actions = [
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListRoleTags",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/zzzapata-*"]
  }

  # 21
  statement {
    sid       = "PassRuntimeRoles"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/zzzapata-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com", "scheduler.amazonaws.com"]
    }
  }

  # 22 — the grant that actually matters for the first-ever ECS task in this account.
  statement {
    sid       = "CreateEcsServiceLinkedRole"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/aws-service-role/ecs.amazonaws.com/AWSServiceRoleForECS"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["ecs.amazonaws.com"]
    }
  }

  # 23
  statement {
    sid       = "StsIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

# --- 6. Apply role: permissions boundary ---------------------------------
#
# References the plan/apply role ARNs and the two boundary policy ARNs as
# *computed* locals (see main.tf), not resource attributes — the apply role
# needs this boundary created first, so the boundary cannot depend on it.

data "aws_iam_policy_document" "apply_boundary" {
  statement {
    sid       = "AllowWithinBoundary"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  # `not_actions` (not `actions`): deny every IAM action on the trust-anchor
  # resources EXCEPT reads. A blanket `iam:*` deny would also block the apply
  # role's own iam:Get*/List* (needed to data-source the OIDC provider) — an
  # explicit Deny always beats an Allow.
  statement {
    sid    = "DenyTrustAnchorMutation"
    effect = "Deny"
    not_actions = [
      "iam:Get*",
      "iam:List*",
    ]
    resources = [
      local.plan_role_arn,
      local.apply_role_arn,
      data.aws_iam_openid_connect_provider.github.arn,
      local.apply_boundary_arn,
      local.runtime_boundary_arn,
      local.plan_permissions_arn,
    ]
  }

  statement {
    sid    = "DenyStateBucketConfigMutation"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
      "s3:PutBucketPolicy",
      "s3:PutBucketVersioning",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutEncryptionConfiguration",
      "s3:PutLifecycleConfiguration",
    ]
    resources = [local.state_bucket_arn]
  }

  statement {
    sid       = "DenyBootstrapStateAccess"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = ["${local.state_bucket_arn}/${local.bootstrap_state_glob}"]
  }

  statement {
    sid       = "DenyEcrRepositoryDeletion"
    effect    = "Deny"
    actions   = ["ecr:DeleteRepository"]
    resources = ["arn:aws:ecr:${var.region}:${local.account_id}:repository/${var.name_prefix}-join-bot"]
  }

  # Deleting the EFS file system destroys the authenticated Chrome profile and
  # forces a manual Google 2FA re-login. Escape hatch: an admin removes this
  # statement, re-applies bootstrap/ locally, then re-runs cd. See README.md.
  statement {
    sid       = "DenyEfsFileSystemDeletion"
    effect    = "Deny"
    actions   = ["elasticfilesystem:DeleteFileSystem"]
    resources = ["arn:aws:elasticfilesystem:${var.region}:${local.account_id}:file-system/*"]
  }

  # `ec2:*Vpc*` in grant #5 silently matches CreateVpcPeeringConnection — a
  # cross-account data path. CreateVpcEndpoint is intentionally NOT denied.
  statement {
    sid    = "DenyVpcPeeringAndTransit"
    effect = "Deny"
    actions = [
      "ec2:*VpcPeering*",
      "ec2:*TransitGateway*",
      "ec2:*VpcEndpointService*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyIamUserCreation"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:CreateLoginProfile",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyAccountAndOrgManagement"
    effect = "Deny"
    actions = [
      "organizations:*",
      "account:*",
    ]
    resources = ["*"]
  }
}

# --- 7. Policy + role + attachment resources ----------------------------

resource "aws_iam_policy" "plan_permissions" {
  name        = local.plan_permissions_name
  description = "Read-only permissions for the Terraform plan role; also attached as its permissions boundary."
  policy      = data.aws_iam_policy_document.plan_permissions.json
}

resource "aws_iam_policy" "runtime_boundary" {
  name        = local.runtime_boundary_name
  description = "Permissions boundary required on every runtime role the apply role creates (zzzapata-ecs-task, -ecs-exec, -scheduler)."
  policy      = data.aws_iam_policy_document.runtime_boundary.json
}

resource "aws_iam_policy" "apply_boundary" {
  name        = local.apply_boundary_name
  description = "Caps the apply role: cannot rewrite its own OIDC trust anchor, cannot break state-bucket protections, cannot delete the ECR repo or the EFS file system, no VPC peering/transit, no IAM users, no org/account management."
  policy      = data.aws_iam_policy_document.apply_boundary.json
}

resource "aws_iam_role" "plan" {
  name                 = local.plan_role_name
  description          = "Assumed by pr.yml via OIDC to run `terraform plan` against zzzapata/prod. Read-only."
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  permissions_boundary = aws_iam_policy.plan_permissions.arn
}

resource "aws_iam_role_policy_attachment" "plan" {
  role       = aws_iam_role.plan.name
  policy_arn = aws_iam_policy.plan_permissions.arn
}

resource "aws_iam_role" "apply" {
  name                 = local.apply_role_name
  description          = "Assumed by cd.yml via OIDC to run `terraform apply` against zzzapata/prod. Scoped write."
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  permissions_boundary = aws_iam_policy.apply_boundary.arn
}

resource "aws_iam_role_policy" "apply" {
  name   = "${local.apply_role_name}-permissions"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply_permissions.json
}

# =============================================================================
# 8. EXPLICIT boundary-vs-allow cross-check
#
# Effective permission = identity Allow ∩ boundary Allow − any boundary Deny.
# Every apply-role Allow checked against every apply_boundary Deny:
#
#   #  Allow                         Verdict vs apply_boundary
#   -- ---------------------------   -----------------------------------------
#   1  EcsScopedManagement           OK   — no ecs: Deny exists
#   2  EcsNonScopableActions         OK
#   3  EfsResourceManagement         PARTIAL (intentional) — DenyEfsFileSystemDeletion
#                                    shadows elasticfilesystem:DeleteFileSystem;
#                                    every other EFS action passes
#   4  EfsCreate                     OK   — Deny is on Delete*, disjoint from Create
#   5  Ec2NetworkManagement          PARTIAL (intentional) — DenyVpcPeeringAndTransit
#                                    shadows *VpcPeering*/*TransitGateway*/
#                                    *VpcEndpointService*; VPC/subnet/IGW/RT/SG
#                                    CRUD unaffected
#   6  Ec2NetworkInterface           OK
#   7  SchedulerManagement           OK
#   8  SchedulerList                 OK
#   9  LogsManagement                OK
#   10 LogsDescribe                  OK
#   11 EcrManagement                 PARTIAL (intentional) — DenyEcrRepositoryDeletion
#                                    shadows ecr:DeleteRepository on zzzapata-join-bot
#                                    only; push/pull/lifecycle/scan-config unaffected
#   12 EcrAuthToken                  OK
#   13 SsmParameterAccess            OK
#   14 SsmDescribeParameters         OK
#   15 SnsManagement                 OK
#   16 SnsList                       OK
#   17 StateObjectCrud (prod/*)      OK   — DenyBootstrapStateAccess covers the
#                                    DISJOINT zzzapata/bootstrap/* prefix;
#                                    DenyStateBucketConfigMutation lists bucket-
#                                    config actions only, never object actions
#   18 ListStateBucket               OK   — VERIFIED: s3:ListBucket is absent from
#                                    DenyStateBucketConfigMutation's action list
#                                    even though both target the same bucket ARN.
#                                    This is the exact shadowing class that bit
#                                    dcuero-iac.
#   19 CreateScopedRuntimeRoles      OK   for new zzzapata-* roles. A module that
#                                    named a role exactly zzzapata-github-actions-plan
#                                    would be denied by DenyTrustAnchorMutation —
#                                    correct behaviour.
#   20 ManageScopedRuntimeRoles      PARTIAL (intentional, REQUIRED) — role/zzzapata-*
#                                    textually matches both anchor role ARNs;
#                                    DenyTrustAnchorMutation (not_actions Get*/List*)
#                                    blocks all 14 mutating actions against them.
#                                    THIS row is why the apply role cannot rewrite
#                                    its own trust policy.
#   21 PassRuntimeRoles              OK   for non-anchor roles. iam:PassRole is
#                                    neither Get* nor List*, so passing an anchor
#                                    role is denied — never intended.
#   22 CreateEcsServiceLinkedRole    OK   — the SLR path is not a trust-anchor ARN;
#                                    DenyIamUserCreation is user-only
#   23 StsIdentity                   OK
#
# Second check — CI-created runtime roles vs zzzapata-runtime-boundary:
#
#   Runtime role         Needs                                    Verdict
#   ------------------   --------------------------------------    -------
#   zzzapata-ecs-task    ssm:GetParameter*, kms:Decrypt,           OK — no Deny matches
#                        elasticfilesystem:ClientMount/ClientWrite
#   zzzapata-ecs-exec    ecr:BatchGetImage/GetDownloadUrlForLayer/ OK
#                        GetAuthorizationToken, logs:CreateLogStream,
#                        logs:PutLogEvents
#   zzzapata-scheduler   ecs:RunTask, iam:PassRole ->              OK — ONLY because
#                        ecs-tasks.amazonaws.com                   DenyIamMutation
#                                                                  replaced a blanket
#                                                                  iam:* Deny;
#                                                                  DenyPassRoleOutsideEcs
#                                                                  permits exactly this
#                                                                  PassedToService
#
# No unintended boundary shadowing. The three PARTIAL rows are the deny-on-delete
# / deny-peering protections working as designed.
# =============================================================================
