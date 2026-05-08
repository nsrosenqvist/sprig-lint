# sprig-lint

A zero-dependency git hook that validates commit messages against the [Conventional Commits](https://www.conventionalcommits.org/) standard — at commit time, in CI, or both.

```
You type:  fix the bug
You get:   ✗ format: subject does not follow Conventional Commits format
              expected '<type>[(scope)][!]: <description>', got: fix the bug

You type:  fix: resolve crash on startup
You get:   (silent — commit accepted)
```

**Why?** Linting at commit time catches bad messages before they enter history, when they're still cheap to fix. No CI round-trip, no force-pushes, no rebases. And when you do want CI-side enforcement, range mode lints whole PRs in one shot.

`sprig-lint` is a companion to [sprig-commit](https://github.com/nsrosenqvist/sprig-commit) — they share a philosophy (single bash script, zero deps) and compose cleanly: sprig-commit *injects* ticket scopes, sprig-lint *verifies* the result. Either works standalone.

## How it works

`sprig-lint` runs as a git `commit-msg` hook (or in CI). It:

1. Finds the subject line — the first non-comment, non-blank line.
2. Validates the format (`<type>[(scope)][!]: <description>`).
3. Checks each rule with its configured severity and collects findings.
4. Prints findings (red ✗ for errors, yellow ⚠ for warnings) and exits 1 if any errors.

| Subject | Result |
|---|---|
| `feat: add login` | ✓ |
| `fix(auth): refresh token` | ✓ |
| `feat!: drop v1 support` | ✓ |
| `feat(api)!: remove endpoint` | ✓ |
| `Merge branch 'main'` | ✓ *(allowed by default)* |
| `fixup! feat: original` | ✓ *(allowed by default)* |
| `fix the bug` | ✗ not conventional format |
| `FEAT: x` | ✗ type must be lowercase |
| `wibble: x` | ✗ type not in allowed_types |
| `feat: ` | ✗ description is empty |
| `feat(): x` | ✗ scope is empty |

## Install

### Quick install (curl)

Run from inside your git repository:

```bash
curl -fsSL https://raw.githubusercontent.com/nsrosenqvist/sprig-lint/main/install.sh | bash
```

This places the hook at `.git/hooks/commit-msg` and creates a template `.sprig-lint.cfg`.

### Manual install

```bash
cp sprig-lint .git/hooks/commit-msg
chmod +x .git/hooks/commit-msg
```

### CLI flags

| Flag | Description |
|---|---|
| `-q`, `--quiet` | Suppress all output (still exits non-zero on failure). For CI. |
| `--no-color` | Disable ANSI color output (also honors the `NO_COLOR` environment variable). |
| `-h`, `--help` | Show usage and exit. |
| `--message <string>` | Lint a literal string (e.g. a PR title). |
| `-` | Read the message from stdin. |
| `--from REF --to REF` | Range mode: lint each commit's message in `REF..REF`. |
| `--range REF..REF` | Same as `--from`/`--to`. |

Error output is automatically colorized when stderr is a TTY; colors are suppressed when piped, redirected, when `--quiet` is set, when `--no-color` is passed, or when the [`NO_COLOR`](https://no-color.org) environment variable is set.

### With Husky

```bash
# .husky/commit-msg
#!/usr/bin/env bash
exec ./scripts/sprig-lint "$1"
```

### With pre-commit

Add to `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/nsrosenqvist/sprig-lint
    rev: v1
    hooks:
      - id: sprig-lint
        stages: [commit-msg]
```

Then install the commit-msg hook (the default `pre-commit install` only sets up the pre-commit stage):

```bash
pre-commit install --hook-type commit-msg
```

### Alongside sprig-commit

Install both — they run on different hooks and don't interfere:

```bash
# .git/hooks/prepare-commit-msg → sprig-commit (injects ticket)
# .git/hooks/commit-msg         → sprig-lint   (validates result)
```

## Configuration

Create `.sprig-lint.cfg` at the repo root (or `~/.sprig-lint.cfg` for a global default). Format is `key=value`.

Validation rules use a **severity level**: `error` (fails commit, exit 1), `warn` (printed but exit 0), or `off` (rule skipped).

```bash
# Severity rules (defaults shown)
format=error
type_case=error
type_allowed=error
scope_required=off
scope_empty=error
description_empty=error
subject_max_length=error
subject_full_stop=off            # reject trailing period
subject_leading_capital=off      # reject "feat: Add login"
body_max_line_length=off         # body line wrapping

# Values
allowed_types='feat,fix,chore,refactor,docs,test,style,perf,build,ci,revert'
max_subject_length=72            # 0 disables
max_body_line_length=100         # 0 disables

# Toggles
allow_merge_commits=true
allow_revert_commits=true
allow_fixup_commits=true
ignored_branches='^$'            # regex; default matches nothing
```

### Options reference

| Option | Default | Description |
|---|---|---|
| `format` | `error` | Subject must match `<type>[(scope)][!]: <description>`. |
| `type_case` | `error` | Type must be lowercase ASCII letters only. |
| `type_allowed` | `error` | Type must be in `allowed_types`. |
| `scope_required` | `off` | Require a scope on every commit. |
| `scope_empty` | `error` | Reject empty scopes (`feat(): x`). |
| `description_empty` | `error` | Reject empty/whitespace descriptions. |
| `subject_max_length` | `error` | Subject must fit within `max_subject_length`. |
| `subject_full_stop` | `off` | Reject subjects ending in `.`. |
| `subject_leading_capital` | `off` | Reject descriptions starting with a capital letter. |
| `body_max_line_length` | `off` | Body lines must fit within `max_body_line_length`. |
| `allowed_types` | *(spec set)* | Comma-separated whitelist of types. |
| `max_subject_length` | `72` | Subject character cap. `0` disables. |
| `max_body_line_length` | `100` | Body line character cap. `0` disables. |
| `allow_merge_commits` | `true` | Skip validation on `Merge ` commits. |
| `allow_revert_commits` | `true` | Skip validation on `Revert ` commits. |
| `allow_fixup_commits` | `true` | Skip validation on `fixup!`, `squash!`, `amend!`. |
| `ignored_branches` | `^$` | Regex of branches to skip in hook mode. |

## CI / PR validation

Range mode lints every commit between two refs. Useful in CI to validate an entire PR in one step:

```bash
sprig-lint --from "$BASE_SHA" --to "$HEAD_SHA"
```

### Picking the right range

The base ref must be the **merge base** (where the PR branched off), not the current tip of the target branch. Otherwise, if the target branch advanced after the PR was opened, you'll lint commits that came in from the target branch and aren't part of the PR.

```bash
base=$(git merge-base origin/main HEAD)
sprig-lint --from "${base}" --to HEAD
```

### GitHub Actions

The simplest path is the bundled composite action, which auto-detects whether to lint the range or the PR title:

```yaml
name: Commit Lint
on:
  pull_request:
    types: [opened, edited, synchronize, reopened]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: nsrosenqvist/sprig-lint@v1
        # Optional inputs:
        # with:
        #   mode: range          # range | pr-title | message
        #   config-path: .github/sprig-lint.cfg
        #   ref: v1              # pin a specific sprig-lint version
```

Or invoke the script directly if you'd rather not pull in the action:

```yaml
name: Commit Lint
on: [pull_request]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - run: |
          curl -fsSL https://raw.githubusercontent.com/nsrosenqvist/sprig-lint/main/sprig-lint -o /usr/local/bin/sprig-lint
          chmod +x /usr/local/bin/sprig-lint
      - run: |
          sprig-lint \
            --from "${{ github.event.pull_request.base.sha }}" \
            --to   "${{ github.event.pull_request.head.sha }}"
```

GitHub already provides the correct merge-base SHA in `pull_request.base.sha` for non-rebased PRs. For more complex workflows, compute it explicitly with `git merge-base`.

### Squash-merge workflows

If your team always squash-merges PRs, the individual commit messages don't end up in `main`'s history — only the squash commit (taken from the PR title) does. In that case, range linting the PR commits is mostly noise; lint the **PR title** instead:

```bash
sprig-lint --message "$PR_TITLE"
# or, equivalently
echo "$PR_TITLE" | sprig-lint -
```

With the bundled GitHub Action this is a one-liner — just set `mode: pr-title` (or let it auto-detect on `pull_request` events when no range is supplied):

```yaml
- uses: nsrosenqvist/sprig-lint@v1
  with:
    mode: pr-title
```

Make sure the workflow re-runs when the title is edited:

```yaml
on:
  pull_request:
    types: [opened, edited, synchronize, reopened]
```

## Behavior details

### What is validated

- **Format**: subject matches `<type>[(scope)][!]: <description>`
- **Type**: lowercase ASCII letters, present in `allowed_types`
- **Scope** *(if present)*: non-empty
- **Description**: non-empty (whitespace-only is rejected)
- **Subject length**: ≤ `max_subject_length`
- **Trailing period** *(opt-in)*: rejected when `subject_full_stop != off`
- **Leading capital** *(opt-in)*: rejected when `subject_leading_capital != off`
- **Body line length** *(opt-in)*: each body line ≤ `max_body_line_length`

### What is **not** validated

- BREAKING CHANGE footer presence
- Imperative mood, exact case patterns beyond leading-capital, body grammar
- URL- or code-block-aware body wrapping (long URLs in a body will trip `body_max_line_length` — split them or disable the rule)
- Footer formatting (`Signed-off-by`, etc.)

### Edge cases

| Scenario | Behavior |
|---|---|
| Empty message | Rejected with "commit message is empty" |
| Comment-only message | Rejected (comments aren't part of the message) |
| Comments before subject | Skipped; first non-comment line is validated |
| Scissors line (`# ------------------------ >8 ------------------------`) | Everything below is ignored |
| Merge / Revert / fixup! / squash! / amend! | Allowed by default; toggleable per kind |
| Ignored branch (hook mode only) | Hook exits silently (exit 0) |
| Range over a merge commit | Merge commits are skipped via `git rev-list --no-merges` |
| Warnings only, no errors | Exit code 0 |

## Requirements

- **bash** 3.2+ (ships with macOS, all Linux distros, and Git Bash on Windows)
- **git** (any modern version)
- No other dependencies

## Testing

```bash
bash test/test.sh
shellcheck sprig-lint install.sh test/test.sh
```

The tests create temporary git repos, run the hook against various scenarios, and verify exit codes, error output, and range-mode behavior. No external test framework is required.

## License

MIT

## See also

- [sprig-commit](https://github.com/nsrosenqvist/sprig-commit) — companion git hook that injects ticket IDs from branch names into conventional commit scopes.
