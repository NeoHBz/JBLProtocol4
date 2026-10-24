#!/usr/bin/env bash
# Release description for a tag: .github/release-notes/template.md filled in with that tag's "What's new"
# (.github/release-notes/<tag>.md), the version, the previous tag and the checksums.
#
#   scripts/release-notes.sh v0.2.0 build/SHA256SUMS.txt > notes.md
#   scripts/release-notes.sh --check v0.2.0      only check that the tag has a "What's new" file
set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true   # bash 5.2+: keep "&" in notes literal

check=0
[[ "${1:-}" == "--check" ]] && { check=1; shift; }
tag="${1:?usage: release-notes.sh [--check] <tag> [SHA256SUMS.txt]}"
dir="$(git rev-parse --show-toplevel)/.github/release-notes"
new="$dir/$tag.md"

[[ -f "$new" ]] || { echo "❌ missing $new: write the release's \"What's new\" bullets there" >&2; exit 1; }
((check)) && exit 0

sums="${2:?checksum file needed}"
prev="$(git describe --tags --abbrev=0 "$tag^" 2>/dev/null)" || { echo "❌ no tag before $tag (fetch tags?)" >&2; exit 1; }

body="$(<"$dir/template.md")"
body="${body//\{\{WHATS_NEW\}\}/$(<"$new")}"
body="${body//\{\{CHECKSUMS\}\}/$(grep -v SHA256SUMS "$sums")}"
body="${body//\{\{PREV_VERSION\}\}/${prev#v}}"
body="${body//\{\{PREV_TAG\}\}/$prev}"
body="${body//\{\{VERSION\}\}/${tag#v}}"
body="${body//\{\{TAG\}\}/$tag}"
printf '%s\n' "$body"
