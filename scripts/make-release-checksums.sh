#!/bin/sh
set -e
# Generates SHA256SUMS for the current repo's VERSION and launcher assets.
# Run from the repo root when cutting a release, then upload the output
# alongside the listed files as GitHub Release assets.
#
# Usage: ./scripts/make-release-checksums.sh > SHA256SUMS

if command -v sha256sum >/dev/null 2>&1; then
    SHA_CMD="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
    SHA_CMD="shasum -a 256"
else
    echo "error: sha256sum or shasum required" >&2
    exit 1
fi

for f in VERSION \
    claude-profile.sh claude-profile-init.ps1 claude-profile.cmd \
    claude-profile.fish \
    agent-profile.sh agent-profile-init.ps1 agent-profile.cmd \
    agent-profile.fish \
    agy.cmd antigravity.cmd antigravity-ide.cmd codex.cmd; do
    if [ ! -f "$f" ]; then
        echo "error: $f not found in current directory (run from repo root)" >&2
        exit 1
    fi
    $SHA_CMD "$f"
done
