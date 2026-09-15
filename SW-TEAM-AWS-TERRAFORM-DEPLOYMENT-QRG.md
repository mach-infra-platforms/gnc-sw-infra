# SW Team — AWS Terraform Deployment QRG

Quick-reference guide for GNC SW team members deploying and running workloads in
AWS via Terraform. Worked example: the Polaris/Unreal cloud sim.

Account GC-GNC-SW-Dev `393769260826`, region `us-gov-west-1`.
Access: the `GNC-SW-Dev-Deploy` SSO role (build + deploy + run), provisioned
2026-09-13 (generated role `AWSReservedSSO_GNC-SW-Dev-Deploy_60a7500d99af67b9`).
The prior `Mach-GNC-SW-Dev-Deploy` identity was retired on 2026-09-13.
The operator's normal-profile STS and Kubernetes reads passed after retirement.
Use `GNC-SW-Dev-Deploy` for current access. Console and CLI operations share
that role's scoped permissions; keep infrastructure changes in reviewed source.

## One-time

1. `aws configure sso` →
   start URL `https://start.us-gov-west-1.us-gov-home.awsapps.com/directory/d-98677abeac`,
   account `393769260826`, role `GNC-SW-Dev-Deploy` (provisioned 2026-09-13),
   region `us-gov-west-1`.
   Profile name used below: `gnc-sw-dev`.
2. `aws sso login --profile gnc-sw-dev` (browser auth; rerun when the session expires).
   **No access keys, ever.**
3. Terraform: `terraform login` (one-time TFC token; org `MachIndustries`).

## Ship images (per code change)

Use GitHub CLI signed in with the approved account for `machindustries/monorepo`.
CodeBuild uses `mach-gnc-polaris-sim-codebuild` and resolves the scoped SourceAuth
PAT and Unreal registry credentials from Secrets Manager; no personal credential
copy is needed. See [credential references](README.md#execution-model).

4. Dispatch Unreal on Ted's branch.

   ```sh
   gh workflow run rig-mach-unreal-image.yaml --repo machindustries/monorepo \
     --ref users/tedzaremba/ue-cloud -f push=true
   ```

5. Dispatch the Polaris application and base-image builds on the same branch.

   ```sh
   gh workflow run rig-polaris-cloud-image.yaml --repo machindustries/monorepo \
     --ref users/tedzaremba/ue-cloud -f build_base=true -f push=true
   ```

6. Check both runs and their push results in GitHub Actions before using the images.

   ```sh
   gh run list --repo machindustries/monorepo --branch users/tedzaremba/ue-cloud \
     --event workflow_dispatch --limit 10
   ```

Record the successful runs' published tags and digests. A queued build does not
establish a published image. Native `start-build` is reserved for an
[owner-restored fixed-snapshot rollback](README.md#build-unreal-and-polaris-images).

## Fly a run

The rig also requires the separately supplied `polaris-unreal-receiver` image.

7. Stage inputs to `s3://mach-polaris-sim-artifacts/` (`runs/inputs/*`, `builds/*`, `gis/*`).
8. `POST /runs` (SigV4-signed) to `https://syqe5a1c2e.execute-api.us-gov-west-1.amazonaws.com`
   body: `{"run_config":"s3://…","px4_build":"s3://…","run_id":"<unique, ≤36 chars>"}`
   - First dispatch after idle: ~5–10 min (EC2 GPU cold start + image pull) — expected.
   - `GET /runs/<run_id>` to watch; both nodes place together or the pair is torn down.
9. Results land in `s3://mach-polaris-sim-artifacts/runs/<run_id>/`.
10. **`DELETE /runs/<run_id>` when done** — cluster scales back to zero; a forgotten
    run bills two GPUs.

## Change the infra

State, locking, and RBAC live in Terraform Cloud workspace
`gc-as-gnc-sw-dev-polaris-sim` (MachIndustries, project GNC-SW). Execution is local;
Terraform Cloud holds no AWS credentials. GitHub CI runs formatting and Terraform
validation only. Merging source does not apply infrastructure.

11. Edit under `aws-gov/dev/polaris-sim/`, run `terraform fmt` and
    `terraform validate`, and open a PR.
12. Have the infrastructure owner review a scoped plan with the existing workspace
    inputs before applying through the approved SSO role. Preserve unrelated inputs,
    including bucket ownership settings.
13. Stop on unexplained changes or IAM denials and contact platform engineering.
    A boundary denial marks the edge of the deploy sandbox.

## Egress reality check (default-deny; these are the ONLY holes)

| destination | purpose |
|---|---|
| `172.23.5.51:443` | Google 3D tiles (in-VPC) |
| S3 gateway endpoint | artifacts, staged imagery, image layers |
| ECR + CloudWatch Logs endpoints | pull + logs |
| `10.73.106.0/24` | HQ Jetsons (bidi, all protocols for now) |

Anything expecting internet at runtime will hang. Stage what the run needs.

## Document History

| Version | Date | Changes |
| --- | --- | --- |
| 1.1 | 2026-09-14 | Added the two GitHub image-build dispatches and completion checks, identified the native path as rollback only, and corrected the validation-only CI and scoped infrastructure change steps. |
| 1.0 | 2026-09-13 | Updated current access to the provisioned `GNC-SW-Dev-Deploy` daily role and recorded retirement of the prior identity with replacement assignments/access preserved. Historical dated evidence remains unchanged; no infrastructure or credential action is performed by this documentation update. |
