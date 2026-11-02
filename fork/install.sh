#!/usr/bin/env bash
# Install the atuin client of this fork on Linux from the `yarden-latest` release.
# Usage: install.sh [install dir], default ~/.local/bin. Run it again to update.
set -euo pipefail

dir="${1:-$HOME/.local/bin}"
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) target=x86_64-unknown-linux-gnu ;;
  Linux-aarch64 | Linux-arm64) target=aarch64-unknown-linux-gnu ;;
  *) echo "no fork build for $(uname -s) $(uname -m): build it with cargo install" >&2; exit 1 ;;
esac

url="https://github.com/Yarden-zamir/atuin/releases/download/yarden-latest/atuin-$target"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl -fsSL --retry 3 -o "$tmp" "$url"
chmod +x "$tmp"
"$tmp" --version >/dev/null
mkdir -p "$dir"
mv "$tmp" "$dir/atuin"
echo "installed $("$dir/atuin" --version) at $dir/atuin"
