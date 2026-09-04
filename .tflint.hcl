# The `terraform` ruleset (deprecated syntax, unused declarations, naming
# conventions, etc.) is bundled into the tflint CLI core since v0.42 and its
# recommended rules are on by default — there is no `plugin "terraform"` block
# to declare, only `rule` overrides if ever needed.
# See https://github.com/terraform-linters/tflint-ruleset-terraform.

plugin "aws" {
  enabled = true
  version = "0.48.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

config {
  # zzzapata's future local modules (modules/efs-chrome-profile,
  # modules/ecs-join-bot, modules/scheduler) are inspected in place, not skipped.
  # No modules/network is planned — environments/prod takes vpc_id and
  # public_subnet_ids as external inputs (README.md §9), not created here.
  call_module_type = "local"
}
