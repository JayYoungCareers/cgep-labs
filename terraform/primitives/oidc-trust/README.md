# oidc-trust

Terraform primitive that establishes keyless GitHub-to-AWS trust for the GRC evidence
pipeline (Lab 4.3). It creates a GitHub OIDC provider and a read-only IAM role
(`cgep-grc-gate`) that GitHub Actions assumes on every pull request, so the pipeline reads
the account with short-lived tokens instead of a stored access key.

## Inputs

| Name | Description |
|---|---|
| `github_org` | GitHub org or user that owns the repo (e.g. `JayYoungCareers`). |
| `github_repo` | Repository name (`cgep-labs`). |
| `github_org_id` | Numeric account/org ID — part of the immutable OIDC subject. |
| `github_repo_id` | Numeric repository ID — part of the immutable OIDC subject. |

## Outputs

| Name | Description |
|---|---|
| `role_arn` | ARN of the read-only role GitHub Actions assumes. Register it as the `AWS_ROLE_ARN` repo variable. |

## How the trust works

GitHub mints a short-lived OIDC token per run whose subject is scoped to this repository;
the role's trust policy accepts only that subject, and AWS returns temporary credentials that
expire when the job ends. No access key is stored, and the subject condition is never loosened
to a wildcard. This repo uses GitHub's immutable subject claims, so the subject carries numeric
org and repo IDs (`repo:<org>@<org_id>/<repo>@<repo_id>:...`), which is why the two `_id` inputs
exist.

## The pipeline it enables

`.github/workflows/grc-gate.yml` assumes this role, plans the `compliant-s3` workspace, runs the
Conftest control gate and a `tfsec` scan, and uploads a per-run evidence artifact to
`evidence/lab-4-3/`. Every meaningful line maps to a control:

| What in the workflow | NIST 800-53 |
|---|---|
| `on: pull_request` + branch protection requiring this check | CM-3 configuration change control |
| Required tags enforced through Conftest | CM-6 configuration settings |
| The gate running on every change | CA-2 / CA-7 assessment + continuous monitoring |
| `tfsec` scanning every change | RA-5 vulnerability scanning |
| Run history + retained evidence artifact | AU-9 protection of audit information |

## Run

```bash
terraform init
terraform apply -var=github_org=<org> -var=github_repo=cgep-labs \
  -var=github_org_id=<org_id> -var=github_repo_id=<repo_id>
gh variable set AWS_ROLE_ARN --body "$(terraform output -raw role_arn)" --repo <org>/cgep-labs
```

Prove the gate with two pull requests: a compliant one that passes green, and one with a
deliberate violation (for example `block_public_acls = false`) that the gate fails by control
ID. With branch protection on `main`, the failing PR cannot merge.

## Verify

- Opening a PR triggers `grc-gate`; each run attaches `grc-evidence-<run-id>` (`plan.json`, `conftest-results.json`, `tfsec.sarif`, `plan.txt`).
- Compliant code ends green; a violation fails with a named control, e.g. `[AC-3] aws_s3_bucket.primary: missing or incomplete aws_s3_bucket_public_access_block`.
- `main` requires the `grc-gate` check, so a failing gate blocks the merge.

See the [repository README](../../../README.md) for architecture, evidence, and design decisions.
