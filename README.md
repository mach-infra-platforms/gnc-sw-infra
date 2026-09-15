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

## Infrastructure changes

See the [deployment quick reference](SW-TEAM-AWS-TERRAFORM-DEPLOYMENT-QRG.md) for setup and rig operations.

1. `aws sso login --profile gnc-sw-dev` — SSO only, no static keys, no secrets in code
2. Run `terraform login` once for Terraform Cloud, then `terraform init` in the intended root.
3. Review a scoped plan with the existing workspace inputs before applying. Stop on unexplained changes.
4. State is in Terraform Cloud (org MachIndustries, project GNC-SW) — never local, never committed.
5. Build images through the GitHub workflows below. Infrastructure owners use reviewed plans with the existing workspace inputs.

## Build Unreal and Polaris images

Prerequisite: GitHub CLI (`gh`) signed in with the approved GitHub account for
`machindustries/monorepo`. Both workflows build the selected Ted branch revision
on the existing GovCloud CodeBuild runners.

1. Dispatch the Unreal build and ECR publication.

   ```sh
   gh workflow run rig-mach-unreal-image.yaml --repo machindustries/monorepo \
     --ref users/tedzaremba/ue-cloud -f push=true
   ```

2. Dispatch the Polaris application and base-image builds with ECR publication.

   ```sh
   gh workflow run rig-polaris-cloud-image.yaml --repo machindustries/monorepo \
     --ref users/tedzaremba/ue-cloud -f build_base=true -f push=true
   ```

3. Open the returned Actions run URLs to check build and push results, or list recent dispatches.

   ```sh
   gh run list --repo machindustries/monorepo --branch users/tedzaremba/ue-cloud \
     --event workflow_dispatch --limit 10
   ```

A successful dispatch only queues work. Confirm both runs succeed and record the
published image tags and digests before deployment. GPU rendering requires a
separate rig check. The rig also requires the separately supplied
`polaris-unreal-receiver` image.

The [Unreal project](aws-gov/dev/polaris-sim/codebuild-ted-smoke.tf) retains a
native S3 rollback that platform engineering can restore with a reviewed, scoped
change. Only after restoring that mode can `aws codebuild start-build` run the
fixed `b950ac0852b224e542c70903f85708a720072212` snapshot with the
[native buildspec](aws-gov/dev/polaris-sim/codebuild/ted-unreal-native.buildspec.yml).

## Execution model

State, locking, and RBAC live in Terraform Cloud (org MachIndustries, project
GNC-SW). Execution is LOCAL: TFC remote runners hold no AWS credentials, and the
org wires no VCS integration. TFC cannot start an apply on its own.

Current GitHub CI runs formatting, backend-disabled initialization, and Terraform
validation only. Live Terraform plan/apply is disabled in that workflow; source
validation does not deploy infrastructure. Infrastructure owners use reviewed,
scoped native plans for authorized changes.

Human AWS access uses the `GNC-SW-Dev-Deploy` SSO role. Both runners use the
existing `mach-gnc-polaris-sim-codebuild` service role. CodeBuild resolves its
scoped GitHub SourceAuth PAT from Secrets Manager reference
`mi-polaris-sim/github-pat-UCrebm`; Unreal also receives the existing
`mi-polaris-sim/epic-ghcr-5QsAFr` username and token fields. Repository checkout
uses the job's `GITHUB_TOKEN`. Operators do not copy personal credentials into
build settings, repository secrets, or Terraform inputs.

## Hygiene (non-negotiable)

- No static AWS credentials. Use SSO for human AWS access and the existing service role for CodeBuild.
- No secrets in `.tf`, tfvars, or committed files.
- IAM names stay inside `mach-gnc-*`; resource names follow the house contract
  (`mi-<workload>-<env>-<region>` / `mach-gnc-<workload>-<function>`).
- `terraform fmt` + `terraform validate` before pushing.
- Stop every dispatched run when it completes: `DELETE /runs/<id>`. An idle half-rig still bills a GPU.

## Document History

| Version | Date | Changes |
| --- | --- | --- |
| 1.1 | 2026-09-14 | Documented the two GitHub image-build dispatches, completion checks, service-role and Secrets Manager usage, retained the fixed-snapshot native path as rollback only, and clarified validation-only Terraform CI. |
| 1.0 | 2026-09-13 | Updated current access to the provisioned `GNC-SW-Dev-Deploy` daily role and recorded retirement of the prior identity with replacement assignments/access preserved. Historical dated evidence remains unchanged; no infrastructure or credential action is performed by this documentation update. |
