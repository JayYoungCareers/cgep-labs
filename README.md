# cgep-labs

Hands-on labs for the GRC Engineering Club, building toward a single portfolio repository that treats compliance evidence as code: Terraform primitives and modules that encode security controls, Rego policies that enforce them across clouds, and scripts that capture, sign, and gate proof of what was actually deployed.

## Structure

```
cgep-labs/
├── terraform/
│   ├── primitives/                 # standalone units deployed directly
│   │   ├── compliant-s3/           # Lab 2.3 — NIST 800-53 controls as a Terraform S3 primitive (AWS)
│   │   ├── evidence-vault/         # Lab 2.5 — S3 Object Lock (WORM) vault for signed evidence bundles (AWS)
│   │   └── policy-fixture/         # Lab 3.3 — plan-only, deliberately broken GCS/firewall test bed for the policies
│   ├── modules/                    # reusable modules
│   │   └── compliant-gcs-bucket/   # Lab 2.4 — a compliant GCS bucket module (GCP)
│   └── consumers/                  # example callers of the module above (dev / prod / negative-test)
├── policies/                       # Policy-as-Code, organized by control ID with a per-cloud variant
│   ├── sc28_encryption.rego        #   SC-28 encryption at rest — GCP (Lab 3.3)
│   ├── sc28_encryption_aws.rego    #   SC-28 encryption at rest — AWS (Lab 3.4)
│   ├── ac3_no_public.rego          #   AC-3 access enforcement  — GCP (Lab 3.3)
│   ├── ac3_no_public_aws.rego      #   AC-3 access enforcement  — AWS (Lab 3.4)
│   ├── cm6_required_tags.rego      #   CM-6 required labels     — GCP (Lab 3.3)
│   ├── cm6_required_tags_aws.rego  #   CM-6 required tags       — AWS (Lab 3.4)
│   ├── tests/                      #   opa unit tests for the GCP policies
│   └── README.md                   #   which file targets which control and cloud
├── scripts/
│   ├── capture-evidence.sh         # Lab 2.5 — hash, bundle, and upload evidence to the vault
│   ├── verify-evidence.sh          # Lab 2.5 — fetch by VersionId, re-hash, verdict
│   ├── policy-gate.sh              # Lab 3.4 — the Conftest gate CI calls to block violating plans
│   └── RUNBOOK.md                  # step-by-step guide to the evidence capture workflow
├── tests/                          # shell tests for the scripts above
└── evidence/                       # captured proof, one folder per lab
    ├── lab-2-3/                    # plan.json / state.json for the compliant-s3 primitive
    ├── lab-2-4/                    # plan.json / compliance_attestation.json for the module lab
    ├── lab-2-5/                    # signed evidence bundle + receipts for the evidence-vault lab
    ├── lab-3-3/                    # opa-test-results.json — the Rego unit-test run
    └── lab-3-4/                    # conftest-pass.json / conftest-fail.json — the gate, both directions
```

## Labs

- **Lab 2.3 — NIST 800-53 Controls as Terraform Resources**: encodes specific NIST 800-53 controls directly into a Terraform S3 bucket resource. See `terraform/primitives/compliant-s3/README.md`.
- **Lab 2.4 — Terraform Modules for Compliance**: extracts a compliant GCS bucket into a reusable module, with dev/prod/negative-test consumers proving the guardrails hold. See `terraform/modules/compliant-gcs-bucket/README.md`.
- **Lab 2.5 — IaC as Compliance Evidence**: an S3 Object Lock evidence vault and capture pipeline that turns Terraform runs into tamper-evident, cryptographically signed audit evidence. See `terraform/primitives/evidence-vault/README.md` and `scripts/RUNBOOK.md`.
- **Lab 3.3 — Writing Compliance Policies in Rego (GCP)**: three Rego policies — SC-28 (encryption at rest), AC-3 (no public access / no open management ports), and CM-6 (required labels) — that read a Terraform plan and add a control-tagged message to a `deny` set on any violation, each backed by passing *and* failing unit tests. Run with `opa test -v policies/`; a plan-only `policy-fixture` supplies the (non-)compliant infrastructure to check against. See `policies/` and `policies/README.md`.
- **Lab 3.4 — Integrating PaC with Terraform via Conftest (AWS)**: AWS variants of the same three control IDs (`*_aws.rego`) — showing that a control is portable across clouds even when its implementation is not — wired into `scripts/policy-gate.sh`, a fail-closed gate that returns a non-zero exit code (and machine-readable evidence) on any violation. It's the exact script the capstone's CI pipeline calls. Evidence in `evidence/lab-3-4/`.

## CI

`.github/workflows/validate.yml` runs `terraform fmt`, `validate`, `tflint`, and `checkov` (config in `.checkov.yaml`) over the Terraform, plus `shellcheck` and the evidence-verifier test suite — on every push and pull request.
