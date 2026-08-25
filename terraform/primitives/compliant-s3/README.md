# compliant-s3

Terraform primitive that provisions a hardened S3 data bucket plus a dedicated
access-log bucket. Every compliance-relevant setting is annotated in `main.tf`
with the NIST 800-53 control it implements (AC-3, AU-3/AU-6, CM-6, SC-28).

## Inputs

| Name | Description | Default |
|---|---|---|
| `project_name` | Short project identifier (validated: 3–21 lowercase alphanumerics/hyphens). Becomes part of bucket names and the `Project` tag. | — |
| `environment` | `dev`, `staging`, or `prod` (validated enum). Drives the `Environment` tag. | — |
| `bucket_suffix` | Optional fixed suffix for bucket names. Defaults to a `random_id`. | `""` |

## Outputs

| Name | Description |
|---|---|
| `bucket_arn` / `bucket_name` | Primary data bucket ARN / name. |
| `log_bucket_arn` | Access-log bucket ARN. |
| `encryption_algorithm` | SSE algorithm read back from the applied resource — an SC-28 attestation from state, not an assertion. |

## Controls

| Control | Enforced by |
|---|---|
| AC-3 | `aws_s3_bucket_public_access_block` on both buckets |
| AU-3 / AU-6 | Log bucket + `aws_s3_bucket_logging` (`access-logs/` prefix) |
| CM-6 | Provider `default_tags` (Project / Environment / ManagedBy / ComplianceScope) + versioning |
| SC-28 | `aws_s3_bucket_server_side_encryption_configuration` (AES-256; commented KMS upgrade path) |

See the [repository README](../../../README.md) for architecture, evidence, and design decisions.
