# CI/CD with GitHub Actions

## Project Status

### Repository

**Working CI/CD Repository**

``` text
C:\Users\ihsan\Desktop\terraform-aws-mediaservices
```

**Original Working Backup**

``` text
C:\Users\ihsan\Desktop\terraform-mediaconnect-lab
```

------------------------------------------------------------------------

# What Was Completed

## 1. GitHub Actions CI

Created:

``` text
.github/workflows/terraform.yml
```

Runs automatically on:

-   Push
-   Pull Request
-   Manual Dispatch

Pipeline:

1.  Terraform fmt
2.  Terraform init
3.  Terraform validate
4.  Terraform plan

No infrastructure changes are made.

------------------------------------------------------------------------

## 2. Secure AWS Authentication

Configured GitHub Actions authentication using **AWS OIDC**.

Created IAM Role:

``` text
GitHubActionsTerraformMediaServicesRole
```

Benefits:

-   No AWS Access Keys stored in GitHub
-   Temporary credentials
-   Secure authentication

------------------------------------------------------------------------

## 3. Manual Terraform Apply

Created:

``` text
.github/workflows/terraform-apply.yml
```

Triggered manually from GitHub Actions.

Workflow:

1.  Authenticate with AWS OIDC
2.  Terraform Init
3.  Terraform Validate
4.  Terraform Apply
5.  Display Terraform Outputs

Successfully provisioned:

-   AWS MediaConnect
-   AWS MediaLive
-   AWS MediaPackage
-   HLS Endpoint
-   DASH Endpoint

------------------------------------------------------------------------

## 4. Manual Terraform Destroy

Created:

``` text
.github/workflows/terraform-destroy.yml
```

Authentication succeeded.

Destroy executed successfully but reported:

``` text
No changes. No objects need to be destroyed.
```

### Reason

GitHub-hosted runners are ephemeral.

Terraform state existed only during the Apply workflow.

After the runner finished, the local Terraform state disappeared.

Destroy therefore had no state to reference.

------------------------------------------------------------------------

# Important Lesson Learned

GitHub Actions requires **remote Terraform state**.

Without a remote backend:

``` text
Terraform Apply
        ↓
Temporary GitHub Runner
        ↓
Local terraform.tfstate deleted
        ↓
Terraform Destroy cannot find resources
```

------------------------------------------------------------------------

# AWS Configuration Completed

## IAM

Created:

-   GitHub OIDC Provider
-   GitHubActionsTerraformMediaServicesRole

Configured:

-   aws-actions/configure-aws-credentials

------------------------------------------------------------------------

## EC2

Created IAM Role:

``` text
EC2SSMManagedInstanceRole
```

Attached policies:

-   AmazonSSMManagedInstanceCore
-   CloudWatch permissions for Grafana

Grafana CloudWatch dashboards were restored successfully.

------------------------------------------------------------------------

# Security Decisions

Implemented:

-   AWS OIDC authentication
-   Manual Apply
-   Manual Destroy
-   AWS Systems Manager (planned)
-   No AWS Access Keys in GitHub
-   No EC2 .pem stored in GitHub

Avoided:

-   Automatic Apply on Push
-   Automatic Destroy
-   Manual AWS credentials

------------------------------------------------------------------------

# Current CI/CD Architecture

``` text
Developer
    │
    ▼
Git Push
    │
    ▼
GitHub Actions CI
    │
    ├── terraform fmt
    ├── terraform validate
    └── terraform plan

Manual Approval

    ▼

GitHub Actions Apply
    │
    ▼
Terraform Apply
    │
    ▼
AWS Media Services Provisioned
```

------------------------------------------------------------------------

# Current Limitation

Terraform state is not yet stored remotely.

Therefore:

-   Apply works
-   Destroy cannot manage previously created infrastructure

------------------------------------------------------------------------

# Next Session

Continue with:

## Configure Terraform Remote State

Tasks:

1.  Create Amazon S3 backend
2.  Configure backend.tf
3.  Migrate Terraform state
4.  Verify Apply
5.  Verify Destroy

After remote state is working:

-   Read Terraform outputs
-   Use AWS Systems Manager (SSM)
-   Automatically update EC2 `.env`
-   Restart application services if required

------------------------------------------------------------------------

# Long-Term Goal

``` text
Git Push
      │
      ▼
GitHub Actions CI
      │
      ▼
Manual Apply
      │
      ▼
Terraform Apply
      │
      ▼
Terraform State (Amazon S3)
      │
      ▼
Terraform Outputs
      │
      ▼
AWS Systems Manager
      │
      ▼
Update EC2 .env
      │
      ▼
Restart Services
      │
      ▼
Streaming Ready
```
