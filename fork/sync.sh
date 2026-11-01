#!/usr/bin/env bash
# Rebase the `yarden` branch of the fork onto upstream main, test it, push it, and install it.
# Exit codes: 0 done or already up to date, 1 rebase conflict (the rebase is aborted), 2 tests failed.
set -euo pipefail

cd "$(dirname "$0")/.."
[ "$(git branch --show-current)" = yarden ] || { echo "not on the yarden branch" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "the yarden worktree has local changes" >&2; exit 1; }

# Tests and builds spawn git: keep the global hooks out of them. Git commands of this script
# keep the global config, because it holds the credential helper for the push.
nogit=(env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1)

git fetch --quiet origin
git fetch --quiet fork
gh repo sync Yarden-zamir/atuin --branch main

before=$(git rev-parse HEAD)
if ! git rebase origin/main; then
  git rebase --abort
  echo "rebase conflict: resolve it in $(pwd), then run this script again" >&2
  exit 1
fi
installed=$(atuin info 2>/dev/null | grep '^commit:' || true)
if [ "$(git rev-parse HEAD)" = "$before" ] && [ "$(git rev-parse HEAD)" = "$(git rev-parse fork/yarden 2>/dev/null)" ] \
  && [[ "$installed" == *"$(git rev-parse HEAD)"* ]]; then
  echo "up to date: $(git log -1 --format='%h %s')"
  exit 0
fi

# Only the tests of the patched code: the full suite runs in upstream CI.
"${nogit[@]}" cargo test --locked --quiet -p atuin-common continuation || exit 2

git push --quiet --force-with-lease fork yarden
"${nogit[@]}" cargo install --locked --quiet --path crates/atuin
if atuin daemon status >/dev/null 2>&1; then atuin daemon restart; fi
echo "installed: $(atuin --version), commit $(git log -1 --format='%h %s')"
