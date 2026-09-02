# Compliance Policies

Policy-as-Code checks that read a Terraform plan (`terraform show -json`) and refuse it
when a resource violates a NIST 800-53 control. Each rule adds a control-tagged message to
a `deny` set; an empty set means compliant. The library is organized by **control ID**, with
a per-cloud variant wherever the underlying resource types differ.

**GCP policies** — unit-tested against hand-built inputs:

```bash
opa test -v policies/
```

**AWS policies** — run as a fail-closed gate against a real plan:

```bash
bash scripts/policy-gate.sh --workspace terraform/primitives/compliant-s3
```

| Control | Cloud | File | Severity | Requires |
|---|---|---|---|---|
| **SC-28** Encryption at Rest | GCP | `sc28_encryption.rego` | high | `google_storage_bucket` has a customer-managed encryption key (CMEK). |
| **SC-28** Encryption at Rest | AWS | `sc28_encryption_aws.rego` | high | `aws_s3_bucket` has a matching `aws_s3_bucket_server_side_encryption_configuration`. |
| **AC-3** Access Enforcement | GCP | `ac3_no_public.rego` | critical | Buckets enforce uniform access + `public_access_prevention`; firewalls don't open 22/3389 to `0.0.0.0/0`. |
| **AC-3** Access Enforcement | AWS | `ac3_no_public_aws.rego` | critical | `aws_s3_bucket` has an `aws_s3_bucket_public_access_block` with all four flags `true`. |
| **CM-6** Configuration Settings | GCP | `cm6_required_tags.rego` | medium | Required labels: `project`, `environment`, `managed_by`, `compliance_scope`. |
| **CM-6** Configuration Settings | AWS | `cm6_required_tags_aws.rego` | medium | Required tags: `Project`, `Environment`, `ManagedBy`, `ComplianceScope` (via `default_tags` → `tags_all`). |

Every policy carries a `# METADATA` block with its control ID, framework, severity, and
remediation. GCP rules are unit-tested in `tests/`; the AWS variants are exercised by
`scripts/policy-gate.sh`, the fail-closed gate CI calls to block any plan that violates a control.