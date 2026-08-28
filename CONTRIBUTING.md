# Contributing

Changes reach `main` through `staging`:

```text
feature/xyz  ──PR──▶  staging  ──PR──▶  main
```

`main` is what provisions a machine. Both install paths — `README.md` and step 3
of the first-run procedure in `docs/README.md` — `git clone` without `--branch`,
so whatever sits on `main` is what a stranger's fresh Ubuntu box runs as soon as
it is merged. There is no release, no tag, no version to hide behind.

`staging` is where a change proves itself first. The static checks run on it, and
the container smoke job runs on the promotion out of it — so a batch of changes
gets one forty-minute run and one VM build rather than one of each per change.

That also fixes the default branch. `main` has to stay default so those clones
keep working, which means a new PR is based on `main` unless you say otherwise —
see [Opening a PR](#opening-a-pr) below.

## Branches

- `main` — cloned by anyone provisioning a box. Only `staging` and `hotfix/*`
  may target it.
- `staging` — integration branch. Feature work lands here first.
- `feature/xyz` — one concern per branch, branched off `staging`.
- `hotfix/xyz` — branched off `main`, for a fix that cannot wait for the next
  staging cycle. Merge it to `main`, then merge `main` back into `staging` so
  the two do not drift.

```bash
git switch staging && git pull
git switch -c feature/xyz
```

## Opening a PR

Feature branches must be retargeted, because the base defaults to `main`:

```bash
gh pr create --base staging --fill
```

Forgetting is caught rather than merged. `.github/workflows/pr-base-guard.yml`
fails any PR into `main` from a branch that is not `staging` or `hotfix/*`, and
prints the `gh pr edit --base staging` needed to fix it.

Promoting staging is the same command with the other base:

```bash
gh pr create --base main --head staging --title "Promote staging"
```

The container smoke job runs on that promotion PR and nowhere else in the normal
flow, so expect it to sit for the better part of an hour. Turn on auto-merge and
walk away rather than watching it.

## Merging

- **Feature into staging: squash.** One commit per feature keeps `staging`
  readable and keeps a branch's work-in-progress commits out of history.
- **Staging into main: merge commit.** This is load-bearing. Squashing
  `staging` into `main` writes a new commit with no ancestry from `staging`, so
  the two branches permanently diverge and every later promotion conflicts
  against changes it already contains. A merge commit keeps the two in step and
  no back-merge is ever needed.

Both rules are enforced by repository rulesets rather than left to discipline.
`main` accepts merge commits only — rebasing a promotion rewrites the commits
and diverges exactly as a squash does. `staging` accepts squashes for feature
work and merge commits for the `hotfix/*` back-merge, which has to keep `main`'s
ancestry for the same reason the promotion does.

Merged branches delete themselves. `staging` survives that because the ruleset
also restricts its deletion, and GitHub skips auto-delete on a protected branch.

## Before you push

There is no test suite. The checks are three tiers, and only the first is cheap
enough to run every time.

```bash
bash -n bootstrap.sh lib/common.sh modules/*.sh
./tests/check-docker.sh          # or ./tests/check.sh directly, on Linux
```

`tests/check.sh` targets Linux, bash 5 and GNU userland on purpose — it uses
`mapfile`, `grep -P` and `stat -c`, matching the idioms in `lib/common.sh`.
macOS ships bash 3.2 and BSD userland, so it is not run there directly;
`tests/check-docker.sh` runs the identical script in the identical
`ubuntu:26.04` image the CI job uses. Docker caches the build, so it is a
one-off cost.

CI also runs super-linter over **changed files only**. `VALIDATE_BASH` is off
there because `tests/check.sh` owns shellcheck and applies `.shellcheckrc`,
which super-linter does not read. What is left is worth reproducing locally:

```bash
yamllint -c .github/linters/.yamllint.yml .github/workflows/ .github/dependabot.yml
actionlint .github/workflows/*.yml
hadolint tests/Dockerfile
codespell
```

Anything touching a module, a manifest or an asset needs a real Ubuntu box, and
nothing on macOS substitutes for it:

```bash
./bootstrap.sh <module>          # run the one module
./bootstrap.sh <module>          # again -- it must change nothing
./tests/verify-box.sh            # after a reboot, inside a desktop session
```

Say in the PR which of these ran where. "Syntax-checked on macOS" and "ran
twice on a clean 26.04 VM" are very different claims.

## Pinning

The manifests in `tools.d/` are the lockfile. A first build runs unpinned to get
working fast; once the VM is green and snapshotted, freeze the versions that
worked back into `tools.d/*` in the same PR. A pin that exists only on your box
defeats the entire point, which is that the *next* VM rebuilds identically.

`tests/check.sh` fails a `.gh` row without an `@tag` and warns on `@latest`,
`@master` or `@main` in a `.go` row. Pin the tag, never the resolved filename —
filenames carry the architecture and cannot be rebuilt on the other one.

## Commits and PRs

One commit per logical change; if the body needs the word "also", it is probably
two commits. Subject line is a short imperative, no trailing period, then a blank
line, then plain prose. Open with what was wrong or missing, close with what the
change does about it, and name concrete files, symbols and values — `serve()
assigned IP=$(...) without local`, not "fixed a scoping issue".

PR bodies follow `.github/pull_request_template.md`: a lede saying what the PR is
and why, bullets for what a reviewer needs that the diff does not already show,
and a closing `Verified:` paragraph naming what was actually run and what it
showed — including what was not run, and why.

## Three things that will bite you

**Ordering lives in the `ALL_MODULES` array in `bootstrap.sh`, not on the
filesystem.** Adding `modules/45-foo.sh` does nothing until you add `45-foo` to
that array. Renaming one without updating the array, the module table in
`docs/README.md` and the module count in both READMEs fails `tests/check.sh` in
four places at once — the diff is against order as well as membership, because
the numeric prefixes are the run order.

**A module must never `die`.** Modules are `source`d, so `die` exits the entire
bootstrap instead of the module; warn and continue, and let the operator fix
forward. The trap is the indirect case: `read_list` dies on a missing manifest,
so renaming a `tools.d/*` file without updating its caller kills the whole run
from a module that never says `die`. `tests/check.sh` resolves every
`read_list`, `apt_install_list`, `pipx_install_list` and `go_install_list`
argument against `tools.d/` for exactly this reason. Bail early with
`return 0 2>/dev/null || exit 0` — a bare `return` breaks direct execution and a
bare `exit` kills the run.

**Every clone URL is `https://`, with no exceptions.** A clone with no SSH key
and no GitHub account has to provision completely, so `git@` in a manifest or a
module is a failure, not a style preference. `tests/check.sh` enforces it across
`bootstrap.sh`, `lib/`, `modules/`, `tools.d/` and `assets/`, allowing only the
`ssh -T git@` authentication probes by shape rather than by line number.
