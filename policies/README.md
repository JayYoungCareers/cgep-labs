# Compliance Policies

Policy-as-Code checks that read a Terraform plan (`terraform show -json`) and refuse it
when a resource violates a NIST 800-53 control. Each rule adds a control-tagged message
to a `deny` set; an empty set means compliant. Every policy is covered by tests in `tests/`.

Run the whole suite:

```bash
opa test -v policies/
```

| Policy | Control | Severity | Requires / Remediation |
|---|---|---|---|
| `sc28_encryption.rego` | **SC-28** — Encryption at Rest | high | Every `google_storage_bucket` must have a customer-managed encryption key (CMEK). *Fix:* add an `encryption { default_kms_key_name = ... }` block. |
| `ac3_no_public.rego` | **AC-3** — Access Enforcement | critical | Buckets must set `uniform_bucket_level_access = true` and `public_access_prevention = "enforced"`; firewalls must not open ports 22/3389 to `0.0.0.0/0`. *Fix:* lock the bucket down, or narrow/remove the firewall rule. |
| `cm6_required_tags.rego` | **CM-6** — Configuration Settings | medium | Every taggable resource must carry the labels `project`, `environment`, `managed_by`, `compliance_scope`. *Fix:* add the missing labels. |

Each policy carries a `# METADATA` block with these same facts (`control_id`, `framework`,
`severity`, `remediation`) so the rule is self-documenting for both tooling and auditors.