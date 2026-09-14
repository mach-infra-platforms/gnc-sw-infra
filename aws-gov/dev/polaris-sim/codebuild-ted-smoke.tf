# Ted CodeBuild source smoke. Existing role. Default: S3 zip source with no IAM,
# ECR, buckets, or network creation — IAM lives in the access-request IAM config.
#
# Optional fail-closed GitHub hosted-runner mode (default OFF): when
# var.ted_github_runner_enabled is true AND a validated SECRETS_MANAGER source-auth
# secret ARN is provided AND a trusted numeric ACTOR_ACCOUNT_ID cohort is listed, the
# project source switches to https://github.com/machindustries/monorepo and a
# WORKFLOW_JOB_QUEUED webhook is created. Official CodeBuild docs document hosted
# runners across CodeBuild regions, so no separate preactivation Gov feature probe
# is required; native CreateWebhook success and WORKFLOW_JOB_QUEUED queue readback
# establish the actual Gov wiring at activation.

variable "ted_github_runner_enabled" {
  description = "Fail-closed switch for the optional GitHub hosted-runner mode. Default false preserves the existing S3 source smoke binding exactly."
  type        = bool
  default     = false
}

variable "ted_github_source_auth_secret_arn" {
  description = "Existing SECRETS_MANAGER secret ARN for GitHub source auth, provisioned by the native Auth owner. Reference only; never a token value and never a global ImportSourceCredentials."
  type        = string
  default     = ""
}

variable "ted_github_webhook_actor_account_ids" {
  description = "Exact trusted numeric GitHub actor account IDs allowed to queue workflow jobs. Empty keeps the optional mode disabled (fail-closed)."
  type        = list(string)
  default     = []
}

locals {
  ted_project  = "mi-polaris-sim-dev-ore-build-mach-unreal"
  ted_role_arn = "arn:aws-us-gov:iam::393769260826:role/mach-gnc-polaris-sim-codebuild"
  ted_bucket   = "mach-polaris-sim-artifacts"
  ted_key      = "codebuild-source/sha256/fd0fc8cfcdb33506a7fec17ed5d6a9d369110e3b4cdcb1f0397a54d2031c2fc1/source.zip"
  ted_expected = "fd0fc8cfcdb33506a7fec17ed5d6a9d369110e3b4cdcb1f0397a54d2031c2fc1"
}

locals {
  # Enabled-mode GitHub hosted-runner source (fail-closed; see variables above).
  ted_source_type           = var.ted_github_runner_enabled ? "GITHUB" : "S3"
  ted_source_location       = var.ted_github_runner_enabled ? "https://github.com/machindustries/monorepo" : "${local.ted_bucket}/${local.ted_key}"
  ted_workflow_name_pattern = "^Rig — mach-unreal Image [(]linux/amd64[)]$"
}

resource "aws_cloudwatch_log_group" "ted_smoke" {
  name              = "/aws/codebuild/${local.ted_project}"
  retention_in_days = 30

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == "393769260826"
      error_message = "Must create logs only in account 393769260826."
    }
    precondition {
      condition     = data.aws_partition.current.partition == "aws-us-gov"
      error_message = "Must create logs only in aws-us-gov."
    }
    precondition {
      condition     = data.aws_region.ted_smoke.name == "us-gov-west-1"
      error_message = "Must create logs only in us-gov-west-1."
    }
  }
}

resource "aws_codebuild_project" "ted_smoke" {
  name         = local.ted_project
  service_role = local.ted_role_arn
  # Disabled mode preserves the exact preimage values; enabled mode proposes the
  # requester-specified Unreal targets (350-minute bound) pending native
  # capacity/cost/Gov acceptance.
  build_timeout  = var.ted_github_runner_enabled ? 350 : 20
  queued_timeout = 10

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    # Disabled mode preserves the exact preimage compute; enabled mode proposes
    # COMPUTE_TYPE XLARGE with privileged Docker for the Docker-based Unreal build,
    # pending native capacity/cost/Gov acceptance.
    compute_type    = var.ted_github_runner_enabled ? "BUILD_GENERAL1_XLARGE" : "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = var.ted_github_runner_enabled
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.ted_smoke.name
      stream_name = "ted-source-smoke"
    }
  }

  source {
    type      = local.ted_source_type
    location  = local.ted_source_location
    buildspec = local.ted_source_type == "S3" ? file("${path.module}/codebuild/ted-source-smoke.buildspec.yml") : null

    # S3 smoke mode keeps the pinned sha256-addressed buildspec; the object is
    # unversioned (AES256 SSE), so there is no S3 version id to pin or claim
    # immutability against. WORKFLOW_JOB_QUEUED dispatch runs the workflow payload
    # and supplies no inline buildspec.
    dynamic "auth" {
      for_each = var.ted_github_runner_enabled ? [1] : []
      content {
        type     = "SECRETS_MANAGER"
        resource = var.ted_github_source_auth_secret_arn
      }
    }
  }

  tags = {
    Name        = local.ted_project
    Environment = "dev"
    Purpose     = "polaris-sim"
  }

  # Disabled S3 mode uses manual StartBuild and no webhook. Enabled GitHub mode
  # uses the count-gated webhook below. Both modes omit vpc_config, secondary
  # artifacts, secret environment variables, and source_version overrides.

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == "393769260826"
      error_message = "Must plan/apply against account 393769260826."
    }

    precondition {
      condition     = data.aws_partition.current.partition == "aws-us-gov"
      error_message = "Must be GovCloud partition aws-us-gov."
    }

    precondition {
      condition     = data.aws_region.ted_smoke.name == "us-gov-west-1"
      error_message = "Must be region us-gov-west-1."
    }

    precondition {
      condition     = local.ted_role_arn == "arn:aws-us-gov:iam::${data.aws_caller_identity.current.account_id}:role/mach-gnc-polaris-sim-codebuild"
      error_message = "service_role must be the existing mach-gnc-polaris-sim-codebuild role ARN; no IAM is created here."
    }

    precondition {
      condition     = local.ted_key == "codebuild-source/sha256/${local.ted_expected}/source.zip"
      error_message = "Source key must be the pinned sha256-addressed archive path."
    }

    precondition {
      condition     = !var.ted_github_runner_enabled || (can(regex("^arn:aws-us-gov:secretsmanager:us-gov-west-1:393769260826:secret:.+$", var.ted_github_source_auth_secret_arn)) && !can(regex("[*?]", var.ted_github_source_auth_secret_arn)))
      error_message = "GitHub runner mode requires the exact us-gov-west-1/393769260826 SECRETS_MANAGER source-auth ARN from the native Auth owner, with no wildcards; activation is fail-closed."
    }

    precondition {
      condition     = !var.ted_github_runner_enabled || (length(var.ted_github_webhook_actor_account_ids) > 0 && alltrue([for id in var.ted_github_webhook_actor_account_ids : can(regex("^[0-9]+$", id))]))
      error_message = "GitHub runner mode requires a nonempty cohort of numeric GitHub actor account IDs; activation is fail-closed."
    }
  }
}

# Optional WORKFLOW_JOB_QUEUED webhook, created only in enabled mode. Filter
# semantics follow the pinned provider docs; actual Gov wiring is proven by native
# CreateWebhook success and a WORKFLOW_JOB_QUEUED queued-job readback, not by a
# separate speculative capability probe.
resource "aws_codebuild_webhook" "ted_smoke_github" {
  count = var.ted_github_runner_enabled ? 1 : 0

  project_name = aws_codebuild_project.ted_smoke.name
  build_type   = "BUILD"

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "WORKFLOW_JOB_QUEUED"
    }

    filter {
      # Anchored RE2 exact-match alternatives for the trusted actor cohort;
      # comma-joined patterns are EVENT-only and are not used here.
      type    = "ACTOR_ACCOUNT_ID"
      pattern = "^(${join("|", var.ted_github_webhook_actor_account_ids)})$"
    }

    filter {
      # Escaped and anchored exact workflow name (bracket-class literal parens).
      type    = "WORKFLOW_NAME"
      pattern = local.ted_workflow_name_pattern
    }
  }

  lifecycle {
    precondition {
      condition     = can(regex("^arn:aws-us-gov:secretsmanager:us-gov-west-1:393769260826:secret:.+$", var.ted_github_source_auth_secret_arn)) && !can(regex("[*?]", var.ted_github_source_auth_secret_arn))
      error_message = "Webhook requires the exact us-gov-west-1/393769260826 SECRETS_MANAGER source-auth ARN from the native Auth owner, with no wildcards."
    }
  }
}

# Unique-name data source (partition/caller_identity reuse the module's main.tf).
data "aws_region" "ted_smoke" {}

output "ted_smoke_project_name" {
  value = aws_codebuild_project.ted_smoke.name
}

output "ted_smoke_project_arn" {
  value = aws_codebuild_project.ted_smoke.arn
}

output "ted_smoke_log_group" {
  value = aws_cloudwatch_log_group.ted_smoke.name
}
