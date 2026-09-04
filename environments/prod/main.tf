# Runtime root. No resources yet — slices 3-6 add, in order:
#   module "network"            (VPC + public subnets, owned by this repo)
#   module "efs_chrome_profile"
#   module "ecs_join_bot"
#   module "scheduler"
# The data source below is deliberate, not filler: it forces the AWS provider
# to be configured, so `plan`/`apply` exercise the OIDC credential path end to
# end instead of only touching the S3 backend. It creates nothing.
data "aws_caller_identity" "current" {}
