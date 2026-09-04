output "plan_role_arn" {
  description = "ARN of the read-only IAM role assumed by pr.yml via OIDC. Publish as the GitHub Actions variable AWS_PLAN_ROLE_ARN."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "ARN of the scoped-write IAM role assumed by cd.yml via OIDC. Publish as the GitHub Actions variable AWS_APPLY_ROLE_ARN."
  value       = aws_iam_role.apply.arn
}

output "runtime_boundary_arn" {
  description = "ARN of the permissions boundary every CI-created runtime role (zzzapata-ecs-task, -ecs-exec, -scheduler) must carry. Consumed by the prod root as var.runtime_boundary_arn; also publish as RUNTIME_BOUNDARY_ARN."
  value       = aws_iam_policy.runtime_boundary.arn
}

output "ecr_repository_url" {
  description = "Push/pull URL of the join-bot ECR repository. Publish as the GitHub Actions variable ECR_REPOSITORY_URL."
  value       = aws_ecr_repository.join_bot.repository_url
}

output "ecr_repository_arn" {
  description = "ARN of the join-bot ECR repository."
  value       = aws_ecr_repository.join_bot.arn
}

output "state_bucket_name" {
  description = "Name of the externally-owned S3 state bucket this repo consumes. Publish as the GitHub Actions variable TF_STATE_BUCKET."
  value       = var.state_bucket_name
}
