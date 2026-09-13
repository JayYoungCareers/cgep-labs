# cgep-labs

[![validate](https://github.com/JayYoungCareers/cgep-labs/actions/workflows/validate.yml/badge.svg)](https://github.com/JayYoungCareers/cgep-labs/actions/workflows/validate.yml)
![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.6-7B42BC?logo=terraform&logoColor=white)
![OPA](https://img.shields.io/badge/OPA-Rego-7D9199?logo=openpolicyagent&logoColor=white)
![NIST](https://img.shields.io/badge/NIST-800--53%20rev5-00539B)

**A compliance-as-code portfolio organized by control ID.** Each NIST 800-53 control here is implemented as a Terraform primitive or module, enforced by a Rego policy that runs against the plan, gated in CI so a violating change cannot merge, and backed by captured evidence of an actual run.

The same control is implemented twice — once for AWS, once for GCP — because a control is portable across clouds even when its implementation is not.

> Compliance frameworks name controls; engineers ship resources. Everything in this repo exists to close that gap in the most literal way available: the control ID lives in the code, in the policy, in the test, and in the evidence file.

---

## Controls

| Control | Title | Implemented by | Enforced by | Severity |
|---|---|---|---|---|
| **SC-28** | Protection of Information at Rest | `terraform/primitives/compliant-s3` (AWS, SSE-S3)<br>`terraform/modules/compliant-gcs-bucket` (GCP, CMEK) | `policies/sc28_encryption_aws.rego`<br>`policies/sc28_encryption.rego` | high |
| **AC-3** | Access Enforcement | Public access blocks (AWS)<br>Uniform access + `public_access_prevention`, no 22/3389 open to `0.0.0.0/0` (GCP) | `policies/ac3_no_public_aws.rego`<br>`policies/ac3_no_public.rego` | critical |
| **CM-6** | Configuration Settings | Provider `default_tags` / labels: `Project`, `Environment`, `ManagedBy`, `ComplianceScope` | `policies/cm6_required_tags_aws.rego`<br>`policies/cm6_required_tags.rego` | medium |
| **AU-3 / AU-6** | Content of Audit Records / Audit Review | Dedicated log bucket + `aws_s3_bucket_logging` shipping server access logs to `access-logs/` | — (structural) | — |

Every Rego rule carries a `# METADATA` block naming its control ID, framework, severity, and remediation. Rules add a control-tagged message to a `deny` set; an empty set means compliant. GCP policies are unit-tested against hand-built inputs; AWS variants are exercised end-to-end by the gate.

See [`policies/README.md`](policies/README.md) for the full control-to-file mapping.

---

## How enforcement works

**1 — Controls are written into the resource.** Each compliance-relevant setting in `main.tf` is annotated with the control it implements, so the code review *is* the control review. Input validation stops bad values at `plan`, not in production.

**2 — Modules make the floor non-negotiable.** `compliant-gcs-bucket` hardcodes the compliance floor so consumers cannot disable it. The `terraform/consumers/` callers (dev / prod / negative-test) prove the guardrails hold even when someone tries to opt out.

**3 — Policies check the plan.** Rego rules read `terraform show -json` and deny on violation:

```bash
opa test -v policies/                                              # GCP policies, unit tests
bash scripts/policy-gate.sh --workspace terraform/primitives/compliant-s3   # AWS, fail-closed gate
```

**4 — The gate is fail-closed.** `scripts/policy-gate.sh` returns a non-zero exit code and machine-readable evidence on any violation. CI runs the same three control namespaces in both directions — a compliant plan must pass, a violating plan must be denied — so a broken gate fails the build rather than silently admitting everything.

**5 — Runs become evidence.** `scripts/capture-evidence.sh` hashes, bundles, and uploads the run to an S3 Object Lock (WORM) vault; `scripts/verify-evidence.sh` fetches by `VersionId`, re-hashes, and returns a verdict. Tamper-evident by construction rather than by policy.

---

## Evidence

Captured proof of each control working, committed to the repo:

| Path | What it proves |
|---|---|
| `evidence/lab-2-3/` | Plan/state for the annotated AWS S3 primitive |
| `evidence/lab-2-4/` | Plan + `compliance_attestation.json` for the GCP module |
| `evidence/lab-2-5/` | Signed evidence bundle and vault receipts |
| `evidence/lab-3-3/` | `opa-test-results.json` — the Rego unit-test run |
| `evidence/lab-3-4/` | `conftest-pass.json` / `conftest-fail.json` — the gate, proven in both directions |

---

## Structure

```
cgep-labs/
├── terraform/
│   ├── primitives/                 # standalone units deployed directly
│   │   ├── compliant-s3/           # NIST 800-53 controls as a Terraform S3 primitive (AWS)
│   │   ├── evidence-vault/         # S3 Object Lock (WORM) vault for signed evidence bundles (AWS)
│   │   └── policy-fixture/         # plan-only, deliberately broken GCS/firewall test bed for the policies
│   ├── modules/                    # reusable modules
│   │   └── compliant-gcs-bucket/   # a compliant GCS bucket module (GCP)
│   └── consumers/                  # example callers of the module above (dev / prod / negative-test)
├── policies/                       # Policy-as-Code, organized by control ID with a per-cloud variant
│   ├── sc28_encryption.rego        #   SC-28 encryption at rest — GCP
│   ├── sc28_encryption_aws.rego    #   SC-28 encryption at rest — AWS
│   ├── ac3_no_public.rego          #   AC-3 access enforcement  — GCP
│   ├── ac3_no_public_aws.rego      #   AC-3 access enforcement  — AWS
│   ├── cm6_required_tags.rego      #   CM-6 required labels     — GCP
│   ├── cm6_required_tags_aws.rego  #   CM-6 required tags       — AWS
│   ├── tests/                      #   opa unit tests for the GCP policies
│   └── README.md                   #   which file targets which control and cloud
├── scripts/
│   ├── capture-evidence.sh         # hash, bundle, and upload evidence to the vault
│   ├── verify-evidence.sh          # fetch by VersionId, re-hash, verdict
│   ├── policy-gate.sh              # the Conftest gate CI calls to block violating plans
│   └── RUNBOOK.md                  # step-by-step guide to the evidence capture workflow
├── tests/                          # shell tests for the scripts above
└── evidence/                       # captured proof, one folder per lab
    ├── lab-2-3/
    ├── lab-2-4/
    ├── lab-2-5/
    ├── lab-3-3/
    └── lab-3-4/
```

---

## CI

[`.github/workflows/validate.yml`](.github/workflows/validate.yml) runs on every push and pull request, in three jobs:

| Job | What it runs |
|---|---|
| `terraform` | `terraform fmt`, `validate`, `tflint`, `checkov` (config in `.checkov.yaml`) |
| `shell` | `shellcheck` over `scripts/` and `tests/`, plus the evidence-verifier test suite |
| `policy` | `opa test` over the GCP policy unit tests, then `conftest` across all three AWS control namespaces — against a compliant plan (must pass) and a violating plan (must be denied) |

Actions are pinned to full commit SHAs, and the workflow holds read-only `contents` permission. Checkov skips are documented in `.checkov.yaml` rather than suppressed silently.

## Scope

Lab-scoped by design: no cross-region replication, no lifecycle/retention rules, local state (no remote backend). Each is a deliberate scope cut, and each is a documented skip rather than an oversight. On the roadmap: bucket-policy-based log delivery, a CMEK variant for the AWS primitive, and lifecycle/retention rules.

---

<sub>Built through the **GRC Engineering Club** Compliance-as-Code curriculum (CGEP). The `evidence/` folders retain their original lab numbering for traceability to the source exercises.</sub>
