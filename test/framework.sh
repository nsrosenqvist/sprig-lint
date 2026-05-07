#!/usr/bin/env bash
# Minimal bash test framework for sprig-lint
set -euo pipefail

# --- State ---
_test_count=0
_test_pass=0
_test_fail=0
_test_failures=()

# Colors (disabled if not a terminal)
if [[ -t 1 ]]; then
  _green=$'\033[32m'
  _red=$'\033[31m'
  _dim=$'\033[2m'
  _reset=$'\033[0m'
else
  _green="" _red="" _dim="" _reset=""
fi

# --- Assertions ---

# assert_eq <expected> <actual> [message]
assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  _test_count=$((_test_count + 1))

  if [[ "${expected}" == "${actual}" ]]; then
    _test_pass=$((_test_pass + 1))
    echo "  ${_green}✓${_reset} ${msg:-assertion #${_test_count}}"
  else
    _test_fail=$((_test_fail + 1))
    local detail
    detail="expected: $(printf '%q' "${expected}")"$'\n'"    actual:   $(printf '%q' "${actual}")"
    _test_failures+=("${msg:-assertion #${_test_count}}: ${detail}")
    echo "  ${_red}✗${_reset} ${msg:-assertion #${_test_count}}"
    echo "    ${_dim}expected: $(printf '%q' "${expected}")${_reset}"
    echo "    ${_dim}actual:   $(printf '%q' "${actual}")${_reset}"
  fi
}

# assert_contains <haystack> <needle> [message]
assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  _test_count=$((_test_count + 1))

  if [[ "${haystack}" == *"${needle}"* ]]; then
    _test_pass=$((_test_pass + 1))
    echo "  ${_green}✓${_reset} ${msg:-assertion #${_test_count}}"
  else
    _test_fail=$((_test_fail + 1))
    _test_failures+=("${msg:-assertion #${_test_count}}: '${needle}' not found in output")
    echo "  ${_red}✗${_reset} ${msg:-assertion #${_test_count}}"
    echo "    ${_dim}needle:   ${needle}${_reset}"
    echo "    ${_dim}haystack: ${haystack}${_reset}"
  fi
}

# assert_exit_code <expected_code> <command...>
# Captures stdout+stderr into $last_output
last_output=""
assert_exit_code() {
  local expected_code="$1"
  shift
  _test_count=$((_test_count + 1))

  local actual_code=0
  last_output=$("$@" 2>&1) || actual_code=$?

  if [[ "${expected_code}" -eq "${actual_code}" ]]; then
    _test_pass=$((_test_pass + 1))
    echo "  ${_green}✓${_reset} exit code ${expected_code}"
  else
    _test_fail=$((_test_fail + 1))
    local msg="expected exit ${expected_code}, got ${actual_code}"
    _test_failures+=("${msg}")
    echo "  ${_red}✗${_reset} ${msg}"
    echo "    ${_dim}output: ${last_output}${_reset}"
  fi
}

# --- Test lifecycle ---

# describe <suite_name>
describe() {
  echo ""
  echo "${1}"
}

# --- Summary ---
test_summary() {
  echo ""
  echo "---"
  echo "${_test_pass}/${_test_count} passed, ${_test_fail} failed"

  if [[ ${_test_fail} -gt 0 ]]; then
    echo ""
    echo "${_red}Failures:${_reset}"
    for f in "${_test_failures[@]}"; do
      echo "  - ${f}"
    done
    return 1
  fi
}
