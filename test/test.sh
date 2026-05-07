#!/usr/bin/env bash
# sprig-lint test suite
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SPRIG_LINT="${PROJECT_DIR}/sprig-lint"

# shellcheck source=test/framework.sh
source "${SCRIPT_DIR}/framework.sh"

# --- Helpers ---

# Create a temp git repo (sprig-lint doesn't strictly need one, but the hook
# may consult `git symbolic-ref` for ignored_branches).
# shellcheck disable=SC2120  # branch arg is optional, defaults to main
setup_repo() {
  local branch_name="${1:-main}"
  local tmp
  tmp="$(mktemp -d)"
  git -C "${tmp}" init -b "${branch_name}" --quiet
  git -C "${tmp}" config user.email "test@test.com"
  git -C "${tmp}" config user.name "Test"
  touch "${tmp}/.gitkeep"
  git -C "${tmp}" add .gitkeep
  git -C "${tmp}" commit -m "init" --quiet
  echo "${tmp}"
}

# Run sprig-lint against a message; returns exit code, sets $last_output.
# Usage: run_lint <repo> <message> [config]
run_lint() {
  local repo="$1"
  local message="$2"
  local config="${3:-}"

  local msg_file="${repo}/.git/COMMIT_EDITMSG"
  printf '%s' "${message}" > "${msg_file}"

  if [[ -n "${config}" ]]; then
    printf '%s\n' "${config}" > "${repo}/.sprig-lint.cfg"
  else
    rm -f "${repo}/.sprig-lint.cfg"
  fi

  local exit_code=0
  last_output=$(cd "${repo}" && bash "${SPRIG_LINT}" "${msg_file}" 2>&1) || exit_code=$?
  return ${exit_code}
}

cleanup_repo() {
  rm -rf "$1"
}

# Convenience: assert lint succeeds
assert_lint_ok() {
  local repo="$1" message="$2" config="${3:-}" desc="${4:-passes}"
  local exit_code=0
  run_lint "${repo}" "${message}" "${config}" || exit_code=$?
  assert_eq "0" "${exit_code}" "${desc}"
}

# Convenience: assert lint fails with code 1
assert_lint_fail() {
  local repo="$1" message="$2" config="${3:-}" desc="${4:-fails}"
  local expected_msg="${5:-}"
  local exit_code=0
  run_lint "${repo}" "${message}" "${config}" || exit_code=$?
  assert_eq "1" "${exit_code}" "${desc}"
  if [[ -n "${expected_msg}" ]]; then
    assert_contains "${last_output}" "${expected_msg}" "error mentions: ${expected_msg}"
  fi
}

# ============================================================================
# TESTS
# ============================================================================

repo=$(setup_repo)

describe "Valid: type only"
assert_lint_ok "${repo}" "feat: add login"

describe "Valid: type + scope"
assert_lint_ok "${repo}" "fix(auth): refresh token"

describe "Valid: hyphenated scope"
assert_lint_ok "${repo}" "feat(new-service): add endpoint"

describe "Valid: comma-separated scopes"
assert_lint_ok "${repo}" "feat(s1, s2): big change"

describe "Valid: breaking change marker"
assert_lint_ok "${repo}" "feat!: drop v1"

describe "Valid: scope + breaking"
assert_lint_ok "${repo}" "feat(api)!: remove endpoint"

describe "Valid: multi-line body"
assert_lint_ok "${repo}" $'feat: add thing\n\nLong description on next paragraph.\nMore detail here.'

describe "Valid: comments and blank lines before subject"
assert_lint_ok "${repo}" $'# This is a comment\n\nfeat: real subject'

describe "Valid: scissors line ignored"
assert_lint_ok "${repo}" $'fix: real subject\n\n# ------------------------ >8 ------------------------\n# garbage below'

describe "Invalid: missing colon"
assert_lint_fail "${repo}" "feat add login" "" "rejects missing colon" \
  "Conventional Commits format"

describe "Invalid: empty message"
assert_lint_fail "${repo}" "" "" "rejects empty message" "empty"

describe "Invalid: only comments"
assert_lint_fail "${repo}" $'# just a comment\n# another' "" "rejects only-comments" "empty"

describe "Invalid: empty description"
assert_lint_fail "${repo}" "feat: " "" "rejects empty description"

describe "Invalid: uppercase type"
assert_lint_fail "${repo}" "FEAT: add login" "" "rejects uppercase type" \
  "lowercase letters"

describe "Invalid: unknown type"
assert_lint_fail "${repo}" "wibble: do thing" "" "rejects unknown type" \
  "not in allowed_types"

describe "Invalid: empty scope"
assert_lint_fail "${repo}" "feat(): blah" "" "rejects empty scope"

describe "Invalid: no space after colon"
assert_lint_fail "${repo}" "feat:no-space" "" "rejects missing space after colon" \
  "Conventional Commits format"

describe "Custom allowed_types: rejects feat"
assert_lint_fail "${repo}" "feat: x" "allowed_types='fix,chore'" \
  "feat rejected when not in custom list" "not in allowed_types"

describe "Custom allowed_types: accepts custom"
assert_lint_ok "${repo}" "spike: x" "allowed_types='fix,chore,spike'" \
  "custom type accepted"

describe "require_scope=true: rejects missing scope"
assert_lint_fail "${repo}" "feat: x" "require_scope=true" \
  "missing scope rejected" "scope is required"

describe "require_scope=true: accepts with scope"
assert_lint_ok "${repo}" "feat(core): x" "require_scope=true" \
  "scope present accepted"

describe "max_subject_length: too long"
long_msg="feat: $(printf 'x%.0s' {1..80})"
assert_lint_fail "${repo}" "${long_msg}" "max_subject_length=72" \
  "too-long rejected" "exceeds max_subject_length"

describe "max_subject_length=0 disables length check"
assert_lint_ok "${repo}" "${long_msg}" "max_subject_length=0" \
  "long subject accepted when limit disabled"

describe "Merge commit allowed by default"
assert_lint_ok "${repo}" "Merge branch 'main' into feature" "" \
  "merge commit accepted"

describe "Revert commit allowed by default"
assert_lint_ok "${repo}" $'Revert "feat: bad thing"' "" \
  "revert commit accepted"

describe "Fixup commit allowed by default"
assert_lint_ok "${repo}" "fixup! feat: original" "" \
  "fixup commit accepted"

describe "Squash commit allowed by default"
assert_lint_ok "${repo}" "squash! feat: original" "" \
  "squash commit accepted"

describe "allow_merge_commits=false rejects merge"
assert_lint_fail "${repo}" "Merge branch 'main'" "allow_merge_commits=false" \
  "merge rejected when disabled" "Conventional Commits format"

describe "allow_fixup_commits=false rejects fixup"
assert_lint_fail "${repo}" "fixup! feat: x" "allow_fixup_commits=false" \
  "fixup rejected when disabled"

describe "Whitespace-only description rejected"
assert_lint_fail "${repo}" "feat:    " "" "whitespace-only description rejected"

describe "Security: command injection in config rejected"
# shellcheck disable=SC2016
assert_lint_ok "${repo}" "feat: x" 'allowed_types=$(echo pwned)' \
  "malicious config line filtered, defaults used"

describe "No arguments fails"
exit_code=0
last_output=$(bash "${SPRIG_LINT}" 2>&1) || exit_code=$?
assert_eq "1" "${exit_code}" "exits 1 with no args"

describe "ignored_branches skips validation"
assert_lint_ok "${repo}" "garbage not even close" \
  "ignored_branches='^main$'" "skipped on ignored branch"

describe "--quiet suppresses output on failure"
msg_file="${repo}/.git/COMMIT_EDITMSG"
printf '%s' "garbage not conventional" > "${msg_file}"
rm -f "${repo}/.sprig-lint.cfg"
exit_code=0
output=$(cd "${repo}" && bash "${SPRIG_LINT}" --quiet "${msg_file}" 2>&1) || exit_code=$?
assert_eq "1" "${exit_code}" "still exits 1 in quiet mode"
assert_eq "" "${output}" "no output emitted in quiet mode"

describe "-q short flag also suppresses output"
exit_code=0
output=$(cd "${repo}" && bash "${SPRIG_LINT}" -q "${msg_file}" 2>&1) || exit_code=$?
assert_eq "1" "${exit_code}" "still exits 1 with -q"
assert_eq "" "${output}" "no output emitted with -q"

describe "--quiet on valid message exits 0 silently"
printf '%s' "feat: valid" > "${msg_file}"
exit_code=0
output=$(cd "${repo}" && bash "${SPRIG_LINT}" --quiet "${msg_file}" 2>&1) || exit_code=$?
assert_eq "0" "${exit_code}" "exits 0 on valid message"
assert_eq "" "${output}" "no output on success"

describe "--help prints usage and exits 0"
exit_code=0
output=$(bash "${SPRIG_LINT}" --help 2>&1) || exit_code=$?
assert_eq "0" "${exit_code}" "--help exits 0"
assert_contains "${output}" "Usage:" "--help shows usage"
assert_contains "${output}" "--quiet" "--help mentions quiet flag"

describe "Unknown option rejected"
exit_code=0
output=$(bash "${SPRIG_LINT}" --bogus "${msg_file}" 2>&1) || exit_code=$?
assert_eq "1" "${exit_code}" "unknown option exits 1"
assert_contains "${output}" "unknown option" "error mentions unknown option"

describe "Flag order: file before --quiet still works"
printf '%s' "garbage" > "${msg_file}"
exit_code=0
output=$(cd "${repo}" && bash "${SPRIG_LINT}" "${msg_file}" --quiet 2>&1) || exit_code=$?
assert_eq "1" "${exit_code}" "exits 1 regardless of arg order"
assert_eq "" "${output}" "still quiet when flag comes after path"

cleanup_repo "${repo}"

# ============================================================================
test_summary
