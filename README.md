# gnc-sw-infra

GNC SW team infrastructure-as-code. Scoped deploy lane: everything in this repo
applies within the boundary/deployer sandbox that platform engineering provisions
(`GNC-SW-Dev-Deploy` permission set, provisioned 2026-09-13; the prior
`Mach-GNC-SW-Dev-Deploy` identity was retired that day with replacement
assignments and EKS access preserved; IAM guarded by the `mach-gnc-*` boundary).

What lives here: GNC SW workload stacks (sim rigs, batch compute, app infra) for the
GNC SW accounts. What does NOT live here: IAM roots, permission sets, boundaries,
OIDC roles, org/account scaffold — those are platform-engineering's repo. If an
apply fails with an IAM/boundary denial, that's the guardrail working: ask platform.

## Layout

```
aws-gov/
  dev/
    polaris-sim/     # Unreal/Polaris GPU sim stack (GC-GNC-SW-Dev 393769260826)
```

Growth: `aws-gov/prod/...`, `aws-commercial/dev/...` — same flat pattern, one dir
per root module, one TFC workspace per root, all in the TFC `GNC-SW` project.

## Workflow (see SW-TEAM-AWS-TERRAFORM-DEPLOYMENT-QRG.md for the quick-start)

1. `aws sso login --profile gnc-sw-dev` — SSO only, no static keys, no secrets in code
2. `terraform login` once (TFC token), then in a root dir: `terraform init && terraform plan`
3. Plan before every apply. Do not apply a plan that contains unexplained changes.
4. State is in Terraform Cloud (org MachIndustries, project GNC-SW) — never local, never committed.
5. Keep infrastructure configuration in Terraform. Queue image builds through the existing GitHub workflows below.

## GitHub image builds: three steps

The committed defaults select two CodeBuild-hosted GitHub runners in GovCloud
account `393769260826`, `us-gov-west-1`. The native owner must apply those
settings and verify both webhooks before the jobs can start. Source validation
alone does not establish live runner wiring.

1. Use an existing authorized GitHub account and select an approved monorepo
   ref containing the workflow definitions. The retained workflow source is
   `fix/gnc-codebuild-01a08e1a`, commit
   `3d47094badaa90fb07322a2847b2b892ca88bed0`; it is separate from monorepo main.
   The configured numeric actor cohort is Ted, Shynn and the registered GA
   actor. Repository write permission and the webhook actor filter both apply.

2. Queue the required workflow from that ref. The cloud application and
   optional base image share one job and one cloud runner project.

   ```sh
   gh workflow run rig-mach-unreal-image.yaml --repo machindustries/monorepo \
     --ref fix/gnc-codebuild-01a08e1a -f push=true

   gh workflow run rig-polaris-cloud-image.yaml --repo machindustries/monorepo \
     --ref fix/gnc-codebuild-01a08e1a -f build_base=false -f push=true
   ```

   Set `build_base=true` only when the cloud base also needs rebuilding.
   The workflow itself selects its exact CodeBuild project; no global runner
   label or third base-build project is needed.

3. Inspect the selected workflow's run and logs. Retain its source SHA, result
   and published image digest.

   ```sh
   gh run list --repo machindustries/monorepo \
     --workflow rig-mach-unreal-image.yaml --limit 5
   gh run list --repo machindustries/monorepo \
     --workflow rig-polaris-cloud-image.yaml --limit 5
   gh run view <run-id> --repo machindustries/monorepo --log
   ```

[Unreal runner defaults](aws-gov/dev/polaris-sim/codebuild-ted-smoke.tf) and
[cloud runner defaults](aws-gov/dev/polaris-sim/codebuild-polaris-cloud-runner.tf)
share the native owner's exact Secrets Manager SourceAuth reference. It binds
the operator-authorized existing GA GitHub credential to these two project source configurations;
project scoping does not reduce the credential's underlying GitHub privileges.
Token values never belong in Terraform or repository files.

GitHub mode runs workflow commands and does not support the old ordinary
`aws codebuild start-build` instructions as the daily workflow. The prior
pinned S3 source snapshot `b950ac0852b224e542c70903f85708a720072212` and
[full buildspec](aws-gov/dev/polaris-sim/codebuild/ted-unreal-native.buildspec.yml)
remain available for an owner-managed rollback by disabling the Unreal runner
switch. This does not automatically revert native state or remove webhooks.

The following image is historical evidence from that successful native S3
build, not evidence that either GitHub runner has executed:

Published `linux/amd64` image, verified on 2026-09-14:

```text
393769260826.dkr.ecr.us-gov-west-1.amazonaws.com/mach-industries/mach-unreal@sha256:5b6ebbe56ed41da83f0aa3784141ec9c9d09f99e230c218781b7e117a8a18e74
```

Full cook, package, layout/CLI checks, and ECR push passed. GPU rendering remains
unverified. Deploy by the recorded digest; `latest` is a mutable convenience tag.

## Execution model

State, locking, and RBAC live in Terraform Cloud (org MachIndustries, project
GNC-SW). Execution is LOCAL: TFC remote runners hold no AWS credentials, and the
org wires no VCS integration. TFC cannot start an apply on its own.

Current GitHub CI runs formatting, backend-disabled initialization, and Terraform
validation only. Live Terraform plan/apply is disabled in that workflow; source
validation does not deploy infrastructure. Infrastructure owners use reviewed,
scoped native plans for authorized changes.

Human AWS access uses SSO. CodeBuild uses its existing service role; GitHub
source authentication uses the native owner's accepted Secrets Manager reference.
GitHub workflow secrets supply Epic access in runner mode. The retained native
S3 rollback mode uses version-pinned Epic Secrets Manager references. No
credential value belongs in repository files or Terraform inputs.

## Hygiene (non-negotiable)

- No static AWS credentials anywhere. SSO for humans; OIDC for CI.
- No secrets in `.tf`, tfvars, or committed files.
- IAM names stay inside `mach-gnc-*`; resource names follow the house contract
  (`mi-<workload>-<env>-<region>` / `mach-gnc-<workload>-<function>`).
- `terraform fmt` + `terraform validate` before pushing.
- Stop every dispatched run when it completes: `DELETE /runs/<id>`. An idle half-rig still bills a GPU.

## Document History

| Version | Date | Changes |
| --- | --- | --- |
| 1.1 | 2026-09-14 | Recorded the verified native Unreal image and retained its S3 rollback path; updated the daily flow to the two accepted GitHub runner source configurations and exact actor cohort, distinguished native activation from source validation, and preserved credential privilege/custody boundaries. |
| 1.0 | 2026-09-13 | Updated current access to the provisioned `GNC-SW-Dev-Deploy` daily role and recorded retirement of the prior identity with replacement assignments/access preserved. Historical dated evidence remains unchanged; no infrastructure or credential action is performed by this documentation update. |
