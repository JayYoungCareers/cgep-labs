#!/usr/bin/env bash
# tests/test-verify-evidence.sh
#
# Tests the evidence verifier against known-good and known-bad bundles.
# A verifier that has only ever seen valid input is an assumption, not a control:
# these cases prove it actually rejects tampering rather than always saying yes.
#
# Usage: bash tests/test-verify-evidence.sh   (exit 0 = all cases passed)

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VERIFY="$HERE/../scripts/verify-evidence.sh"
[[ -x "$VERIFY" || -f "$VERIFY" ]] || { echo "Cannot find $VERIFY" >&2; exit 2; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PASS=0 FAIL=0

# Builds a bundle whose manifest.json is generated the same way capture-evidence.sh
# generates it, so fixtures cannot drift from the real format.
make_bundle() {
  local dir="$1"; rm -rf "$dir"; mkdir -p "$dir"
  printf '{"format_version":"1.0","planned_values":{}}\n' > "$dir/plan.json"
  printf '{"version":4,"resources":[]}\n'                 > "$dir/state.json"
  printf 'commit 0000000 test fixture\n'                  > "$dir/commit.txt"
  printf 'Terraform v1.9.8\n'                             > "$dir/version.txt"
  {
    echo "["
    local first=1
    for f in "$dir"/*; do
      local base; base=$(basename "$f")
      [[ "$base" == "manifest.json" ]] && continue
      local hash size
      hash=$(sha256sum "$f" | awk '{print $1}')
      size=$(wc -c < "$f" | tr -d ' ')
      [[ $first -eq 1 ]] && first=0 || printf ","
      printf '\n  {"filename":"%s","sha256":"%s","size":%s,"captured_at_utc":"1970-01-01T00:00:00Z"}' \
        "$base" "$hash" "$size"
    done
    echo; echo "]"
  } > "$dir/manifest.json"
}

# assert <name> <expected-verdict> <tarball>
assert() {
  local name="$1" expected="$2" tarball="$3"
  local out actual
  set +e
  out=$(bash "$VERIFY" --bundle "$tarball" --json 2>&1)
  set -e
  actual=$(echo "$out" | jq -r '.verdict // "ERROR"' 2>/dev/null || echo "ERROR")
  if [[ "$actual" == "$expected" ]]; then
    echo "  ok   $name (verdict=$actual)"
    PASS=$((PASS+1))
  else
    echo "  FAIL $name — expected $expected, got $actual"
    echo "$out" | sed 's/^/       /' | head -20
    FAIL=$((FAIL+1))
  fi
}

cd "$WORK"

# 1. An untouched bundle must verify.
make_bundle good && tar czf good.tar.gz good
assert "intact bundle verifies" VERIFIED good.tar.gz

# 2. Changed file contents must be caught by the hash comparison.
make_bundle altered && printf '{"tampered":true}\n' > altered/plan.json
tar czf altered.tar.gz altered
assert "altered file is rejected" FAILED altered.tar.gz

# 3. A file removed after the manifest was written must be caught.
make_bundle removed && rm removed/state.json && tar czf removed.tar.gz removed
assert "removed file is rejected" FAILED removed.tar.gz

# 4. An added file the manifest does not account for must be caught —
#    injection is tampering just as much as modification is.
make_bundle injected && printf 'unaccounted\n' > injected/extra.txt
tar czf injected.tar.gz injected
assert "unlisted file is rejected" FAILED injected.tar.gz

# 5. A bundle with no manifest cannot be verified at all.
mkdir -p nomanifest && printf 'x\n' > nomanifest/plan.json
tar czf nomanifest.tar.gz nomanifest
assert "manifest-less bundle is rejected" FAILED nomanifest.tar.gz

echo
echo "  $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
