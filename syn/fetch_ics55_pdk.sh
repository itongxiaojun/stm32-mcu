#!/usr/bin/env bash
# ========================================================================
# Fetch the ICS55 PDK (icsprout55-pdk v1.10.102) release artifacts.
#
# Two reasons this uses a mirror:
#   1. a full git clone of the repository repeatedly fails with
#      "fetch-pack: unexpected disconnect / early EOF";
#   2. direct downloads from github.com releases stall on some hosts
#      (measured ~4 KB/s with SSL "unexpected eof" drops, versus ~950 KB/s
#      through gh-proxy.com).
#
# The mirror is tried first and direct github.com is the fallback, so this
# still works if gh-proxy.com is unreachable.
#
# This only provides the standard cells / IO / tech LEF. The SRAM macro comes
# from a separate repository - see run_ics55_synth.sh or README.md.
#
# Usage:  bash syn/fetch_ics55_pdk.sh [destination]
# Default destination: <repo>/syn/pdk/icsprout55-pdk-v1.10.102
# ========================================================================
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$REPO/syn/pdk/icsprout55-pdk-v1.10.102}"

REL="v1.10.102"
GH="https://github.com/openecos-projects/icsprout55-pdk/releases/download/$REL"
PROXY="https://gh-proxy.com"

FILES=(
    ics55_LLSC_H7CH_gds.tar.bz2
    ics55_LLSC_H7CH_liberty.tar.bz2
    ics55_LLSC_H7CL_gds.tar.bz2
    ics55_LLSC_H7CL_liberty.tar.bz2
    ics55_LLSC_H7CR_gds.tar.bz2
    ics55_LLSC_H7CR_liberty.tar.bz2
    ICsprout_55LLULP1233_IO_251013_gds.tar.bz2
)

mkdir -p "$DEST"
cd "$DEST" || exit 1

echo "=== ICS55 PDK $REL -> $DEST ==="
date
echo

# fetch <url> <output>: resume-aware download with retries. --speed-limit /
# --speed-time abort a stalled transfer so the retry can resume from -C -.
fetch() {
    local url="$1" out="$2"
    curl -L --fail --retry 5 --retry-delay 3 --retry-all-errors \
         -C - --connect-timeout 20 --max-time 7200 \
         --speed-limit 1024 --speed-time 120 \
         -o "$out" "$url"
}

fail=0
for f in "${FILES[@]}"; do
    echo "--- $f"
    if fetch "$PROXY/$GH/$f" "$f"; then
        printf '    OK  %12s bytes  (mirror)\n' "$(stat -c %s "$f")"
        continue
    fi
    echo "    mirror failed, retrying direct"
    if fetch "$GH/$f" "$f"; then
        printf '    OK  %12s bytes  (direct)\n' "$(stat -c %s "$f")"
    else
        echo "    FAILED: $f" >&2
        fail=1
    fi
done

echo
echo "--- source archive $REL.zip"
if fetch "$PROXY/https://github.com/openecos-projects/icsprout55-pdk/archive/refs/tags/$REL.zip" "$REL.zip"; then
    printf '    OK  %12s bytes  (mirror)\n' "$(stat -c %s "$REL.zip")"
else
    echo "    FAILED: $REL.zip" >&2
    fail=1
fi

echo
echo "=== extract ==="
mkdir -p extracted && cd extracted || exit 1
for a in ../*.tar.bz2; do
    tar -xjf "$a" && echo "  unpacked $(basename "$a")"
done
unzip -q -o "../$REL.zip" && echo "  unpacked $REL.zip"

echo
echo "=== result ==="
ls -la
echo
sha256sum -- ../*.tar.bz2 "../$REL.zip" 2>/dev/null
echo
date
exit "$fail"
