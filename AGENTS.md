# AGENTS.md

## North Star

**sprig-lint** exists to enforce the [Conventional Commits](https://www.conventionalcommits.org/) standard at commit time, with zero dependencies and zero configuration overhead. Developers shouldn't have to remember the format — the hook tells them when they got it wrong, immediately, before the commit is recorded.

It is a deliberate companion to **sprig-commit**: where sprig-commit *injects* ticket IDs into commit scopes, sprig-lint *verifies* the resulting message conforms to the spec. The two tools share a philosophy and can be installed together (sprig-commit as `prepare-commit-msg`, sprig-lint as `commit-msg`) or independently.

The core value proposition: **adopt in 30 seconds, never think about it again.** Every design decision should optimize for simplicity, reliability, and staying out of the developer's way. If a feature adds complexity without meaningfully reducing friction, it doesn't belong here.

---

## Project Overview

- **Language**: Bash (3.2+ compatible)
- **Entry point**: `sprig-lint` — a self-contained bash script used as a git `commit-msg` hook
- **Config**: `.sprig-lint.cfg` (key=value format, searched in repo root then `$HOME`)
- **Tests**: `test/test.sh` using a minimal framework in `test/framework.sh`
- **Installer**: `install.sh` — curl-friendly script that sets up the hook

## File Structure

```
sprig-lint           # Main script (the hook itself)
install.sh           # curl-pipe installer
.sprig-lint.cfg      # Example/template config
test/
  framework.sh       # Minimal bash test framework (assert_eq, assert_contains, etc.)
  test.sh            # Test suite
README.md
AGENTS.md            # This file
```

## Key Design Decisions

1. **Single file, zero dependencies.** The entire tool is one bash script. No package manager, no compile step, no runtime. Only `bash`, `git`, `sed`, and `grep` (all POSIX standard).
2. **Verify, don't rewrite.** sprig-lint never modifies the commit message. It either accepts or rejects with a clear error. Rewriting is sprig-commit's job.
3. **Config is key=value.** No JSON, YAML, TOML, or package.json integration. The config file is sourced by bash with security validation. This keeps the tool ecosystem-agnostic.
4. **Config is validated before sourcing.** Lines are filtered through strict regex patterns to prevent command injection. Only known keys with safe values are evaluated.
5. **Sensible defaults match the spec.** Out of the box, sprig-lint accepts the canonical conventional-commit type set and rejects everything else. Merge/revert/fixup commits are allowed by default because they're auto-generated.
6. **Idempotent and stateless.** Running the hook on the same message twice produces the same result. No persistent state.
7. **Output is human-friendly by default, machine-friendly on demand.** Errors are colorized when stderr is a TTY; `--quiet` suppresses all output for CI/CD use; `--no-color` and the [`NO_COLOR`](https://no-color.org) env var both disable colorization without suppressing output.

## Development Guidelines

- All changes must pass `bash test/test.sh` and `shellcheck sprig-lint install.sh test/test.sh`.
- No external dependencies. If a feature requires `jq`, `python`, `node`, or any non-POSIX tool, it doesn't belong here.
- Support bash 3.2 (macOS default). Avoid bash 4+ features like associative arrays, `readarray`, or `${var,,}` lowercasing.
- Errors must always be clear and actionable. The whole point is helping the developer fix their message; cryptic errors defeat the purpose.

## Verification

Before merging any change, run:

```bash
# 1. Lint (requires shellcheck installed: brew install shellcheck)
shellcheck sprig-lint install.sh test/test.sh

# 2. Unit tests
bash test/test.sh
```

Both must pass with zero errors. Tests create temporary git repos, write commit messages, run the hook, and assert on exit code and error output. They clean up after themselves.

If adding new behavior, add a corresponding test case in `test/test.sh` following the existing pattern:

```bash
describe "Description of behavior"
assert_lint_ok   "${repo}" "feat: valid message"
assert_lint_fail "${repo}" "garbage" "" "rejects garbage" "expected error substring"
```

## Config Reference

Validation rules use a **severity level**: `error` (fail commit, exit 1), `warn` (printed in yellow but exit 0), or `off` (skip rule entirely).

### Severity rules

| Option | Default | Description |
|---|---|---|
| `format` | `error` | Subject matches `<type>[(scope)][!]: <description>` |
| `type_case` | `error` | Type is lowercase ASCII letters only |
| `type_allowed` | `error` | Type is in `allowed_types` |
| `scope_required` | `off` | Scope is required |
| `scope_empty` | `error` | Reject `feat(): x` |
| `description_empty` | `error` | Reject empty/whitespace descriptions |
| `subject_max_length` | `error` | Subject ≤ `max_subject_length` |
| `subject_full_stop` | `off` | Reject trailing period |
| `subject_leading_capital` | `off` | Reject capital first letter of description |
| `body_max_line_length` | `off` | Body lines ≤ `max_body_line_length` |

### Values & toggles

| Option | Default | Description |
|---|---|---|
| `allowed_types` | (CC type set) | Comma-separated whitelist |
| `max_subject_length` | `72` | Subject length cap; `0` disables |
| `max_body_line_length` | `100` | Body line cap; `0` disables |
| `allow_merge_commits` | `true` | Skip validation on `Merge ` commits |
| `allow_revert_commits` | `true` | Skip validation on `Revert ` commits |
| `allow_fixup_commits` | `true` | Skip validation on `fixup!`, `squash!`, `amend!` |
| `ignored_branches` | `^$` | Regex of branches to skip in hook mode |

## CLI surface

| Mode | Invocation |
|---|---|
| Hook (single message) | `sprig-lint <commit-msg-file>` |
| Range (CI / PR) | `sprig-lint --from REF --to REF` or `--range REF..REF` |
| Quiet | `-q` / `--quiet` (still exits non-zero on failure) |
| No color | `--no-color` flag or `NO_COLOR` env var |
| Help | `-h` / `--help` |

Range mode iterates `git rev-list --no-merges` and lints each commit's full message body. **Important:** the `--from` ref must be the merge base, not the tip of the target branch — otherwise commits introduced by target-branch advancement get linted as if they were part of the PR. The README documents this in the CI section.

## Architectural notes

- `lint_message <message-string>` is the single entry point for validation. Both file mode and range mode populate a message string and call it.
- Findings are stored in **parallel arrays** (`finding_levels`, `finding_rules`, `finding_msgs`, `finding_details`) rather than associative arrays — bash 3.2 doesn't have those.
- Severities and totals are accumulated across all messages in a single run, so range mode can print a per-run summary at the end.
- The conventional-commit regex permits an empty `()` scope so that `scope_empty` can fire as its own rule rather than collapsing into a generic `format` failure.

## Relationship to sprig-commit

sprig-lint is intentionally separable. The two tools can be:
- Used together: sprig-commit injects the ticket and produces a conventional-format message; sprig-lint then validates it. They run on different git hooks (`prepare-commit-msg` vs `commit-msg`) so they compose without coordination.
- Used independently: a team that doesn't track tickets in branches can still benefit from sprig-lint's enforcement; a team that doesn't want enforcement can still use sprig-commit's injection.

Each tool stays narrowly focused on its job. Cross-tool features (e.g., "lint should know about sprig-commit's ticket pattern") belong in user config, not the codebase.

## Non-goals

These are deliberately out of scope; users who need them should reach for [commitlint](https://commitlint.js.org/) instead:

- Plugin systems / custom rules in JS
- Shareable configs as packages
- Body / footer parsing beyond a single line-length check
- BREAKING CHANGE footer enforcement
- Subject case modes beyond `subject_leading_capital`
- JSON / JUnit output formats
- i18n of error messages
- Anything that would require `jq`, `node`, `python`, or other non-POSIX tools
