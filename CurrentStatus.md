# AWS Media Pipeline GitHub Actions CI/CD Detailed Explanation

## 1. Purpose of the CI/CD Upgrade

The project originally worked through a manual flow: Terraform was executed from Windows, AWS Media Services were provisioned, a PowerShell script generated `.env`, the file was copied to EC2, and services were restarted manually.

That worked, but it created operational problems:

- The deployment depended on one local machine.
- Terraform state was local and could be lost between GitHub runners.
- Long-lived AWS access keys would have been risky in GitHub.
- Runtime deployment still required manual EC2 access.
- Cleanup was easy to forget, which could increase AWS cost.

The current GitHub Actions design turns the project into a controlled CI/CD workflow.

---

## 2. Current High-Level Flow

```text
Code push
  -> Terraform CI
  -> Manual Terraform Apply
  -> AWS OIDC assumes IAM role
  -> Terraform provisions MediaConnect / MediaLive / MediaPackage
  -> Terraform state is stored in S3
  -> Manual Deploy Runtime
  -> Terraform outputs generate runtime.env
  -> AWS SSM updates EC2 .env
  -> metrics-api restarts
  -> operator generates JWT token
  -> operator starts FFmpeg
  -> stream flows through AWS Media Services
  -> HLS/DASH playback
```

The project now has three clear layers:

1. **Infrastructure layer**: Terraform, AWS MediaConnect, MediaLive, MediaPackage, IAM, CloudFormation endpoint stacks.
2. **Runtime layer**: EC2, Docker Compose, FastAPI, FFmpeg, Prometheus, Grafana, `.env`, JWT/RBAC.
3. **Automation layer**: GitHub Actions, OIDC, IAM role, S3 remote backend, AWS SSM.

---

## 3. Main Workflow Files

```text
.github/workflows/
├── terraform.yml
├── terraform-apply.yml
├── terraform-destroy.yml
└── deploy-runtime.yml
```

Each file has a separate purpose. This separation is important because validation, provisioning, destruction, and runtime configuration should not be mixed into one workflow.

---

## 4. `terraform.yml` — Terraform CI

### Purpose

`terraform.yml` validates Terraform code without changing AWS resources.

### Typical Steps

1. Checkout repository.
2. Configure Terraform.
3. Run `terraform fmt`.
4. Run `terraform init`.
5. Run `terraform validate`.
6. Run `terraform plan`.

### Why It Exists

It catches problems before AWS resources are created or changed:

- Formatting issues.
- Invalid Terraform syntax.
- Provider initialization problems.
- Missing variables.
- Plan-time errors.

### Why It Does Not Apply

A push to GitHub should not automatically create paid AWS media resources. MediaLive, MediaConnect, EC2, CloudWatch, MediaPackage, and data transfer can all create cost, so apply remains manual.

---

## 5. `terraform-apply.yml` — Manual Infrastructure Apply

### Purpose

`terraform-apply.yml` creates or updates AWS Media Services infrastructure.

### Typical Steps

1. Checkout repository.
2. Configure AWS credentials through GitHub OIDC.
3. Install/setup Terraform.
4. Run `terraform init`.
5. Run `terraform plan`.
6. Run `terraform apply -auto-approve`.

### AWS Resources Involved

This workflow provisions or updates:

- AWS MediaConnect SRT listener flow.
- AWS MediaLive input.
- AWS MediaLive channel.
- AWS MediaPackage v1 channel.
- HLS and DASH origin endpoints.
- CloudFormation-managed endpoint stacks, where needed.
- IAM role references and permissions required by MediaLive.
- Terraform outputs used later by runtime deployment.

### Why It Is Manual

Manual apply prevents accidental cost and avoids changing live media infrastructure on every push.

---

## 6. `terraform-destroy.yml` — Manual Infrastructure Destroy

### Purpose

`terraform-destroy.yml` removes AWS infrastructure after testing.

### Initial Problem

Destroy originally failed because GitHub-hosted runners are ephemeral. A runner starts fresh, runs the workflow, and disappears. If Terraform state is only local to that runner, the next runner does not know what resources were created.

### Fix

The project added an S3 remote backend.

The S3 bucket used for state was:

```text
ihsan-aws-live-streaming-tfstate
```

After this, apply and destroy could share the same state.

### Typical Steps

1. Checkout repository.
2. Configure AWS credentials through OIDC.
3. Run `terraform init`.
4. Read state from S3.
5. Run `terraform destroy -auto-approve`.

### Why It Is Manual

Destroy removes infrastructure. It should never happen automatically unless the project later adds a very controlled environment approval process.

---

## 7. `deploy-runtime.yml` — Runtime Deployment

### Purpose

`deploy-runtime.yml` updates the EC2 runtime environment after Terraform has created the media pipeline.

It does not create MediaConnect, MediaLive, or MediaPackage resources. It updates the running EC2 app configuration.

### What It Updates

The workflow updates runtime values such as:

```text
SRT_TARGET_IP
SRT_TARGET_PORT
HLS_URL
DASH_URL
JWT_SECRET
```

These values are used by:

- FFmpeg start script.
- FastAPI dashboard.
- JWT authentication.
- HLS/DASH dashboard links.
- Prometheus/Grafana monitoring.

### Typical Steps

1. Checkout repository.
2. Configure AWS credentials through OIDC.
3. Run `terraform init`.
4. Read Terraform outputs.
5. Generate a temporary runtime `.env`.
6. Find EC2 using tag variables.
7. Use AWS Systems Manager Run Command.
8. Write `.env` on EC2.
9. Restart `metrics-api`.
10. Leave FFmpeg stopped until the operator starts it.

### Why SSM Was Used Instead of SSH

SSM avoids storing a `.pem` key in GitHub. It uses AWS IAM instead of SSH keys.

Benefits:

- No private SSH key in GitHub secrets.
- No need for SSH automation.
- Commands are sent through AWS APIs.
- Access can be controlled through IAM.
- EC2 can be managed without opening extra access paths.

---

## 8. GitHub OIDC Authentication

### Problem With AWS Access Keys

A simple method would be to store these in GitHub secrets:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
```

That works, but it creates long-lived credentials. If leaked, they remain valid until rotated or deleted.

### Current Method

The project uses GitHub OIDC with an AWS IAM role:

```text
GitHubActionsTerraformMediaServicesRole
```

The flow is:

```text
GitHub Actions job
  -> requests OIDC token
  -> AWS verifies GitHub identity provider
  -> AWS allows role assumption
  -> job receives temporary AWS credentials
```

### Required Workflow Permission

```yaml
permissions:
  id-token: write
  contents: read
```

`id-token: write` allows GitHub Actions to request the OIDC token.  
`contents: read` allows the workflow to check out repository code.

### Why This Is Better

- No permanent AWS keys in GitHub.
- Credentials are short-lived.
- AWS can restrict access by repository.
- AWS can restrict access by branch or environment.
- Permissions can later be reduced to least privilege.

---

## 9. AWS IAM Role

### Role Responsibility

The GitHub Actions IAM role gives workflows permission to interact with AWS.

It may need access to:

```text
mediaconnect
medialive
mediapackage
cloudformation
iam
s3
ssm
ec2
logs
cloudwatch
```

### Current Practical Use

During development, broader permissions may be used to avoid blocking progress. For production, this should be reduced.

### Future Least-Privilege Direction

1. Keep the pipeline working.
2. Review exact AWS actions used.
3. Replace broad permissions with scoped policies.
4. Restrict S3 access to the Terraform state bucket.
5. Restrict SSM access to the target EC2 instance.
6. Restrict OIDC trust to the correct GitHub repository and branch.

---

## 10. S3 Remote Terraform State

### Why State Matters

Terraform state records:

- Resource IDs.
- Resource relationships.
- Current deployed configuration.
- Outputs needed by other workflows.

Without shared state, one GitHub runner cannot safely destroy infrastructure created by another runner.

### Result of Adding S3 State

- Apply and destroy use the same state.
- Runtime deploy can read Terraform outputs.
- State survives after GitHub runners disappear.
- The workflow becomes closer to real-world DevOps practice.

---

## 11. GitHub Variables and Secrets

### Variables

GitHub variables store non-sensitive configuration:

```text
AWS_REGION
FLOW_NAME
SRT_PORT
EC2_TARGET_TAG_NAME
EC2_APP_DIR
```

### Secrets

GitHub secrets store sensitive configuration:

```text
RUNTIME_JWT_SECRET
```

### Why They Are Separate

Variables are safe configuration values. Secrets should be hidden and never committed to the repository.

---

## 12. Runtime JWT Secret

### Purpose

`RUNTIME_JWT_SECRET` signs and validates JWT tokens for the FastAPI control API.

This protects sensitive operations such as:

- Start FFmpeg.
- Stop FFmpeg.
- View protected status/control functions.

### Operational Rule

When the JWT secret changes:

1. Run `deploy-runtime.yml`.
2. The EC2 `.env` is updated.
3. `metrics-api` restarts.
4. Old JWT tokens stop working.
5. Generate a fresh JWT token.

---

## 13. AWS Systems Manager Dependency

`deploy-runtime.yml` depends on SSM.

The EC2 instance must have:

- SSM agent installed and running.
- IAM instance profile with SSM permissions.
- Network path to SSM endpoints.
- Correct EC2 tag for discovery.
- Runtime app directory already present.

The GitHub Actions IAM role must also be allowed to:

- Describe EC2 instances.
- Send SSM commands.
- Read command results if needed.

---

## 14. Cost Management

The main cost-sensitive items are:

- MediaLive channel.
- MediaConnect flow.
- EC2 instance.
- CloudWatch metrics and logs.
- MediaPackage origin traffic.
- Data transfer.

Current cost-safe design choices:

- Apply is manual.
- Destroy is manual.
- Runtime deploy does not start FFmpeg automatically.
- EC2 can be stopped when not needed.
- Media Services can be destroyed after test windows.

Recommended routine:

```text
1. Apply infrastructure only when needed.
2. Deploy runtime.
3. Start FFmpeg only for testing.
4. Stop FFmpeg after testing.
5. Stop EC2 if preserving dashboards.
6. Destroy Media Services if not needed.
7. Check AWS Billing / Cost Explorer.
```

---

## 15. Why Runtime Depends on Terraform Outputs

The EC2 runtime cannot hardcode values such as:

- MediaConnect listener IP.
- MediaConnect listener port.
- HLS endpoint URL.
- DASH endpoint URL.

Terraform creates these values. Therefore, Terraform outputs are the source of truth. `deploy-runtime.yml` reads them and writes the EC2 `.env`.

---

## 16. Why Infrastructure and Runtime Are Separate

Infrastructure changes less often. Runtime configuration can change more often.

Infrastructure includes:

- MediaConnect.
- MediaLive.
- MediaPackage.
- IAM.
- Terraform state.

Runtime includes:

- `.env`.
- JWT secret.
- FFmpeg target.
- HLS/DASH links.
- FastAPI restart.

Separating them avoids unnecessary Terraform changes when only the EC2 runtime needs updating.

---

## 17. How the GitHub Actions Part Evolved

### Stage 1 — Manual Terraform

Terraform was first run from the Windows laptop.

### Stage 2 — Terraform CI

`terraform.yml` was added for validation.

### Stage 3 — OIDC Authentication

GitHub Actions was connected to AWS without access keys.

### Stage 4 — Manual Apply

`terraform-apply.yml` was added to create/update infrastructure.

### Stage 5 — Manual Destroy

`terraform-destroy.yml` was added for cleanup.

### Stage 6 — S3 Remote State

Destroy failed without shared state, so S3 backend was added.

### Stage 7 — Runtime Deployment

`deploy-runtime.yml` was added to read Terraform outputs and update EC2 through SSM.

---

## 18. Current Standing

The project now demonstrates:

- AWS Media Services with Terraform.
- GitHub Actions validation.
- Manual infrastructure apply.
- Manual infrastructure destroy.
- OIDC-based AWS authentication.
- S3 remote Terraform state.
- Runtime deployment through AWS SSM.
- EC2 FFmpeg source control.
- FastAPI dashboard with JWT/RBAC.
- Prometheus and Grafana observability.
- CloudWatch metrics integration.
- HLS/DASH playback.

---

## 19. Future Enhancements

Recommended next improvements:

- Add GitHub Actions summaries.
- Upload Terraform plan as an artifact.
- Add GitHub environment approval gates.
- Add separate dev/prod environments.
- Replace broad IAM permissions with least privilege.
- Add Grafana dashboard provisioning.
- Add CloudWatch alarm documentation.
- Add deployment notifications.
- Add cost cleanup reminders.
- Add a short runbook to the README.

---

## 20. Final Summary

The GitHub Actions work evolved the project from a manual AWS media lab into a more realistic DevOps-style pipeline.

The most important improvements were:

- secure AWS authentication using OIDC,
- remote Terraform state in S3,
- separate apply and destroy workflows,
- runtime deployment through SSM,
- and separation between infrastructure and runtime configuration.

This makes the project easier to operate, easier to explain to a client, safer from a security point of view, and better aligned with real-world DevOps practices.
