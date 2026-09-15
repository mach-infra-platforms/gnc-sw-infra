# Active CodeBuild-hosted runner for the existing Rig polaris-cloud workflow.
# The application and optional base image share one job and the existing role.
# SourceAuth and actors reuse the accepted inputs in codebuild-ted-smoke.tf.

variable "polaris_cloud_github_runner_enabled" {
  description = "Retain the activated Rig polaris-cloud GitHub runner lane. Independent of the Unreal runner switch."
  type        = bool
  default     = true
}

locals {
  polaris_cloud_runner_project = "mi-polaris-sim-dev-ore-build-polaris-cloud"
  polaris_cloud_workflow_name  = "^Rig — polaris-cloud Image [(]linux/amd64[)]$"
}

resource "aws_cloudwatch_log_group" "polaris_cloud_runner" {
  count = var.polaris_cloud_github_runner_enabled ? 1 : 0

  name              = "/aws/codebuild/${local.polaris_cloud_runner_project}"
  retention_in_days = 30
}

resource "aws_codebuild_project" "polaris_cloud_runner" {
  count = var.polaris_cloud_github_runner_enabled ? 1 : 0

  name                   = local.polaris_cloud_runner_project
  description            = "Polaris cloud/base GitHub Actions runner in GNC GovCloud; source auth via approved scoped workload secret."
  service_role           = local.ted_role_arn
  build_timeout          = 180
  queued_timeout         = 60
  concurrent_build_limit = 1

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_XLARGE"
    image                       = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true
    image_pull_credentials_type = "CODEBUILD"
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.polaris_cloud_runner[0].name
    }
  }

  source {
    type            = "GITHUB"
    location        = "https://github.com/machindustries/monorepo.git"
    git_clone_depth = 1
    # The GitHub job supplies commands; there is no native S3/inline buildspec.
    auth {
      type     = "SECRETS_MANAGER"
      resource = var.ted_github_source_auth_secret_arn
    }
  }

  lifecycle {
    precondition {
      condition = (
        data.aws_caller_identity.current.account_id == "393769260826" &&
        data.aws_partition.current.partition == "aws-us-gov" &&
        data.aws_region.ted_smoke.name == "us-gov-west-1"
      )
      error_message = "The cloud runner is restricted to GovCloud account 393769260826 in us-gov-west-1."
    }
    precondition {
      condition = (
        can(regex("^arn:aws-us-gov:secretsmanager:us-gov-west-1:393769260826:secret:.+$", var.ted_github_source_auth_secret_arn)) &&
        !can(regex("[*?]", var.ted_github_source_auth_secret_arn))
      )
      error_message = "The cloud runner requires the accepted exact Gov393 SourceAuth secret ARN, without wildcards."
    }
    precondition {
      condition = (
        length(var.ted_github_webhook_actor_account_ids) > 0 &&
        alltrue([for id in var.ted_github_webhook_actor_account_ids : can(regex("^[0-9]+$", id))])
      )
      error_message = "The cloud runner requires an accepted nonempty cohort of numeric GitHub actor IDs."
    }
  }
}

resource "aws_codebuild_webhook" "polaris_cloud_runner" {
  count = var.polaris_cloud_github_runner_enabled ? 1 : 0

  project_name = aws_codebuild_project.polaris_cloud_runner[0].name
  build_type   = "BUILD"

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "WORKFLOW_JOB_QUEUED"
    }
    filter {
      type    = "ACTOR_ACCOUNT_ID"
      pattern = "^(${join("|", var.ted_github_webhook_actor_account_ids)})$"
    }
    filter {
      type    = "WORKFLOW_NAME"
      pattern = local.polaris_cloud_workflow_name
    }
  }
}

output "polaris_cloud_runner_project_name" {
  value = var.polaris_cloud_github_runner_enabled ? aws_codebuild_project.polaris_cloud_runner[0].name : null
}
