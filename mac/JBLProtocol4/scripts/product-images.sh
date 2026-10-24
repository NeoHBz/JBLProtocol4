#!/usr/bin/env bash
# Usage: product-images.sh <out dir>. Copies each Protocol4 model's product photo, one per colour, from a locally
# decompiled JBL app into <out dir> as <pid>_<Colour>.<ext>, plus <pid>.<ext> as the model's default.
# The photos are JBL's: they are read from your own decompiled copy at build time and never committed.
# Source: $JBL_APK_DIR (default: decompiled/apktool at the main checkout's root). No source or no jq: skip, and the
# app shows a symbol instead. Lookup rules: notes/protocol.md section 12.
set -euo pipefail
OUT="${1:?output dir}"
COMMON="$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
SRC="${JBL_APK_DIR:-${COMMON:+$(dirname "$COMMON")/decompiled/apktool}}"
LIST="$SRC/assets/product_list.json"
if ! command -v jq >/dev/null || [ ! -f "$LIST" ]; then
    echo "Product images: skipped (needs jq and ${LIST#/})"; exit 0
fi
rm -rf "$OUT"; mkdir -p "$OUT"

# Path of a drawable by resource name, highest density first. Vector (.xml) drawables are skipped.
drawable() {
    [ -n "$1" ] || return 0
    local d f
    for d in -xxxhdpi -xxhdpi -xhdpi -hdpi -mdpi -nodpi ""; do
        for f in "$SRC"/res/drawable"$d"*/"$1".webp "$SRC"/res/drawable"$d"*/"$1".png; do
            [ -f "$f" ] && { echo "$f"; return 0; }
        done
    done
    return 0
}

n=0
# One line per model: pids|dash4 config|deviceImg. '|' because read collapses empty tab-separated fields.
while IFS='|' read -r pids cfg legacy; do
    conf="$SRC/assets/config/dash4/$cfg"
    for pid in ${pids//,/ }; do
        pid="$(echo "$pid" | tr 'A-F' 'a-f')"
        default=""
        if [ -n "$cfg" ] && [ -f "$conf" ]; then
            while IFS='|' read -r colour res; do
                f="$(drawable "$res")"; [ -n "$f" ] || continue
                cp "$f" "$OUT/${pid}_${colour}.${f##*.}"; n=$((n + 1))
                if [ -z "$default" ] || [ "$colour" = Black ]; then default="$f"; fi
            done < <(jq -r '(.resourceConfig // {}) | to_entries[] | select(.value.device) | "\(.key)|\(.value.device)"' "$conf")
        fi
        # deviceImg often shows an older model (the 780NC's is a 770NC), so only models with no per-colour photo use it.
        [ -n "$default" ] || default="$(drawable "$legacy")"
        if [ -n "$default" ]; then cp "$default" "$OUT/$pid.${default##*.}"; fi
    done
done < <(jq -r '.. | objects | select((.cmdCtrlList? // []) | tostring | test("\\.protocol4\\."))
               | "\(.pidS | join(","))|\(.dash4Config // "")|\((.deviceImg // [])[0] // "")"' "$LIST")
echo "Product images: $n colour photos, $(ls "$OUT" | grep -cv _) model defaults"
