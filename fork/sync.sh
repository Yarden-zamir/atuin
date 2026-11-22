#!/usr/bin/env bash
# Rebase the `yarden` branch of the fork onto upstream main, test it, push it, and install it.
# Exit codes: 0 done or already up to date, 1 rebase conflict (the rebase is aborted), 2 tests failed,
# 3 the daemon does not run the installed build.
set -euo pipefail

cd "$(dirname "$0")/.."
[ "$(git branch --show-current)" = yarden ] || { echo "not on the yarden branch" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "the yarden worktree has local changes" >&2; exit 1; }

# Tests and builds spawn git: keep the global hooks out of them. Git commands of this script
# keep the global config, because it holds the credential helper for the push.
nogit=(env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1)

# A daemon of another build refuses requests from this client (agents see "daemon and client
# builds differ"), so restart it on the installed binary. On macOS launchd runs it as an agent.
# Fail loudly when a daemon still runs another build.
ensure_daemon_build() {
  local agent="gui/$(id -u)/sh.atuin.daemon" version build status
  version=$(atuin --version)
  build=${version##*(}
  build=${build%)}
  status=$(atuin daemon status 2>&1 || true)
  [[ "$status" != *"Daemon running"* || "$status" == *"+$build"* ]] && return 0
  if launchctl print "$agent" >/dev/null 2>&1; then
    launchctl kickstart -k "$agent"
  else
    atuin daemon restart
  fi
  for _ in $(seq 20); do
    status=$(atuin daemon status 2>&1 || true)
    [[ "$status" == *"+$build"* ]] && return 0
    sleep 1
  done
  echo "the daemon does not run the installed build $build:" >&2
  echo "$status" >&2
  exit 3
}

git fetch --quiet origin
git fetch --quiet fork
gh repo sync Yarden-zamir/atuin --branch main

before=$(git rev-parse HEAD)
if ! git rebase origin/main; then
  git rebase --abort
  echo "rebase conflict: resolve it in $(pwd), then run this script again" >&2
  exit 1
fi
# `atuin info` can show an old commit: build.rs reads it, but cargo does not run build.rs again
# for a new commit. So this script records what it installed.
stamp="${XDG_STATE_HOME:-$HOME/.local/state}/atuin-fork/installed"
installed=$(cat "$stamp" 2>/dev/null || true)
if [ "$(git rev-parse HEAD)" = "$before" ] && [ "$(git rev-parse HEAD)" = "$(git rev-parse fork/yarden 2>/dev/null)" ] \
  && [ "$installed" = "$(git rev-parse HEAD)" ]; then
  ensure_daemon_build
  echo "up to date: $(git log -1 --format='%h %s')"
  exit 0
fi

# Compile every test of the crates that the patches change, with all features: some test modules
# (continuation, each harness) compile only with them, and a new upstream test can call a function
# that a patch changed. Then run only the tests of the patches: the full suite runs in upstream CI,
# and some of its tests are flaky on this Mac.
crates=(-p atuin-common -p atuin-client -p atuin-server)
"${nogit[@]}" cargo test --locked --quiet --all-features "${crates[@]}" --no-run || exit 2
"${nogit[@]}" cargo test --locked --quiet --all-features "${crates[@]}" -- \
  harnesstools::continuation extra_headers skip_stores upload_accepts || exit 2

git push --quiet --force-with-lease fork yarden
"${nogit[@]}" cargo install --locked --quiet --path crates/atuin
mkdir -p "$(dirname "$stamp")" && git rev-parse HEAD > "$stamp"
ensure_daemon_build
echo "installed: commit $(git log -1 --format='%h %s')"
