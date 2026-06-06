#!/usr/bin/env bash
# Install the repo's git hooks. One-shot per clone.
# Symlinks .git/hooks/pre-commit -> ../../scripts/git-hooks/pre-commit so the
# installed hook tracks the source-of-truth file in the repo (no drift between
# what's tested and what's installed).

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

src="scripts/git-hooks/pre-commit"
dst=".git/hooks/pre-commit"

if [ ! -f "$src" ]; then
  echo "missing source hook: $src" >&2
  exit 1
fi
chmod +x "$src"

if [ -L "$dst" ]; then
  current=$(readlink "$dst")
  if [ "$current" = "../../$src" ]; then
    echo "pre-commit hook already installed (symlink → $src)"
    exit 0
  fi
  echo "removing existing pre-commit hook symlink ($current)"
  rm "$dst"
elif [ -f "$dst" ]; then
  ts=$(date +%Y%m%d_%H%M%S)
  echo "moving existing pre-commit hook to $dst.bak-$ts"
  mv "$dst" "$dst.bak-$ts"
fi

ln -s "../../$src" "$dst"
echo "installed: $dst → $src"
