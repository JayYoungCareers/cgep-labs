# Lab 2.5 Runbook — IaC as Compliance Evidence (AWS)

This runbook covers the **live AWS steps** you run yourself. All the code is already
written and placed in this repo (see layout below). You just deploy, capture, verify,
and prove immutability.

Your AWS profile is assumed to be **`JayYoungCareersComplianceLab`** throughout.

## Where to run this

These commands are **bash**. On Windows, run them in **WSL** or **Git Bash**, not
PowerShell. You'll need on PATH: `aws` (CLI v2), `terraform` (>= 1.6), `git`,
`tar`, and `sha256sum`. `cosign` only for the optional Step 5.

Keep everything in **one terminal session** — `$VAULT` and `$VERSION_ID` are shell
variables set in earlier steps and reused later.

## Repo layout (already built for you)

```
IaC as Compliance Evidence/            <- lab-2-5 root (this folder)
├── terraform/
│   └── primitives/
│       └── evidence-vault/
│           ├── main.tf                <- the Object Lock vault
│           ├── variables.tf
│           └── outputs.tf             <- vault_name output (was empty; now filled)
├── scripts/
│   └── capture-evidence.sh            <- capture → hash → tar → upload → JSON receipt
├── evidence/
│   └── lab-2-5/
│       ├── receipt.example.json       <- shape reference only
│       └── receipt.json               <- created when you run Step 2
├── .gitignore
└── RUNBOOK.md
```

---

## Step 1 — Deploy the vault

```bash
cd "terraform/primitives/evidence-vault"

# Export sandbox creds so Terraform's AWS provider can authenticate
eval "$(aws configure export-credentials --profile JayYoungCareersComplianceLab --format env)"

terraform init
terraform apply -auto-approve

# Grab the vault bucket name for later steps
VAULT=$(terraform output -raw vault_name)
echo "VAULT=$VAULT"
```

You should see one S3 bucket plus its versioning, object-lock, encryption,
public-access-block, and bucket-policy resources created.

## Step 2 — Capture evidence from your Lab 2.3 workspace

```bash
# Back out to the lab-2-5 root (this folder)
cd ../../..

# IMPORTANT: point --workspace at your actual Lab 2.3 Terraform workspace.
# The lab's example is a sibling folder named lab-2-3; adjust to your real path.
bash scripts/capture-evidence.sh \
  --workspace "../lab-2-3" \
  --run-id    test-001 \
  --vault     "$VAULT" \
  --profile   JayYoungCareersComplianceLab \
  | tee evidence/lab-2-5/receipt.json

# Save the durable handle for the verify + delete + cleanup steps
VERSION_ID=$(python3 -c "import json;print(json.load(open('evidence/lab-2-5/receipt.json'))['version_id'])")
echo "VERSION_ID=$VERSION_ID"
```

`receipt.json` now holds `run_id`, `vault`, `key`, `version_id`, `captured_at_utc`.
That `version_id` is the durable pointer to this exact evidence object — anything
that references this evidence later uses `s3://$VAULT/runs/test-001/bundle.tar.gz?versionId=$VERSION_ID`.

> If `terraform` isn't on PATH inside the Lab 2.3 workspace shell, the script still
> runs — `plan.json`/`state.json`/`version.txt` come from `terraform`, and the script
> tolerates their absence (the bundle just carries fewer files). For a full bundle,
> make sure `terraform` and `git` work inside `../lab-2-3`.

## Step 3 — Verify retention was applied

```bash
aws s3api get-object-retention \
  --bucket "$VAULT" \
  --key runs/test-001/bundle.tar.gz \
  --profile JayYoungCareersComplianceLab
```

Expected — retention was set automatically by the bucket's default rule, not by you:

```json
{ "Retention": { "Mode": "GOVERNANCE", "RetainUntilDate": "<utc-timestamp>" } }
```

## Step 4 — The destructive test (this is the lesson)

```bash
aws s3api delete-object \
  --bucket "$VAULT" \
  --key runs/test-001/bundle.tar.gz \
  --version-id "$VERSION_ID" \
  --profile JayYoungCareersComplianceLab
```

Expected — **the failure is the passing result:**

```
An error occurred (AccessDenied) when calling the DeleteObject operation:
Access Denied because object protected by object lock.
```

That rejection is your proof of immutability: the evidence resists silent tampering,
even by an admin who would rather it not exist.

## Step 5 — (Stretch) Sign the bundle with Cosign

The capture script left the tarball at `/tmp/bundle-test-001.tar.gz`. Keyless signing
opens a browser for the OIDC flow.

```bash
COSIGN_EXPERIMENTAL=1 cosign sign-blob \
  --yes --bundle bundle.sig.bundle \
  /tmp/bundle-test-001.tar.gz

aws s3 cp bundle.sig.bundle "s3://$VAULT/runs/test-001/bundle.sig.bundle" \
  --profile JayYoungCareersComplianceLab
```

---

## Verification — three checks that should all pass

```bash
# 1. Object Lock configured at the bucket level
aws s3api get-object-lock-configuration --bucket "$VAULT" \
  --profile JayYoungCareersComplianceLab

# 2. Retention present on the uploaded object
aws s3api get-object-retention --bucket "$VAULT" \
  --key runs/test-001/bundle.tar.gz \
  --profile JayYoungCareersComplianceLab

# 3. Deletion attempt is refused (expect AccessDenied)
aws s3api delete-object --bucket "$VAULT" \
  --key runs/test-001/bundle.tar.gz \
  --version-id "$VERSION_ID" \
  --profile JayYoungCareersComplianceLab
```

## Cleanup (GOVERNANCE only)

GOVERNANCE retention allows a privileged bypass so you can clean up a lab. (COMPLIANCE
would not — the objects would sit until every retention expired.)

```bash
# Delete the test object, bypassing governance retention
aws s3api delete-object --bucket "$VAULT" \
  --key runs/test-001/bundle.tar.gz \
  --version-id "$VERSION_ID" --bypass-governance-retention \
  --profile JayYoungCareersComplianceLab

# Remove any remaining versions and delete markers
aws s3api list-object-versions --bucket "$VAULT" --output json \
  --profile JayYoungCareersComplianceLab \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); items=[*d.get("Versions",[]),*d.get("DeleteMarkers",[])]; print(json.dumps({"Objects":[{"Key":o["Key"],"VersionId":o["VersionId"]} for o in items]}))' > /tmp/del.json

aws s3api delete-objects --bucket "$VAULT" --delete file:///tmp/del.json \
  --bypass-governance-retention \
  --profile JayYoungCareersComplianceLab || true

# Tear down the vault
cd terraform/primitives/evidence-vault
terraform destroy -auto-approve
```

## Portfolio submission checklist

- [x] `terraform/primitives/evidence-vault/` deploys the vault — **built**
- [x] `scripts/capture-evidence.sh` committed and executable — **built** (run `chmod +x` if git dropped the bit)
- [x] One bundle uploaded with its VersionId in `evidence/lab-2-5/receipt.json` — **produced by Step 2**
- [x] (Stretch) Cosign signature alongside the bundle — **Step 5**

## Troubleshooting

- **`InvalidBucketState: Object Lock ... cannot be enabled on existing buckets`** — Object
  Lock must be set at bucket creation; no upgrade path. `terraform destroy` and recreate.
- **Retention window too long in COMPLIANCE mode** — you cannot shorten it. For labs stay on
  GOVERNANCE + 1 day (the current defaults in `variables.tf`).
- **Clock drift** — `RetainUntilDate` is wall-clock UTC. Trust the server's date, not your laptop's.
- **Cosign keyless from a laptop** needs a browser for the OIDC flow. In CI it's automatic via
  `permissions: id-token: write` (that's Lab 4.4).
