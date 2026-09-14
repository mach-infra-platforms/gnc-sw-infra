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
5. Keep infrastructure configuration in Terraform. Start the existing build project with the native flow below.

## Native Unreal build: three steps

Prerequisite: an existing `gnc-sw-dev` AWS profile for GovCloud account
`393769260826` with the `GNC-SW-Dev-Deploy` role.

1. Sign in with the existing profile.

   ```sh
   aws sso login --profile gnc-sw-dev
   ```

2. Start the configured project and retain its build ID. No overrides are needed.

   ```sh
   BUILD_ID=$(aws codebuild start-build --profile gnc-sw-dev --region us-gov-west-1 \
     --project-name mi-polaris-sim-dev-ore-build-mach-unreal --query build.id --output text)
   ```

3. Check the result and open the returned log link. Repeat this read until the build completes.

   ```sh
   aws codebuild batch-get-builds --profile gnc-sw-dev --region us-gov-west-1 \
     --ids "$BUILD_ID" --query 'builds[0].{status:buildStatus,phase:currentPhase,logs:logs.deepLink}'
   ```

The [project defaults](aws-gov/dev/polaris-sim/codebuild-ted-smoke.tf) use the
fixed `b950ac0852b224e542c70903f85708a720072212` source snapshot and
[full buildspec](aws-gov/dev/polaris-sim/codebuild/ted-unreal-native.buildspec.yml).
This rebuilds that snapshot; it does not fetch the latest monorepo commit.
The native AWS route is active. The optional GitHub runner/webhook remains unwired.

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

Human AWS access uses SSO. CodeBuild uses its existing service role and resolves
version-pinned Epic credential references through Secrets Manager. No credential
value belongs in repository files or Terraform inputs.

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
| 1.1 | 2026-09-14 | Added the verified native Unreal self-service steps and image digest, distinguished the fixed source snapshot from the unwired GitHub runner, and corrected the current validation-only CI description. |
| 1.0 | 2026-09-13 | Updated current access to the provisioned `GNC-SW-Dev-Deploy` daily role and recorded retirement of the prior identity with replacement assignments/access preserved. Historical dated evidence remains unchanged; no infrastructure or credential action is performed by this documentation update. |
