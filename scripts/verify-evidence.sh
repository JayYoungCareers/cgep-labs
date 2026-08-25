#!/usr/bin/env bash
# scripts/verify-evidence.sh
#
# The other half of chain of custody. capture-evidence.sh proves evidence went
# into the vault; this proves what comes back out is the same bytes, still under
# Object Lock retention, and (optionally) signed by the identity you expect.
#
# Usage:
#   verify-evidence.sh --receipt evidence/lab-2-5/receipt.json [--profile <p>]
#   verify-evidence.sh --bundle /path/to/bundle.tar.gz            # offline check
#
# Options:
#   --receipt <path>    Receipt emitted by capture-evidence.sh (vault/key/version_id).
#   --bundle <path>     Verify a local tarball instead of downloading from S3.
#                       Skips the retention check — there is no object to ask about.
#   --profile <p>       AWS CLI profile.
#   --signature <path>  Cosign bundle to verify against the tarball.
#   --identity <regex>  Expected signer identity   (required with --signature).
#   --issuer <url>      Expected OIDC issuer       (required with --signature).
#   --json              Emit only the JSON verdict on stdout.
#
# Exit codes: 0 = every check passed, 1 = a check failed, 2 = usage/environment error.

set -euo pipefail

RECEIPT="" BUNDLE="" PROFILE_ARG="" SIGNATURE="" IDENTITY="" ISSUER="" JSON_ONLY=0

die()  { echo "Error: $*" >&2; exit 2; }
say()  { [[ $JSON_ONLY -eq 1 ]] || echo "$*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --receipt)   RECEIPT="$2";   shift 2 ;;
    --bundle)    BUNDLE="$2";    shift 2 ;;
    --profile)   PROFILE_ARG="--profile $2"; shift 2 ;;
    --signature) SIGNATURE="$2"; shift 2 ;;
    --identity)  IDENTITY="$2";  shift 2 ;;
    --issuer)    ISSUER="$2";    shift 2 ;;
    --json)      JSON_ONLY=1;    shift ;;
    -h|--help)   sed -n '2,28p' "$0"; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "$RECEIPT" || -n "$BUNDLE" ]] || die "Need --receipt <path> or --bundle <path>. See --help."
[[ -z "$SIGNATURE" || ( -n "$IDENTITY" && -n "$ISSUER" ) ]] || \
  die "--signature requires --identity and --issuer (an unverified signature proves nothing)."

command -v jq >/dev/null 2>&1 || die "jq is required."
if   command -v sha256sum >/dev/null 2>&1; then SHASUM="sha256sum"
elif command -v shasum    >/dev/null 2>&1; then SHASUM="shasum -a 256"
else die "Need sha256sum or shasum."; fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Every check appends {name, status, detail}; the verdict is derived from these,
# so a check that never runs can never be silently counted as a pass.
CHECKS_FILE="$WORK/checks.jsonl"
: > "$CHECKS_FILE"
record() { jq -nc --arg n "$1" --arg s "$2" --arg d "$3" \
  '{check:$n,status:$s,detail:$d}' >> "$CHECKS_FILE"; }

RUN_ID="" VAULT="" KEY="" VERSION_ID="" SOURCE=""

if [[ -n "$RECEIPT" ]]; then
  [[ -f "$RECEIPT" ]] || die "Receipt not found: $RECEIPT"
  jq -e . "$RECEIPT" >/dev/null 2>&1 || die "Receipt is not valid JSON: $RECEIPT"
  RUN_ID=$(jq -r '.run_id     // empty' "$RECEIPT")
  VAULT=$(jq -r  '.vault      // empty' "$RECEIPT")
  KEY=$(jq -r    '.key        // empty' "$RECEIPT")
  VERSION_ID=$(jq -r '.version_id // empty' "$RECEIPT")
  [[ -n "$VAULT" && -n "$KEY" && -n "$VERSION_ID" ]] || \
    die "Receipt must carry vault, key and version_id (got vault='$VAULT' key='$KEY' version_id='$VERSION_ID')."
  record "receipt_parsed" "pass" "run_id=$RUN_ID key=$KEY"
fi

TARBALL=""
if [[ -n "$BUNDLE" ]]; then
  [[ -f "$BUNDLE" ]] || die "Bundle not found: $BUNDLE"
  TARBALL="$BUNDLE"
  SOURCE="local:$BUNDLE"
  record "bundle_source" "pass" "local file (S3 retention check skipped)"
else
  command -v aws >/dev/null 2>&1 || die "aws CLI is required to fetch from the vault."
  TARBALL="$WORK/bundle.tar.gz"
  SOURCE="s3://$VAULT/$KEY?versionId=$VERSION_ID"

  # Pin to the exact immutable version, never the mutable key.
  if aws $PROFILE_ARG s3api get-object --bucket "$VAULT" --key "$KEY" \
       --version-id "$VERSION_ID" "$TARBALL" >/dev/null 2>"$WORK/get.err"; then
    record "object_downloaded" "pass" "$SOURCE"
  else
    record "object_downloaded" "fail" "$(tr -d '\n' < "$WORK/get.err" | cut -c1-200)"
  fi

  # WORM still in force? A vault whose retention has lapsed no longer protects
  # anything, so this is a real check, not a formality.
  if RET=$(aws $PROFILE_ARG s3api get-object-retention --bucket "$VAULT" --key "$KEY" \
             --version-id "$VERSION_ID" --output json 2>"$WORK/ret.err"); then
    MODE=$(echo "$RET" | jq -r '.Retention.Mode // "none"')
    UNTIL=$(echo "$RET" | jq -r '.Retention.RetainUntilDate // "unknown"')
    if [[ "$MODE" == "GOVERNANCE" || "$MODE" == "COMPLIANCE" ]]; then
      record "object_lock_retention" "pass" "$MODE until $UNTIL"
    else
      record "object_lock_retention" "fail" "no retention mode on this object version"
    fi
  else
    record "object_lock_retention" "fail" "$(tr -d '\n' < "$WORK/ret.err" | cut -c1-200)"
  fi
fi

BUNDLE_SHA=""
if [[ -f "$TARBALL" ]]; then
  BUNDLE_SHA=$($SHASUM "$TARBALL" | awk '{print $1}')
  record "bundle_sha256" "pass" "$BUNDLE_SHA"
fi

# --- Manifest verification: the core of the whole exercise ---------------------
EXTRACT="$WORK/extract"
mkdir -p "$EXTRACT"
if [[ -f "$TARBALL" ]] && tar xzf "$TARBALL" -C "$EXTRACT" 2>"$WORK/tar.err"; then
  record "bundle_extracted" "pass" "$(find "$EXTRACT" -type f | wc -l | tr -d ' ') files"

  MANIFEST=$(find "$EXTRACT" -name manifest.json -type f | head -1)
  if [[ -z "$MANIFEST" ]]; then
    record "manifest_present" "fail" "no manifest.json in bundle — contents cannot be verified"
  else
    record "manifest_present" "pass" "$(basename "$(dirname "$MANIFEST")")/manifest.json"
    BDIR=$(dirname "$MANIFEST")
    MISMATCH=0 MISSING=0 OK=0

    while IFS=$'\t' read -r fname fhash fsize; do
      target="$BDIR/$fname"
      if [[ ! -f "$target" ]]; then
        record "file:$fname" "fail" "listed in manifest but missing from bundle"
        MISSING=$((MISSING+1)); continue
      fi
      actual_hash=$($SHASUM "$target" | awk '{print $1}')
      actual_size=$(wc -c < "$target" | tr -d ' ')
      if [[ "$actual_hash" != "$fhash" ]]; then
        record "file:$fname" "fail" "sha256 mismatch (manifest ${fhash:0:12}… actual ${actual_hash:0:12}…)"
        MISMATCH=$((MISMATCH+1))
      elif [[ -n "$fsize" && "$fsize" != "null" && "$actual_size" != "$fsize" ]]; then
        record "file:$fname" "fail" "size mismatch (manifest $fsize, actual $actual_size)"
        MISMATCH=$((MISMATCH+1))
      else
        record "file:$fname" "pass" "sha256 ${actual_hash:0:12}… size $actual_size"
        OK=$((OK+1))
      fi
    done < <(jq -r '.[] | [.filename, .sha256, (.size|tostring)] | @tsv' "$MANIFEST")

    # Anything in the bundle that the manifest does not account for is a
    # chain-of-custody hole: an added file is as much tampering as a changed one.
    EXTRA=0
    while read -r present; do
      [[ "$present" == "manifest.json" ]] && continue
      if ! jq -e --arg f "$present" 'any(.[]; .filename == $f)' "$MANIFEST" >/dev/null; then
        record "unlisted:$present" "fail" "file present in bundle but absent from manifest"
        EXTRA=$((EXTRA+1))
      fi
    done < <(cd "$BDIR" && find . -maxdepth 1 -type f -printf '%f\n')

    record "manifest_summary" \
      "$( [[ $MISMATCH -eq 0 && $MISSING -eq 0 && $EXTRA -eq 0 ]] && echo pass || echo fail )" \
      "$OK verified, $MISMATCH altered, $MISSING missing, $EXTRA unlisted"

    # A bundle whose plan/state never made it in is not evidence of a deployment.
    for expected in plan.json state.json; do
      if [[ -f "$BDIR/$expected" ]]; then
        record "completeness:$expected" "pass" "present"
      else
        record "completeness:$expected" "warn" "absent — capture ran without it"
      fi
    done
  fi
else
  record "bundle_extracted" "fail" "$(tr -d '\n' < "$WORK/tar.err" 2>/dev/null | cut -c1-200)"
fi

# --- Optional signature verification ------------------------------------------
if [[ -n "$SIGNATURE" ]]; then
  if ! command -v cosign >/dev/null 2>&1; then
    record "signature" "fail" "cosign not installed but --signature was requested"
  elif [[ ! -f "$SIGNATURE" ]]; then
    record "signature" "fail" "signature bundle not found: $SIGNATURE"
  elif cosign verify-blob --bundle "$SIGNATURE" \
        --certificate-identity-regexp "$IDENTITY" \
        --certificate-oidc-issuer "$ISSUER" "$TARBALL" >"$WORK/cosign.out" 2>&1; then
    record "signature" "pass" "verified against identity /$IDENTITY/ issued by $ISSUER"
  else
    record "signature" "fail" "$(tr -d '\n' < "$WORK/cosign.out" | cut -c1-200)"
  fi
fi

# --- Verdict -------------------------------------------------------------------
FAILED=$(grep -c '"status":"fail"' "$CHECKS_FILE" || true)
WARNED=$(grep -c '"status":"warn"' "$CHECKS_FILE" || true)
PASSED=$(grep -c '"status":"pass"' "$CHECKS_FILE" || true)
VERDICT=$( [[ "$FAILED" -eq 0 ]] && echo "VERIFIED" || echo "FAILED" )

jq -n \
  --slurpfile checks "$CHECKS_FILE" \
  --arg verdict "$VERDICT" --arg run_id "$RUN_ID" --arg source "$SOURCE" \
  --arg sha "$BUNDLE_SHA" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson passed "$PASSED" --argjson failed "$FAILED" --argjson warned "$WARNED" \
  '{verdict:$verdict, run_id:$run_id, source:$source, bundle_sha256:$sha,
    verified_at_utc:$at, summary:{passed:$passed,failed:$failed,warnings:$warned},
    checks:$checks}' > "$WORK/verdict.json"

if [[ $JSON_ONLY -eq 1 ]]; then
  cat "$WORK/verdict.json"
else
  jq -r '.checks[] | "  [\(.status|ascii_upcase)] \(.check): \(.detail)"' "$WORK/verdict.json"
  echo
  echo "  Verdict: $VERDICT  ($PASSED passed, $FAILED failed, $WARNED warnings)"
  echo
  cat "$WORK/verdict.json"
fi

[[ "$FAILED" -eq 0 ]] || exit 1
