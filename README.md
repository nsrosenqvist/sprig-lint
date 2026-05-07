# sprig-lint

A zero-dependency git hook that validates commit messages against the [Conventional Commits](https://www.conventionalcommits.org/) standard.

```
You type:  fix the bug
You get:   sprig-lint: error: subject does not follow Conventional Commits format
           sprig-lint:   expected '<type>[(scope)][!]: <description>', got: fix the bug

You type:  fix: resolve crash on startup
You get:   ✓ commit accepted
```

**Why?** Linting at commit time catches bad messages before they enter history, when they're still cheap to fix. No CI round-trip, no force-pushes, no rebases.

`sprig-lint` is a companion to [sprig-commit](https://github.com/nsrosenqvist/sprig-commit) — they share a philosophy (single bash script, zero deps) and compose cleanly: sprig-commit *injects* ticket scopes, sprig-lint *verifies* the result. Either works standalone.

## How it works

`sprig-lint` runs as a git `commit-msg` hook. When you commit:

1. Reads the commit message file
2. Finds the first non-comment, non-blank line (the subject)
3. Validates it against `<type>[(scope)][!]: <description>`
4. Checks the type is in `allowed_types`, the description is non-empty, and the line length is within `max_subject_length`
5. Exits 0 if valid, 1 with an actionable error if not

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
| `-q`, `--quiet` | Suppress all output (still exits non-zero on failure). Useful for CI/CD. |
| `-h`, `--help` | Show usage and exit. |

Error output is automatically colorized when stderr is a TTY; colors are suppressed when piped, redirected, or when `--quiet` is set.

### With Husky

```bash
# .husky/commit-msg
#!/usr/bin/env bash
exec ./scripts/sprig-lint "$1"
```

### Alongside sprig-commit

Install both — they run on different hooks and don't interfere:

```bash
# .git/hooks/prepare-commit-msg → sprig-commit (injects ticket)
# .git/hooks/commit-msg         → sprig-lint   (validates result)
```

## Configuration

Create `.sprig-lint.cfg` at the repo root (or `~/.sprig-lint.cfg` for a global default). Format is `key=value`:

```bash
# Allowed conventional commit types (comma-separated)
allowed_types='feat,fix,chore,refactor,docs,test,style,perf,build,ci,revert'

# Require a scope on every commit (e.g. feat(core): ...)
require_scope=false

# Max subject line length; 0 disables the check
max_subject_length=72

# Allow auto-generated commits to bypass validation
allow_merge_commits=true
allow_revert_commits=true
allow_fixup_commits=true

# Regex of branches where validation should be skipped
ignored_branches='^$'
```

### Options reference

| Option | Default | Description |
|---|---|---|
| `allowed_types` | `feat,fix,chore,refactor,docs,test,style,perf,build,ci,revert` | Comma-separated list of allowed types. Unknown types are rejected. |
| `require_scope` | `false` | When `true`, every commit must have a scope: `type(scope): ...`. |
| `max_subject_length` | `72` | Maximum length of the subject line. Set to `0` to disable. |
| `allow_merge_commits` | `true` | Skip validation for subjects starting with `Merge `. |
| `allow_revert_commits` | `true` | Skip validation for subjects starting with `Revert `. |
| `allow_fixup_commits` | `true` | Skip validation for `fixup!`, `squash!`, `amend!` commits. |
| `ignored_branches` | `^$` | Regex of branches where the hook exits silently. Default matches nothing. |

## Behavior details

### What is validated

- **Format**: subject matches `<type>[(scope)][!]: <description>`
- **Type**: lowercase ASCII letters only, present in `allowed_types`
- **Scope** *(if present)*: non-empty
- **Description**: non-empty (whitespace-only is rejected)
- **Length**: subject ≤ `max_subject_length`

### What is **not** validated

- Body and footer formatting (the spec is loose here; teams disagree)
- BREAKING CHANGE footer presence (you can add this in your own pre-commit policy)
- Imperative mood, capitalization style, trailing periods (style preferences, not spec)

If you want stricter rules, fork the script — it's small and readable on purpose.

### Edge cases

| Scenario | Behavior |
|---|---|
| Empty message | Rejected with "commit message is empty" |
| Comment-only message | Rejected (comments aren't part of the message) |
| Comments before subject | Skipped; first non-comment line is validated |
| Scissors line (`# ------------------------ >8 ------------------------`) | Everything below is ignored |
| Merge / Revert / fixup! / squash! / amend! | Allowed by default; toggleable per kind |
| Ignored branch | Hook exits silently (exit 0) |

## Requirements

- **bash** 3.2+ (ships with macOS, all Linux distros, and Git Bash on Windows)
- **git** (any modern version)
- No other dependencies

## Testing

```bash
bash test/test.sh
shellcheck sprig-lint install.sh test/test.sh
```

The tests create temporary git repos, run the hook against various scenarios, and verify exit codes and error output. No external test framework is required.

## License

MIT

## See also

- [sprig-commit](https://github.com/nsrosenqvist/sprig-commit) — companion git hook that injects ticket IDs from branch names into conventional commit scopes.
