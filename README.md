# cgep-labs

Hands-on labs for the GRC Engineering Club, building toward a single portfolio repository that treats compliance evidence as code: Terraform primitives and modules that encode security controls, Rego policies that enforce them, and scripts that capture and sign proof of what was actually deployed.

## Structure

```
cgep-labs/
├── terraform/
│   ├── primitives/          # standalone units deployed directly
│   │   ├── compliant-s3/    # Lab 2.3 — NIST 800-53 controls as a Terraform S3 primitive
│   │   └── evidence-vault/  # Lab 2.5 — S3 Object Lock (WORM) vault for signed evidence bundles
│   ├── modules/              # reusable modules
│   │   └── compliant-gcs-bucket/  # Lab 2.4 — a compliant GCS bucket module
│   └── consumers/            # example callers of the modules above (dev / prod / negative-test)
├── policies/                  # Rego policies (and their tests) that validate Terraform plans against controls
├── scripts/                   # shared scripts, including the evidence capture/verify pipeline
│   └── RUNBOOK.md             # step-by-step guide to the evidence capture workflow
├── tests/                     # shell tests for the scripts above
└── evidence/                  # captured proof, one folder per lab
    ├── lab-2-3/               # plan.json / state.json for the compliant-s3 primitive
    ├── lab-2-4/               # plan.json / compliance_attestation.json for the module lab
    └── lab-2-5/                # signed evidence bundle + receipts for the evidence-vault lab
```

## Labs

- **Lab 2.3 — NIST 800-53 Controls as Terraform Resources**: encodes specific NIST 800-53 controls directly into a Terraform S3 bucket resource. See `terraform/primitives/compliant-s3/README.md`.
- **Lab 2.4 — Terraform Modules for Compliance**: extracts a compliant GCS bucket into a reusable module, with dev/prod/negative-test consumers proving the guardrails hold. See `terraform/modules/compliant-gcs-bucket/README.md`.
- **Lab 2.5 — IaC as Compliance Evidence**: an S3 Object Lock evidence vault and capture pipeline that turns Terraform runs into tamper-evident, cryptographically signed audit evidence. See `terraform/primitives/evidence-vault/README.md` and `scripts/RUNBOOK.md`.
- **Lab 3.3 — Writing Compliance Policies in Rego**: Rego policies (with tests) that check Terraform plans against the same control set programmatically. See `policies/`.

## CI

`.github/workflows/validate.yml` runs `checkov` (config in `.checkov.yaml`) and the policy/evidence tests against every change.
