#!/usr/bin/env bash
# Wraps `terraform init` for a root module's partial S3 backend. The state
# bucket name is externally owned (bootstrap/variables.tf's
# `state_bucket_name`, currently "central-tfstate-estanix-871696174477") and
# is injected here from TF_STATE_BUCKET rather than hardcoded, so this
# script never needs to know the value.
#
# Usage:
#   export TF_STATE_BUCKET="central-tfstate-estanix-871696174477"
#   ./scripts/tf-init.sh bootstrap
#   ./scripts/tf-init.sh environments/prod   # once that root exists
#
# Ported from dcuero-iac's scripts/tf-init.sh. One addition beyond that
# original: the resolved target directory is checked to exist AND to stay
# inside this repository BEFORE terraform is ever invoked. A positional
# target such as `../../other-repo` must never reach `terraform -chdir`.
# Resolution uses `pwd -P` (physical path), not the shell's default logical
# `pwd` — logical resolution keeps symlink path components intact, so a
# symlinked directory anywhere under the repo (e.g. `environments/prod` ->
# somewhere outside) would otherwise pass this string-prefix check while
# `terraform -chdir` still follows the symlink at execution time.
#
# Guard failures below exit 2 (usage/validation error); terraform's own
# exit code passes through unchanged as the script's exit code, so callers
# can tell "the wrapper rejected this" from "terraform itself failed".
set -euo pipefail

if [ -z "${TF_STATE_BUCKET:-}" ]; then
  echo "error: TF_STATE_BUCKET is not set." >&2
  echo "Export it to the bucket name from bootstrap's 'state_bucket_name' output, then re-run." >&2
  exit 2
fi

script_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -P "${script_dir}/.." && pwd -P)"
relative_target="${1:-environments/prod}"
target_dir="${repo_root}/${relative_target}"

if [ ! -d "${target_dir}" ]; then
  echo "error: target '${relative_target}' does not exist (resolved: ${target_dir})." >&2
  exit 2
fi

resolved_target_dir="$(cd -P "${target_dir}" && pwd -P)"

case "${resolved_target_dir}" in
  "${repo_root}" | "${repo_root}"/*)
    ;;
  *)
    echo "error: target '${relative_target}' resolves outside this repository (${resolved_target_dir})." >&2
    exit 2
    ;;
esac

terraform -chdir="${resolved_target_dir}" init -reconfigure \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="region=us-east-1"
