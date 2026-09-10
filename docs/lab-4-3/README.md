# Lab 4.3: Building a GRC Evidence Pipeline (AWS + GitHub Actions)

The Conftest gate from Lab 3.4 runs on your laptop. That protects you, and does nothing for a teammate who skips it. This lab moves the gate to GitHub's servers, where it runs automatically on every pull request and nobody can skip it. On each run the pipeline plans the Terraform, runs the policies, scans for misconfigurations, and writes a named evidence file. The result is a control that enforces itself and documents itself at the same time.

## Keyless trust with OIDC

The pipeline needs to read the AWS account to run a plan. The old way was to paste a long-lived AWS access key into GitHub's secrets, a standing credential that grants access to anyone who leaks it. This lab uses OIDC instead. GitHub and AWS establish trust once, and then on each run GitHub hands AWS a short-lived token that proves the run comes from this specific repository. AWS returns temporary credentials that expire when the job ends. No secret is stored, nothing outlives the run, and the trust is scoped to one repo.

`terraform/primitives/oidc-trust/main.tf` creates two things: the OIDC provider (the trust anchor) and a read-only IAM role (`cgep-grc-gate`) whose trust policy allows only tokens whose subject matches this repository. That single subject condition is the difference between scoped trust and an open door, so it is never loosened to a wildcard across repositories.

## What the pipeline does

`.github/workflows/grc-gate.yml` runs on every pull request into `main`:

1. Assume the read-only AWS role through OIDC (no stored keys).
2. `terraform init` / `validate` / `plan` on the compliant-s3 workspace.
3. Conftest gate over the AWS control namespaces (SC-28, AC-3, CM-6). A violation exits non-zero and fails the build.
4. tfsec scan. A high or critical finding fails the build.
5. Upload `plan.json`, `plan.txt`, `conftest-results.json`, and `tfsec.sarif` as a run artifact.

Three choices make it behave correctly. `permissions: id-token: write` is what lets the run mint an OIDC token; without it OIDC fails with a misleading error. `if: always()` on the scan, copy, and upload steps means the evidence is captured even when the gate fails, because the entire value of CI evidence is that it survives the failure it documents. The tools' own exit codes decide pass or fail, so no JSON parsing runs on the runner.

## The evidence is the point

Every meaningful line of the workflow maps to a control, which is why the committed YAML is itself an audit artifact:

| What is in the workflow | NIST 800-53 control |
|---|---|
| `on: pull_request` plus branch protection requiring this check | CM-3 (configuration change control) |
| Required tags enforced through Conftest in the same run | CM-6 (configuration settings) |
| The workflow running on every change | CA-2, CA-7 (assessment, continuous monitoring) |
| tfsec scanning every change | RA-5 (vulnerability scanning) |
| Run history and evidence retained | AU-9 (protection of audit information) |

An assessor follows the run link to the evidence instead of asking for a screenshot.

## Files

- `terraform/primitives/oidc-trust/main.tf` the OIDC provider and the read-only, repo-scoped role
- `.github/workflows/grc-gate.yml` the pipeline
- `evidence/lab-4-3/` the per-run artifact contents (`plan.json`, `plan.txt`, `conftest-results.json`, `tfsec.sarif`), produced by the workflow rather than committed

## Run and prove it

One time, apply the trust and register the role ARN as a repo variable:

```bash
cd terraform/primitives/oidc-trust
terraform apply -var=github_org=<org> -var=github_repo=cgep-labs \
  -var=github_org_id=<org_id> -var=github_repo_id=<repo_id>
gh variable set AWS_ROLE_ARN --body "$(terraform output -raw role_arn)" --repo <org>/cgep-labs
cd ../../..
```

Then demonstrate the gate with two pull requests, the pair a capstone needs:

- Green PR: the compliant code passes. OIDC assumes the role, Terraform plans, Conftest passes all namespaces, tfsec is clean, and an evidence artifact is attached.
- Red PR: introduce one violation (for example set `block_public_acls = false` on the primary bucket). The Conftest gate fails, names the control and the resource, and with branch protection on `main` the merge is blocked.

## Verify

- Opening a PR triggers the workflow, visible in the Actions tab.
- Each run attaches `grc-evidence-<run-id>` holding `plan.json`, `conftest-results.json`, `tfsec.sarif`, and `plan.txt`.
- Compliant code ends green. Non-compliant code fails with named control IDs in the Conftest evidence, for example:

```json
{ "namespace": "compliance.ac3_aws", "successes": 0,
  "failures": [ { "msg": "[AC-3] aws_s3_bucket.primary: missing or incomplete aws_s3_bucket_public_access_block. All four flags must be true." } ] }
```

- Branch protection on `main` requires the `grc-gate` check, so a failing run blocks the merge rather than only marking it red.

## Notes from the build

Three problems surfaced here that the guide did not predict, and each is worth recording.

GitHub immutable subject claims. This repo issues OIDC tokens whose subject embeds numeric organization and repository IDs (`repo:<org>@<org_id>/<repo>@<repo_id>:...`) rather than the classic `repo:<org>/<repo>:...`. The trust policy has to match that exact prefix, otherwise AWS returns "Not authorized to perform sts:AssumeRoleWithWebIdentity" even though the policy looks correct. Matching the immutable subject keeps the security feature on and the trust scoped.

A provider lock contradiction. The compliant-s3 lock pinned the AWS provider at a 6.x version while the module constrained it to `~> 5.0`. Local runs never re-resolved because of a warm cache, and the earlier CI only initialized a different directory, so the contradiction only appeared on a clean-room Linux init. Regenerating the lock for both `linux_amd64` and `windows_amd64` fixed the version and the cross-platform hashes at once.

A control-strength decision. tfsec flagged the primary bucket for encrypting with the AWS-managed AES256 key rather than a customer-managed key. SC-28 is satisfied either way at the level of "encrypted at rest," but holding the key adds control over rotation, access, and revocation. The bucket was switched to a customer-managed KMS key with rotation enabled and an explicit key policy, the stronger reading of the control.
