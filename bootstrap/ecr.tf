# Container registry for the meeting join-bot image.
#
# IMMUTABLE tags force sha-only deploys (no `latest`), so every running task is
# traceable to a commit and there is no untagged-overwrite pile. Satisfies
# CKV_AWS_51 (immutable) and CKV_AWS_163 (scan on push) with no checkov skip.

resource "aws_ecr_repository" "join_bot" {
  name                 = "${var.name_prefix}-join-bot"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "join_bot" {
  repository = aws_ecr_repository.join_bot.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}
