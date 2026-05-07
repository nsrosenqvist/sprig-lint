#!/usr/bin/env bash
# sprig-lint test suite
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SPRIG_LINT="${PROJECT_DIR}/sprig-lint"

# shellcheck source=test/framework.sh
source "${SCRIPT_DIR}/framework.sh"

# --- Helpers ---

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

assert_lint_ok() {
  local repo="$1" message="$2" config="${3:-}" desc="${4:-passes}"
  local exit_code=0
  run_lint "${repo}" "${message}" "${config}" || exit_code=$?
  assert_eq "0" "${exit_code}" "${desc}"
}

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

# Make a commit with a given subject in a repo (used for range tests).
make_commit() {
  local repo="$1" subject="$2"
  echo "$RANDOM" > "${repo}/file-$RANDOM"
  git -C "${repo}" add -A
  git -C "${repo}" commit -m "${subject}" --quiet --allow-empty-message
}

# ============================================================================
# SINGLE-MESSAGE (HOOK) MODE
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
assert_lint_fail "${repo}" "feat(): blah" "" "rejects empty scope" \
  "scope is empty"

describe "Invalid: no space after colon"
assert_lint_fail "${repo}" "feat:no-space" "" "rejects missing space after colon" \
  "Conventional Commits format"

# --- allowed_types ---
describe "Custom allowed_types: rejects feat"
assert_lint_fail "${repo}" "feat: x" "allowed_types='fix,chore'" \
  "feat rejected when not in custom list" "not in allowed_types"

describe "Custom allowed_types: accepts custom"
assert_lint_ok "${repo}" "spike: x" "allowed_types='fix,chore,spike'" \
  "custom type accepted"

# --- scope_required ---
describe "scope_required=error: rejects missing scope"
assert_lint_fail "${repo}" "feat: x" "scope_required=error" \
  "missing scope rejected" "scope is required"

describe "scope_required=error: accepts with scope"
assert_lint_ok "${repo}" "feat(core): x" "scope_required=error" \
  "scope present accepted"

describe "scope_required=warn: warns but does not fail"
assert_lint_ok "${repo}" "feat: x" "scope_required=warn" \
  "warn does not fail exit code"
assert_contains "${last_output}" "scope_required" "warning is printed"
assert_contains "${last_output}" "scope is required" "warning text shown"

# --- subject_max_length ---
describe "max_subject_length: too long"
long_msg="feat: $(printf 'x%.0s' {1..80})"
assert_lint_fail "${repo}" "${long_msg}" "max_subject_length=72" \
  "too-long rejected" "subject exceeds 72 chars"

describe "max_subject_length=0 disables length check"
assert_lint_ok "${repo}" "${long_msg}" "max_subject_length=0" \
  "long subject accepted when limit disabled"

describe "subject_max_length=warn does not fail"
assert_lint_ok "${repo}" "${long_msg}" $'subject_max_length=warn\nmax_subject_length=72' \
  "warn does not fail"

# --- subject_full_stop ---
describe "subject_full_stop: off by default (period accepted)"
assert_lint_ok "${repo}" "feat: add login." "" \
  "trailing period allowed by default"

describe "subject_full_stop=error rejects trailing period"
assert_lint_fail "${repo}" "feat: add login." "subject_full_stop=error" \
  "trailing period rejected" "must not end with a period"

describe "subject_full_stop=warn warns on trailing period"
assert_lint_ok "${repo}" "feat: add login." "subject_full_stop=warn" \
  "warn does not fail"
assert_contains "${last_output}" "must not end with a period" "warning text shown"

# --- subject_leading_capital ---
describe "subject_leading_capital: off by default"
assert_lint_ok "${repo}" "feat: Add login" "" \
  "capital allowed by default"

describe "subject_leading_capital=error rejects capital"
assert_lint_fail "${repo}" "feat: Add login" "subject_leading_capital=error" \
  "capital description rejected" "must not start with a capital letter"

describe "subject_leading_capital=error: lowercase passes"
assert_lint_ok "${repo}" "feat: add login" "subject_leading_capital=error" \
  "lowercase first char ok"

# --- body_max_line_length ---
describe "body_max_line_length: off by default"
long_body=$'feat: x\n\n'"$(printf 'a%.0s' {1..150})"
assert_lint_ok "${repo}" "${long_body}" "" \
  "long body lines accepted by default"

describe "body_max_line_length=error rejects long body lines"
assert_lint_fail "${repo}" "${long_body}" \
  $'body_max_line_length=error\nmax_body_line_length=100' \
  "long body line rejected" "body line exceeds 100 chars"

describe "body_max_line_length=error: short body lines pass"
short_body=$'feat: x\n\nThis is a short body line.\nAnd another short one.'
assert_lint_ok "${repo}" "${short_body}" \
  $'body_max_line_length=error\nmax_body_line_length=100' \
  "short body lines accepted"

describe "max_body_line_length=0 disables body check"
assert_lint_ok "${repo}" "${long_body}" \
  $'body_max_line_length=error\nmax_body_line_length=0' \
  "0 disables body length check"

# --- Special commits ---
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

# --- Multiple findings ---
describe "Multiple findings printed together"
multi_msg="WIBBLE: This is way too long $(printf 'x%.0s' {1..80}) ."
assert_lint_fail "${repo}" "${multi_msg}" \
  $'subject_full_stop=error\nsubject_leading_capital=error\nmax_subject_length=72' \
  "multiple findings cause exit 1"
assert_contains "${last_output}" "type_case" "type_case finding present"
assert_contains "${last_output}" "type_allowed" "type_allowed finding present"
assert_contains "${last_output}" "subject_max_length" "length finding present"
assert_contains "${last_output}" "subject_full_stop" "period finding present"
assert_contains "${last_output}" "subject_leading_capital" "capital finding present"

describe "Warnings alone do not fail"
assert_lint_ok "${repo}" "feat: Add login." \
  $'subject_full_stop=warn\nsubject_leading_capital=warn' \
  "all-warn message exits 0"
assert_contains "${last_output}" "subject_full_stop" "warning printed"
assert_contains "${last_output}" "subject_leading_capital" "warning printed"

# --- Severity validation ---
describe "Invalid severity value rejected"
assert_lint_fail "${repo}" "feat: x" "format=loud" \
  "bogus severity rejected" "invalid severity"

# --- Security ---
describe "Security: command injection in config rejected"
# shellcheck disable=SC2016
assert_lint_ok "${repo}" "feat: x" 'allowed_types=$(echo pwned)' \
  "malicious config line filtered, defaults used"

# --- CLI ---
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
assert_contains "${output}" "--no-color" "--help mentions --no-color"
assert_contains "${output}" "--from" "--help mentions range mode"

describe "--no-color disables ANSI escapes"
printf '%s' "garbage" > "${msg_file}"
exit_code=0
output=$(cd "${repo}" && bash "${SPRIG_LINT}" --no-color "${msg_file}" 2>&1) || exit_code=$?
assert_eq "1" "${exit_code}" "--no-color does not change exit code"
has_esc=no
case "${output}" in *$'\033'*) has_esc=yes ;; esac
assert_eq "no" "${has_esc}" "--no-color produces no ANSI escapes"

describe "NO_COLOR env var disables color"
exit_code=0
output=$(cd "${repo}" && NO_COLOR=1 bash "${SPRIG_LINT}" "${msg_file}" 2>&1) || exit_code=$?
assert_eq "1" "${exit_code}" "NO_COLOR does not change exit code"
has_esc=no
case "${output}" in *$'\033'*) has_esc=yes ;; esac
assert_eq "no" "${has_esc}" "NO_COLOR produces no ANSI escapes"

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
# RANGE MODE
# ============================================================================

describe "Range: lints commits in range, all valid"
repo=$(setup_repo)
make_commit "${repo}" "feat: first"
make_commit "${repo}" "fix: second"
base="$(git -C "${repo}" rev-parse HEAD~2)"
exit_code=0
output=$(cd "${repo}" && bash "${SPRIG_LINT}" --from "${base}" --to HEAD 2>&1) || exit_code=$?
assert_eq "0" "${exit_code}" "all-valid range exits 0"
assert_contains "${output}" "linted 2 commit" "summary printed"
cleanup_repo "${repo}"

describe "Range: --range syntax"
repo=$(setup_repo)
make_commit "${repo}" "feat: first"
make_commit "${repo}" "fix: second"
base="$(git -C "${repo}" rev-parse HEAD~2)"
exit_code=0
output=$(cd "${repo}" && bash "${SPRIG_LINT}" --range "${base}..HEAD" 2>&1) || exit_code=$?
assert_eq "0" "${exit_code}" "--range exits 0 on valid commits"
cleanup_repo "${repo}"

describe "Range: rejects when any commit is invalid"
repo=$(setup_repo)
make_commit "${repo}" "feat: ok"
make_commit "${repo}" "garbage commit"
make_commit "${repo}" "feat: also ok"
base="$(git -C "${repo}" rev-parse HEAD~3)"
exit_code=0
output=$(cd "${repo}" && bash "${SPRIG_LINT}" --from "${base}" --to HEAD 2>&1) || exit_code=$?
assert_eq "1" "${exit_code}" "exits 1 when any commit fails"
assert_contains "${output}" "garbage commit" "bad subject shown in output"
assert_contains "${output}" "Conventional Commits format" "format error reported"
assert_contains "${output}" "linted 3 commit" "summary printed"
cleanup_repo "${repo}"

describe "Range: empty range exits 0"
repo=$(setup_repo)
make_commit "${repo}" "feat: only one"
exit_code=0
output=$(cd "${repo}" && bash "${SPRIG_LINT}" --from HEAD --to HEAD 2>&1) || exit_code=$?
assert_eq "0" "${exit_code}" "empty range exits 0"
assert_contains "${output}" "no commits to lint" "informs about empty range"
cleanup_repo "${repo}"

describe "Range: skips merge commits by default"
repo=$(setup_repo)
make_commit "${repo}" "feat: a"
git -C "${repo}" checkout -b side --quiet
make_commit "${repo}" "fix: b"
git -C "${repo}" checkout main --quiet
make_commit "${repo}" "feat: c"
git -C "${repo}" merge side --no-ff --quiet -m "Merge branch 'side'"
base="$(git -C "${repo}" rev-list --max-parents=0 HEAD)"
exit_code=0
output=$(cd "${repo}" && bash "${SPRIG_LINT}" --from "${base}" --to HEAD 2>&1) || exit_code=$?
assert_eq "0" "${exit_code}" "range with merge commits exits 0"
cleanup_repo "${repo}"

describe "Range: invalid ref errors"
repo=$(setup_repo)
exit_code=0
output=$(cd "${repo}" && bash "${SPRIG_LINT}" --from bogus --to HEAD 2>&1) || exit_code=$?
assert_eq "1" "${exit_code}" "invalid ref exits 1"
assert_contains "${output}" "failed to list commits" "error reported"
cleanup_repo "${repo}"

describe "Range: --from without --to errors"
repo=$(setup_repo)
exit_code=0
output=$(cd "${repo}" && bash "${SPRIG_LINT}" --from HEAD 2>&1) || exit_code=$?
assert_eq "1" "${exit_code}" "incomplete range exits 1"
assert_contains "${output}" "must both be set" "error reported"
cleanup_repo "${repo}"

describe "Range: cannot combine with file path"
repo=$(setup_repo)
make_commit "${repo}" "feat: x"
echo "feat: x" > "${repo}/msg.txt"
exit_code=0
output=$(cd "${repo}" && bash "${SPRIG_LINT}" --from HEAD --to HEAD "${repo}/msg.txt" 2>&1) || exit_code=$?
assert_eq "1" "${exit_code}" "combined modes rejected"
assert_contains "${output}" "cannot combine" "error reported"
cleanup_repo "${repo}"

describe "Range: --quiet suppresses output"
repo=$(setup_repo)
make_commit "${repo}" "garbage"
base="$(git -C "${repo}" rev-parse HEAD~1)"
exit_code=0
output=$(cd "${repo}" && bash "${SPRIG_LINT}" --quiet --from "${base}" --to HEAD 2>&1) || exit_code=$?
assert_eq "1" "${exit_code}" "still fails on bad commit"
assert_eq "" "${output}" "quiet suppresses range output"
cleanup_repo "${repo}"

# ============================================================================
test_summary
