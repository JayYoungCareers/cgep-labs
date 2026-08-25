# variables.tf
#
# Module interface. Only naming, placement, and labeling are configurable.
# Compliance-critical settings (encryption, key rotation, versioning,
# uniform access) are NOT variables — see main.tf.

variable "gcp_project" {
  type        = string
  description = "GCP project ID where the bucket and KMS resources will live."
}

variable "project_label" {
  type        = string
  description = "Short project identifier used in resource naming and labeling."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_label))
    error_message = "project_label must be 3-21 lowercase alphanumerics or hyphens, starting with a letter."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  type        = string
  description = "GCS bucket location. Multi-regions like US, EU are valid for buckets."
  default     = "us-central1"
}

variable "kms_location" {
  type        = string
  description = "KMS keyring location. Must be a single region (multi-regions are not supported for keyrings)."
  default     = "us-central1"
}

variable "bucket_name_suffix" {
  type        = string
  description = "Globally-unique suffix appended to the bucket name and reused to derive the KMS key ring/key names."

  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.bucket_name_suffix))
    error_message = "bucket_name_suffix must be 3-30 lowercase alphanumerics or hyphens."
  }
}

variable "retention_days" {
  type        = number
  description = "Object retention floor in days, enforced for AU-11 audit-trail retention. Production must be >= 365."

  validation {
    condition     = var.retention_days >= 1 && var.retention_days <= 3650
    error_message = "retention_days must be between 1 and 3650."
  }

  validation {
    condition     = var.environment != "prod" || var.retention_days >= 365
    error_message = "retention_days must be >= 365 when environment == \"prod\"."
  }
}

variable "labels" {
  type        = map(string)
  description = "Additional labels merged onto the bucket. Required compliance labels take precedence on key collision and cannot be overridden."
  default     = {}
}
