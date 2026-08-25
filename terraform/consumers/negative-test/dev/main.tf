# consumers/dev/main.tf
terraform {
  required_version = ">= 1.9" # cross-variable validation in the module requires 1.9+
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

provider "google" {
  project = "gcp-labs-418118"
  region  = "us-central1"
}

module "data_bucket" {
  source = "../../modules/compliant-gcs-bucket"

  gcp_project        = "gcp-labs-418118"
  project_label      = "cgep-lab-2"
  environment        = "prod"
  retention_days     = 30
  bucket_name_suffix = "should-never-exist"
}

output "attestation" { value = module.data_bucket.compliance_attestation }
output "bucket_url" { value = module.data_bucket.bucket_url }