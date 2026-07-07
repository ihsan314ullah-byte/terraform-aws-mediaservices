# AWS Media Pipeline -- CI/CD Evolution Notes

## Overview

This document summarizes the work completed over the last 3--4 days to
evolve the project from a manually operated Terraform deployment into a
secure CI/CD pipeline.

## Starting Point

Originally:

1.  Terraform was executed manually from Windows.
2.  AWS MediaConnect, MediaLive and MediaPackage were provisioned.
3.  A PowerShell script generated `.env`.
4.  `.env` was copied manually to EC2.
5.  Services were restarted manually.

This worked but required significant manual effort.

## What Was Implemented

### 1. GitHub Actions CI

Created `terraform.yml`.

Functions: - terraform fmt - terraform init - terraform validate -
terraform plan

Purpose: Continuous validation without modifying AWS resources.

Status: Complete.

### 2. Secure AWS Authentication

Implemented AWS OIDC with IAM role
`GitHubActionsTerraformMediaServicesRole`.

Purpose: Remove AWS Access Keys from GitHub.

Status: Complete.

### 3. Terraform Apply

Created `terraform-apply.yml`.

Purpose: Provision AWS Media Services manually through GitHub Actions.

Status: Complete.

### 4. Terraform Destroy

Created `terraform-destroy.yml`.

Purpose: Safely remove infrastructure after testing.

Initial problem: Destroy failed because GitHub runners are ephemeral and
local Terraform state was lost.

### 5. Amazon S3 Remote State

Created S3 bucket:

`ihsan-aws-live-streaming-tfstate`

Added `backend.tf`.

Purpose: Share Terraform state between Apply and Destroy.

Status: Complete.

### 6. GitHub Variables

Added:

-   AWS_REGION
-   FLOW_NAME
-   SRT_PORT
-   EC2_TARGET_TAG_NAME
-   EC2_APP_DIR

Purpose: Remove hardcoded configuration.

Status: Complete.

### 7. Runtime Deployment

Created `deploy-runtime.yml`.

Purpose:

-   Read Terraform outputs
-   Generate runtime.env
-   Connect through AWS Systems Manager
-   Update EC2 `.env`
-   Restart metrics-api

No SSH automation or `.pem` key is required.

Status: Complete.

### 8. JWT Runtime Secret

Added GitHub Secret:

`RUNTIME_JWT_SECRET`

The runtime workflow updates EC2 with the current secret.

Fresh JWT tokens must be generated whenever the secret changes.

## Current Deployment Flow

Git Push -> Terraform CI -> Manual Terraform Apply -> Terraform State stored in Amazon S3 
-> Manual Deploy Runtime -> AWS Systems Manager -> EC2 `.env` updated -> metrics-api restarted
-> Generate JWT Token -> Start FFmpeg -> MediaConnect -> MediaLive -> MediaPackage -> HLS / DASH Playback

## Current Project Status

Infrastructure: - Terraform - MediaConnect - MediaLive - MediaPackage

CI/CD: - GitHub Actions - AWS OIDC - Amazon S3 backend

Application: - FastAPI - FFmpeg - JWT - RBAC

Observability: - Prometheus - Grafana - CloudWatch

Runtime: - AWS Systems Manager deployment

Overall: End-to-end deployment is operational.

## Lessons Learned

-   GitHub-hosted runners are ephemeral.
-   Remote Terraform state is required.
-   OIDC is safer than AWS access keys.
-   Runtime deployment should be separated from infrastructure
    deployment.
-   Systems Manager eliminates the need for SSH automation.

## Future Enhancements

-   Improve documentation and architecture diagrams.
-   Publish Terraform plans as GitHub artifacts.
-   Add GitHub Action summaries.
-   Improve workflow error handling.
-   Introduce development/production environments.
-   Replace AdministratorAccess with least-privilege IAM policies.
-   Add deployment notifications and additional monitoring.

## Conclusion

The project now demonstrates:

-   Infrastructure as Code
-   Secure CI/CD
-   Remote Terraform state
-   Automated runtime configuration
-   Secure AWS authentication
-   Modern observability
