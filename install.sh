#!/usr/bin/env bash
# sprig-lint installer
# Usage: curl -fsSL https://raw.githubusercontent.com/nsrosenqvist/sprig-lint/main/install.sh | bash
set -euo pipefail

SCRIPT_URL="https://raw.githubusercontent.com/nsrosenqvist/sprig-lint/main/sprig-lint"

echo "sprig-lint: installing..."

if ! git rev-parse --show-toplevel &>/dev/null; then
  echo "error: not inside a git repository" >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
hooks_dir="${repo_root}/.git/hooks"
hook_path="${hooks_dir}/commit-msg"

if command -v curl &>/dev/null; then
  curl -fsSL "${SCRIPT_URL}" -o "${hook_path}"
elif command -v wget &>/dev/null; then
  wget -qO "${hook_path}" "${SCRIPT_URL}"
else
  echo "error: curl or wget required" >&2
  exit 1
fi

chmod +x "${hook_path}"

config_path="${repo_root}/.sprig-lint.cfg"
if [[ ! -f "${config_path}" ]]; then
  cat > "${config_path}" << 'EOF'
# sprig-lint configuration
# See https://github.com/nsrosenqvist/sprig-lint for details
#
# Severity rules: error | warn | off
# format=error
# type_case=error
# type_allowed=error
# scope_required=off
# scope_empty=error
# description_empty=error
# subject_max_length=error
# subject_full_stop=off
# subject_leading_capital=off
# body_max_line_length=off
#
# Values
# allowed_types='feat,fix,chore,refactor,docs,test,style,perf,build,ci,revert'
# max_subject_length=72
# max_body_line_length=100
#
# Toggles
# allow_merge_commits=true
# allow_revert_commits=true
# allow_fixup_commits=true
# ignored_branches='^$'
EOF
  echo "sprig-lint: created ${config_path} (edit to customize)"
fi

echo "sprig-lint: installed to ${hook_path}"
echo "sprig-lint: done!"
