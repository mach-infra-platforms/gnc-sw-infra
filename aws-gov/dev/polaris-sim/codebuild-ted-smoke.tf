# Ted CodeBuild source smoke. S3 zip source, existing role. No IAM, ECR, buckets,
# network, or webhook creation here — IAM lives in the access-request IAM config.

locals {
  ted_project  = "mi-polaris-sim-dev-ore-build-mach-unreal"
  ted_role_arn = "arn:aws-us-gov:iam::393769260826:role/mach-gnc-polaris-sim-codebuild"
  ted_bucket   = "mach-polaris-sim-artifacts"
  ted_key      = "codebuild-source/sha256/fd0fc8cfcdb33506a7fec17ed5d6a9d369110e3b4cdcb1f0397a54d2031c2fc1/source.zip"
  ted_expected = "fd0fc8cfcdb33506a7fec17ed5d6a9d369110e3b4cdcb1f0397a54d2031c2fc1"
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
  name           = local.ted_project
  service_role   = local.ted_role_arn
  build_timeout  = 20
  queued_timeout = 10

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = false
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.ted_smoke.name
      stream_name = "ted-source-smoke"
    }
  }

  source {
    type      = "S3"
    location  = "${local.ted_bucket}/${local.ted_key}"
    buildspec = file("${path.module}/codebuild/ted-source-smoke.buildspec.yml")

    # source_version intentionally omitted: the object is unversioned (AES256 SSE),
    # so there is no S3 version id to pin or claim immutability against.
  }

  tags = {
    Name        = local.ted_project
    Environment = "dev"
    Purpose     = "polaris-sim"
  }

  # Manual StartBuild only: no vpc_config, no secondary artifacts, no webhook,
  # no secret environment variables, no source_version override.

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
