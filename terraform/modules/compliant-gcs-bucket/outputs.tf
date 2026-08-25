# outputs.tf

output "bucket_name" {
  description = "Name of the compliance-hardened bucket."
  value       = google_storage_bucket.bucket.name
}

output "bucket_url" {
  description = "gs:// URL of the compliant bucket."
  value       = google_storage_bucket.bucket.url
}

output "bucket_self_link" {
  description = "Self-link of the compliant bucket."
  value       = google_storage_bucket.bucket.self_link
}

output "kms_key_ring_id" {
  description = "Fully-qualified ID of the KMS key ring backing the bucket's CMEK."
  value       = google_kms_key_ring.ring.id
}

output "kms_key_id" {
  description = "Resource ID of the CMEK key protecting this bucket."
  value       = google_kms_crypto_key.key.id
}

# Machine-readable evidence for downstream labs. Each entry ties a control
# to the resource attribute(s) that enforce it and reads the value back from
# actual Terraform state, so a consuming lab verifies the claim rather than
# trusting a label.
output "compliance_attestation" {
  description = "Structured compliance evidence for this module's instance, consumed by downstream labs as an audit artifact."
  value = {
    subject   = google_storage_bucket.bucket.name
    generated = timestamp()

    controls = {
      "SC-12" = {
        title       = "Cryptographic Key Establishment and Management"
        enforced_by = "google_kms_key_ring.ring, google_kms_crypto_key.key"
        evidence = {
          key_ring = google_kms_key_ring.ring.id
          key      = google_kms_crypto_key.key.id
        }
      }
      "SC-13" = {
        title       = "Cryptographic Protection"
        enforced_by = "google_kms_crypto_key.key.rotation_period"
        evidence = {
          rotation_period = google_kms_crypto_key.key.rotation_period
        }
      }
      "SC-28" = {
        title       = "Protection of Information at Rest"
        enforced_by = "google_storage_bucket.bucket.encryption, versioning"
        evidence = {
          kms_key_name       = google_storage_bucket.bucket.encryption[0].default_kms_key_name
          versioning_enabled = google_storage_bucket.bucket.versioning[0].enabled
        }
      }
      "AU-11" = {
        title       = "Audit Record Retention"
        enforced_by = "google_storage_bucket.bucket.retention_policy"
        evidence = {
          retention_period_days = var.retention_days
          retention_locked      = google_storage_bucket.bucket.retention_policy[0].is_locked
        }
      }
      "CM-6" = {
        title       = "Configuration Settings"
        enforced_by = "google_storage_bucket.bucket.uniform_bucket_level_access, public_access_prevention, labels"
        evidence = {
          uniform_bucket_level_access = google_storage_bucket.bucket.uniform_bucket_level_access
          public_access_prevention    = google_storage_bucket.bucket.public_access_prevention
          required_labels_present = alltrue([
            for k in keys(local.required_labels) : contains(keys(google_storage_bucket.bucket.labels), k)
          ])
        }
      }
    }
  }
}
