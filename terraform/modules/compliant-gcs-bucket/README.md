# compliant-gcs-bucket

A Terraform module that provisions a CMEK-encrypted, access-locked Google
Cloud Storage bucket. The module's body hardcodes every compliance-relevant
setting; the interface (`variables.tf`) exposes only naming, placement, and
optional extra labels. A consumer cannot disable encryption, uniform access,
versioning, or the required labels — those are literals in `main.tf`, not
variables.

## Usage

```hcl
module "data_bucket" {
  source = "../../modules/compliant-gcs-bucket"

  gcp_project        = "your-gcp-project"
  project_label      = "cgep-lab-2"
  environment        = "dev"          # dev | staging | prod
  retention_days     = 30             # prod requires >= 365
  bucket_name_suffix = "dev-data-001"
}

output "attestation" { value = module.data_bucket.compliance_attestation }
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `gcp_project` | GCP project ID where the bucket and KMS resources live. | — |
| `project_label` | Short project identifier used in naming/labeling. | — |
| `environment` | `dev`, `staging`, or `prod`. | — |
| `retention_days` | Object retention floor in days (1–3650). Must be ≥ 365 when `environment == "prod"`. | — |
| `bucket_name_suffix` | Globally-unique suffix for the bucket name; also derives the KMS key ring/key names. | — |
| `location` | GCS bucket location. Multi-regions (`US`, `EU`) are valid. | `us-central1` |
| `kms_location` | KMS key ring location. Must be a single region — multi-regions are not supported for key rings. | `us-central1` |
| `labels` | Extra labels merged onto the bucket. Required compliance labels take precedence on key collision and cannot be overridden. | `{}` |

## Outputs

| Name | Description |
|---|---|
| `bucket_name` | Name of the compliance-hardened bucket. |
| `bucket_url` | `gs://` URL of the bucket. |
| `bucket_self_link` | Self-link of the bucket. |
| `kms_key_ring_id` | Fully-qualified ID of the KMS key ring backing the bucket's CMEK. |
| `kms_key_id` | Resource ID of the CMEK key protecting the bucket. |
| `compliance_attestation` | Structured, machine-readable evidence map. Each control cites the resource attribute(s) that enforce it and reads the value back from Terraform state, so downstream consumers verify the claim rather than trust a label. |

## Controls enforced

None of the settings below are exposed as variables — a consumer cannot turn
them off.

| Control | Title | Enforced by | Evidence field(s) |
|---|---|---|---|
| SC-12 | Cryptographic Key Establishment and Management | `google_kms_key_ring.ring`, `google_kms_crypto_key.key` — the module owns the key ring and key; a consumer cannot supply their own or opt out of CMEK. | `compliance_attestation.controls.SC-12.evidence.key_ring`, `.key` |
| SC-13 | Cryptographic Protection | `google_kms_crypto_key.key.rotation_period` hardcoded to `7776000s` (90 days). | `compliance_attestation.controls.SC-13.evidence.rotation_period` |
| SC-28 | Protection of Information at Rest | `google_storage_bucket.bucket.encryption.default_kms_key_name` (CMEK) and `versioning.enabled = true`, both hardcoded. | `compliance_attestation.controls.SC-28.evidence.kms_key_name`, `.versioning_enabled` |
| AU-11 | Audit Record Retention | `google_storage_bucket.bucket.retention_policy.retention_period`, driven by the validated `retention_days` variable (≥ 365 for prod); `is_locked` is hardcoded `false` — not a variable a consumer could flip. | `compliance_attestation.controls.AU-11.evidence.retention_period_days`, `.retention_locked` |
| CM-6 | Configuration Settings | `uniform_bucket_level_access = true`, `public_access_prevention = "enforced"`, and required labels (`project`, `environment`, `managed_by`, `compliance_scope`) merged on top of any consumer-supplied labels so they always win on key collision. | `compliance_attestation.controls.CM-6.evidence.uniform_bucket_level_access`, `.public_access_prevention`, `.required_labels_present` |

## Notes

- `required_version = ">= 1.9"` — the `retention_days` variable has two
  `validation` blocks (range check, then prod-specific floor), which
  requires Terraform 1.9+.
- `google_kms_crypto_key.key` has `lifecycle { prevent_destroy = true }`.
  Destroying a consumer's bucket does not delete the key; it is a
  deliberate one-way door.
- `retention_policy.is_locked` is left `false` in this module. Locking is
  irreversible on real GCP infrastructure — a production variant should
  lock deliberately in code, never via a variable a consumer could set.
