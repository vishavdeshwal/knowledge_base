# SAM Terraform Drift Sync Playbook

**Project:** SAMMMM (SAM)
**Applies to:** preprod (next), prod (future)
**Completed on:** staging (July 2026)
**Author:** Vishav + Claude

---

## Background

The SAM staging terraform was written with a monolithic `module "ecs_fargate"` that created one cluster + one ECS service (webhook). Over time, the actual AWS infra diverged significantly:

- Webhook service was retired; replaced by webapi / webchat / dashboard / pdf / scan services
- 4 new SQS queues added (render, render-dlq, scan, scan-dlq)
- 5 new Secrets Manager secrets added
- ALB grew: path-based routing (priority 5 + 10), port 8443 listener for dashboard
- GOOGLE_API_KEY moved from plaintext env var → Secrets Manager secret

This playbook documents every change made and the exact steps to replicate in preprod.

---

## 1. Pre-Flight: Read Current State

Before touching any files, pull what's actually running in AWS:

```bash
# Confirm profile and account
aws sts get-caller-identity --profile <profile> --region ap-south-1

# List ECS services in the cluster
aws ecs list-services \
  --cluster <env>-SAMMMM-app-sammmm \
  --profile <profile> --region ap-south-1

# List SQS queues
aws sqs list-queues \
  --queue-name-prefix "<env>-SAMMMM-app-" \
  --profile <profile> --region ap-south-1 | jq '.QueueUrls[]'

# List secrets
aws secretsmanager list-secrets \
  --profile <profile> --region ap-south-1 \
  --query "SecretList[?starts_with(Name,'<env>/SAMMMM/')].Name" | jq '.[]'

# List target groups
aws elbv2 describe-target-groups \
  --profile <profile> --region ap-south-1 \
  --query "TargetGroups[?contains(TargetGroupName,'sammmm')].{Name:TargetGroupName,Port:Port,ARN:TargetGroupArn}"

# List ALB listeners
aws elbv2 describe-listeners \
  --load-balancer-arn <alb_arn> \
  --profile <profile> --region ap-south-1
```

---

## 2. All Terraform Changes Made (Staging → Truth)

### 2a. Modules Added to `main.tf`

| Module Name | Source | What It Creates | Key Params |
|---|---|---|---|
| `ecs_cluster` | `modules/aws/ecs_cluster` | ECS cluster only | `cluster_name = "<env>-<project>-app-sammmm"` |
| `webhook_task_exec_role` | `modules/aws/iam_role` | Preserves exec role name | `name = "<env>-<project>-sammmm-webhook-task-exec-role"` |
| `webhook_task_task_role` | `modules/aws/iam_role` | Preserves task role name | `name = "<env>-<project>-sammmm-webhook-task-task-role"` |
| `sqs_render_dlq` | `modules/aws/sqs` | DLQ for render queue | standard |
| `sqs_render` | `modules/aws/sqs` | Render job queue | `visibility_timeout=90`, `max_receive_count=3`, `redrive_policy` to dlq |
| `sqs_scan_dlq` | `modules/aws/sqs` | DLQ for scan queue | standard |
| `sqs_scan` | `modules/aws/sqs` | Scan job queue | `visibility_timeout=90`, `max_receive_count=3`, `redrive_policy` to dlq |
| `target_group_webapi` | `modules/aws/target_group` | TG for webapi | `name_override="stg-sammmm-tg-webapi-8080"`, port 8080 |
| `target_group_webchat` | `modules/aws/target_group` | TG for webchat | `name_override="stg-sammmm-tg-webchat-8080"`, port 8080 |
| `target_group_dashboard` | `modules/aws/target_group` | TG for dashboard | `name_override="<env>-SAMMMM-app-tg-dash-8091"`, port 8091 |
| `secret_google_api_key` | `modules/aws/secrets_manager` | Gemini API key | `secret_name = "<env>/SAMMMM/GOOGLE_API_KEY"` |
| `secret_openai_api_key` | `modules/aws/secrets_manager` | OpenAI key | `secret_name = "<env>/SAMMMM/OPENAI_API_KEY"` |
| `secret_deeptag_api_key` | `modules/aws/secrets_manager` | DeepTag key | `secret_name = "<env>/SAMMMM/DEEPTAG_API_KEY"` |
| `secret_email_smtp_password` | `modules/aws/secrets_manager` | SMTP password | `secret_name = "<env>/SAMMMM/EMAIL_SMTP_PASSWORD"` |
| `secret_gupshup_numbers` | `modules/aws/secrets_manager` | Gupshup numbers JSON | `secret_name = "<env>/SAMMMM/GUPSHUP_NUMBERS"` |
| `ecs_webapi` | `modules/aws/ecs_service` | webapi ECS service | cpu=256/512, port=8080, exec=webhook-task-exec-role, task=webhook-task-task-role |
| `ecs_webchat` | `modules/aws/ecs_service` | webchat ECS service | cpu=1024/2048, port=8080, same roles |
| `ecs_dashboard` | `modules/aws/ecs_service` | dashboard ECS service | cpu=256/512, port=8091, same roles |
| `ecs_pdf` | `modules/aws/ecs_service` | pdf worker | cpu=1024/2048, no port, exec=ecs-execution-role, task=flush-role |
| `ecs_scan` | `modules/aws/ecs_service` | scan worker | cpu=512/1024, no port, exec=ecs-execution-role, task=flush-role |

### 2b. Resources Added to `main.tf`

```hcl
# ALB routing — webchat takes priority over webapi for WebSocket paths
resource "aws_lb_listener_rule" "webchat" {
  listener_arn = module.alb.https_listener_arn
  priority     = 5
  action { type = "forward"; target_group_arn = module.target_group_webchat.target_group_arn }
  condition { path_pattern { values = ["/v1/ws/*"] } }
}

resource "aws_lb_listener_rule" "webapi" {
  listener_arn = module.alb.https_listener_arn
  priority     = 10
  action { type = "forward"; target_group_arn = module.target_group_webapi.target_group_arn }
  condition { path_pattern { values = ["/v1/*"] } }
}

# Dashboard listener on port 8443
resource "aws_lb_listener" "dashboard" {
  load_balancer_arn = module.alb.alb_arn
  port              = "8443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = <acm_cert_arn>
  default_action { type = "forward"; target_group_arn = module.target_group_dashboard.target_group_arn }
}
```

### 2c. Modules Removed

- `module "ecs_fargate"` — replaced by `module "ecs_cluster"` + individual `module "ecs_*"` services + explicit IAM role modules.

### 2d. Locals Changes

**Removed from `sam_env_vars`:**
- `{ name = "GOOGLE_API_KEY", value = "..." }` — moved to Secrets Manager
- `{ name = "OPENAI_API_KEY", value = "" }` — moved to Secrets Manager

**Added locals:**

```hcl
# Extended env for webapi/webchat/dashboard (concat of sam_env_vars + these)
sam_webapi_env_vars = concat(local.sam_env_vars, [
  { name = "DEEPTAG_TIMEOUT",            value = "90s" },
  { name = "DEEPTAG_DISABLED",           value = "false" },
  { name = "DEEPTAG_BASE_URL",           value = "https://gserver1.btbp.org/deeptag/AppService.svc" },
  { name = "WEBHOOK_SECRET",             value = var.webhook_secret },
  { name = "MESSAGES_REFRESH_TTL",       value = "5m" },
  { name = "WEBAPI_ALLOWED_ORIGINS",     value = "*" },
  { name = "WEBAPI_COOKIE_SAME_SITE",    value = "none" },
  { name = "COMPLETION_SUMMARY_ENABLED", value = "true" },
  { name = "MIDLINER_THRESHOLDS",        value = "12,18,20" },
  { name = "BIOMETRIC_CONSENT_VERSION",  value = "v1.0" },
])

# Secrets for webapi/webchat/dashboard (4 base + 2 new)
sam_api_secrets = [
  { name = "DATABASE_URL",       valueFrom = module.secret_database_url.secret_arn },
  { name = "GUPSHUP_HMAC_SECRET",valueFrom = module.secret_gupshup_hmac_secret.secret_arn },
  { name = "GUPSHUP_TOKEN",      valueFrom = module.secret_gupshup_token.secret_arn },
  { name = "CLEVERTAP_PASSCODE", valueFrom = module.secret_clevertap_passcode.secret_arn },
  { name = "GOOGLE_API_KEY",     valueFrom = module.secret_google_api_key.secret_arn },
  { name = "DEEPTAG_API_KEY",    valueFrom = module.secret_deeptag_api_key.secret_arn },
]

# Secrets for pdf/scan workers (7 secrets)
sam_worker_v2_secrets = [
  { name = "DATABASE_URL",       valueFrom = module.secret_database_url.secret_arn },
  { name = "CLEVERTAP_PASSCODE", valueFrom = module.secret_clevertap_passcode.secret_arn },
  { name = "GUPSHUP_TOKEN",      valueFrom = module.secret_gupshup_token.secret_arn },
  { name = "GOOGLE_API_KEY",     valueFrom = module.secret_google_api_key.secret_arn },
  { name = "DEEPTAG_API_KEY",    valueFrom = module.secret_deeptag_api_key.secret_arn },
  { name = "EMAIL_SMTP_PASSWORD",valueFrom = module.secret_email_smtp_password.secret_arn },
  { name = "OPENAI_API_KEY",     valueFrom = module.secret_openai_api_key.secret_arn },
]
```

### 2e. Security Group Changes

```hcl
# alb_sg — add port 8443 inbound (for dashboard listener)
ingress { from_port = 8443; to_port = 8443; protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }

# app_sg — add port 8091 inbound from ALB (for dashboard container)
ingress { from_port = 8091; to_port = 8091; protocol = "tcp"; source_sg = module.alb_sg.security_group_id }
```

### 2f. New Variables (`variable.tf`)

```hcl
variable "webhook_secret"           { type = string; sensitive = true }
variable "secret_google_api_key"    { type = string; sensitive = true }
variable "secret_openai_api_key"    { type = string; sensitive = true; default = "" }
variable "secret_deeptag_api_key"   { type = string; sensitive = true }
variable "secret_email_smtp_password" { type = string; sensitive = true }
variable "secret_gupshup_numbers"   { type = string; sensitive = true; default = "" }
```

Add dummy values to `terraform.tfvars` (actual values protected by `ignore_changes`):
```hcl
webhook_secret             = "dummy-webhook-secret"
secret_google_api_key      = "dummy-google-api-key"
secret_openai_api_key      = ""
secret_deeptag_api_key     = "dummy-deeptag-api-key"
secret_email_smtp_password = "dummy-smtp-password"
secret_gupshup_numbers     = ""
```

### 2g. Module-Level Fixes (applied globally — already done)

| Module | Change | Why |
|---|---|---|
| `modules/aws/ec2/main.tf` | `lifecycle { ignore_changes = [ami] }` | SSM param returns latest AMI at every plan; without this the bastion EC2 is force-replaced whenever AWS publishes a new AL2023 AMI |
| `modules/aws/secrets_manager/main.tf` | `lifecycle { ignore_changes = [secret_string] }` | Dummy values in tfvars would overwrite real API keys in AWS on every apply |

---

## 3. IAM Policy Attachments to Update

Two `aws_iam_role_policy_attachment` resources that previously referenced `module.ecs_fargate.*` must reference the new explicit role modules:

```hcl
resource "aws_iam_role_policy_attachment" "fargate_execution_secrets" {
  role       = module.webhook_task_exec_role.role_name   # was: module.ecs_fargate.exec_role_name
  policy_arn = aws_iam_policy.ecs_execution_secrets_policy.arn
}

resource "aws_iam_role_policy_attachment" "fargate_task_webhook" {
  role       = module.webhook_task_task_role.role_name   # was: module.ecs_fargate.task_role_name
  policy_arn = aws_iam_policy.webhook_policy.arn
}
```

---

## 4. `output.tf` Fixes

```hcl
# Change
output "ecs_cluster_name" {
  value = module.ecs_cluster.cluster_name   # was: module.ecs_fargate.cluster_name
}
# Remove entirely — service no longer exists:
# output "ecs_service_name" { value = module.ecs_fargate.service_name }
```

---

## 5. `terraform init` Requirement

After updating `main.tf` to add the new modules, run init before any state operations:

```bash
terraform init -reconfigure
```

This installs the new module sources. Without it, `terraform state rm` and `terraform import` will fail with "Module not installed."

---

## 6. State Reconciliation — Import Commands

Run these **after** updating main.tf and running `terraform init -reconfigure`.

Replace `<env>` with `preprod` and `<PROJ>` with `SAMMMM`.

### 6a. Remove old ecs_fargate from state (it no longer exists in code)
```bash
terraform state rm module.ecs_fargate
```

### 6b. Import ECS Cluster
```bash
terraform import module.ecs_cluster.aws_ecs_cluster.cluster \
  <env>-<PROJ>-app-sammmm
```

### 6c. Import IAM roles (previously created by ecs_fargate internally)
```bash
terraform import module.webhook_task_exec_role.aws_iam_role.role \
  <env>-<PROJ>-sammmm-webhook-task-exec-role

terraform import module.webhook_task_task_role.aws_iam_role.role \
  <env>-<PROJ>-sammmm-webhook-task-task-role
```

### 6d. Import SQS queues (get URLs first)
```bash
# Get the queue URLs
aws sqs list-queues --profile <profile> --region ap-south-1 \
  --queue-name-prefix "<env>-<PROJ>-app-" | jq '.QueueUrls[]'

terraform import module.sqs_render_dlq.aws_sqs_queue.queue \
  https://sqs.ap-south-1.amazonaws.com/<account_id>/<env>-<PROJ>-app-render-dlq

terraform import module.sqs_render.aws_sqs_queue.queue \
  https://sqs.ap-south-1.amazonaws.com/<account_id>/<env>-<PROJ>-app-render-queue

terraform import module.sqs_scan_dlq.aws_sqs_queue.queue \
  https://sqs.ap-south-1.amazonaws.com/<account_id>/<env>-<PROJ>-app-scan-dlq

terraform import module.sqs_scan.aws_sqs_queue.queue \
  https://sqs.ap-south-1.amazonaws.com/<account_id>/<env>-<PROJ>-app-scan-queue
```

### 6e. Import Target Groups (use ARN)
```bash
# Get ARNs
aws elbv2 describe-target-groups --profile <profile> --region ap-south-1 \
  --query "TargetGroups[?contains(TargetGroupName,'sammmm')].{Name:TargetGroupName,ARN:TargetGroupArn}"

terraform import module.target_group_webapi.aws_lb_target_group.tg \
  <target_group_arn_webapi>

terraform import module.target_group_webchat.aws_lb_target_group.tg \
  <target_group_arn_webchat>

terraform import module.target_group_dashboard.aws_lb_target_group.tg \
  <target_group_arn_dashboard>
```

### 6f. Import ALB Listener Rules
```bash
# Get all listener rules for the HTTPS listener
aws elbv2 describe-rules --profile <profile> --region ap-south-1 \
  --listener-arn <https_listener_arn> \
  --query "Rules[?Priority!='default'].{Priority:Priority,ARN:RuleArn}"

terraform import aws_lb_listener_rule.webchat <rule_arn_priority_5>
terraform import aws_lb_listener_rule.webapi  <rule_arn_priority_10>
```

### 6g. Import Dashboard Listener (port 8443)
```bash
# Get listener ARNs
aws elbv2 describe-listeners --profile <profile> --region ap-south-1 \
  --load-balancer-arn <alb_arn> \
  --query "Listeners[].{Port:Port,ARN:ListenerArn}"

terraform import aws_lb_listener.dashboard <listener_arn_port_8443>
```

### 6h. Import Secrets Manager secrets
```bash
# Get secret ARNs
aws secretsmanager list-secrets --profile <profile> --region ap-south-1 \
  --query "SecretList[?starts_with(Name,'<env>/SAMMMM/')].{Name:Name,ARN:ARN}"

# Secret metadata (aws_secretsmanager_secret)
terraform import module.secret_google_api_key.aws_secretsmanager_secret.secret \
  <env>/SAMMMM/GOOGLE_API_KEY

terraform import module.secret_openai_api_key.aws_secretsmanager_secret.secret \
  <env>/SAMMMM/OPENAI_API_KEY

terraform import module.secret_deeptag_api_key.aws_secretsmanager_secret.secret \
  <env>/SAMMMM/DEEPTAG_API_KEY

terraform import module.secret_email_smtp_password.aws_secretsmanager_secret.secret \
  <env>/SAMMMM/EMAIL_SMTP_PASSWORD

terraform import module.secret_gupshup_numbers.aws_secretsmanager_secret.secret \
  <env>/SAMMMM/GUPSHUP_NUMBERS
```

### 6i. Import Secret Versions — CRITICAL: use ARN form, NOT name
```bash
# Get each secret's ARN and current version ID
aws secretsmanager describe-secret --profile <profile> --region ap-south-1 \
  --secret-id <env>/SAMMMM/GOOGLE_API_KEY \
  --query '{ARN:ARN,VersionId:keys(VersionIdsToStages)|[0]}'

# Import format: <secret_ARN>|<version_id>   (ARN, NOT name — name causes replacement on next plan)
terraform import module.secret_google_api_key.aws_secretsmanager_secret_version.version \
  "<secret_arn_google_api_key>|<version_id>"

terraform import module.secret_openai_api_key.aws_secretsmanager_secret_version.version \
  "<secret_arn_openai_api_key>|<version_id>"

terraform import module.secret_deeptag_api_key.aws_secretsmanager_secret_version.version \
  "<secret_arn_deeptag_api_key>|<version_id>"

terraform import module.secret_email_smtp_password.aws_secretsmanager_secret_version.version \
  "<secret_arn_email_smtp_password>|<version_id>"

terraform import module.secret_gupshup_numbers.aws_secretsmanager_secret_version.version \
  "<secret_arn_gupshup_numbers>|<version_id>"
```

### 6j. Import ECS Services
```bash
# Format: <cluster_name>/<service_name>
terraform import module.ecs_webapi.aws_ecs_service.service \
  <env>-<PROJ>-app-sammmm/sammmm-webapi

terraform import module.ecs_webchat.aws_ecs_service.service \
  <env>-<PROJ>-app-sammmm/sammmm-webchat

terraform import module.ecs_dashboard.aws_ecs_service.service \
  <env>-<PROJ>-app-sammmm/sammmm-dashboard

terraform import module.ecs_pdf.aws_ecs_service.service \
  <env>-<PROJ>-app-sammmm/sammmm-pdf

terraform import module.ecs_scan.aws_ecs_service.service \
  <env>-<PROJ>-app-sammmm/sammmm-scan
```

---

## 7. Post-Import Plan Check

Run plan and verify before applying:

```bash
terraform plan -var-file=terraform.tfvars -no-color 2>&1 | tee /tmp/tfplan.txt

# Must see NO "must be replaced" for secrets or bastion
grep "must be replaced" /tmp/tfplan.txt

# Check destroy count — should only be old task def revisions (ecs_flush, ecs_ingest)
grep "Plan:" /tmp/tfplan.txt
```

**Acceptable in the plan:**
- `module.ecs_flush.aws_ecs_task_definition.task[0] must be replaced` — GOOGLE_API_KEY moved from env to secret; services won't switch due to `ignore_changes = [task_definition]`
- `module.ecs_ingest.aws_ecs_task_definition.task[0] must be replaced` — same reason
- In-place changes to tags, health check thresholds, SQS configs, SG rules

**Not acceptable — fix before applying:**
- Any secret version `must be replaced` — means secret version was imported with name not ARN (see §6i)
- `module.bastion_host.aws_instance.ec2 must be replaced` — means `lifecycle { ignore_changes = [ami] }` didn't apply (re-check ec2 module)
- Any live ECS service `must be replaced`

---

## 8. Known Gotchas

| Gotcha | Symptom | Fix |
|---|---|---|
| Module not installed | `state rm` fails: "module not installed" | Run `terraform init -reconfigure` after adding new modules |
| Secret version replacement | `secret_id: "name" → "arn:..."` forces replace | Always import secret versions using the ARN, not the secret name (see §6i) |
| Duplicate env var + secret | ECS API: "secret name must not be shared with env vars" | `OPENAI_API_KEY` must be removed from `sam_env_vars` since it's in `sam_worker_v2_secrets` |
| Stale state lock | `PreconditionFailed` on plan/apply | Previous command was OOM-killed; `terraform force-unlock <lock_id>` |
| output.tf references old module | `Error: Module not installed: module.ecs_fargate` | Update output.tf before running any terraform commands |
| Bastion replacement | Plan shows EC2 must replace | `ignore_changes = [ami]` in ec2 module — already fixed globally |

---

## 9. Service → Role Mapping (preprod names will differ by env prefix)

| ECS Service | Exec Role | Task Role | Port | Secrets List |
|---|---|---|---|---|
| webapi | `webhook-task-exec-role` | `webhook-task-task-role` | 8080 | `sam_api_secrets` |
| webchat | `webhook-task-exec-role` | `webhook-task-task-role` | 8080 | `sam_api_secrets` |
| dashboard | `webhook-task-exec-role` | `webhook-task-task-role` | 8091 | `sam_api_secrets` |
| pdf | `ecs-execution-role` | `flush-role` | none | `sam_worker_v2_secrets` |
| scan | `ecs-execution-role` | `flush-role` | none | `sam_worker_v2_secrets` |
| ingest (existing) | `ecs-execution-role` | `ingest-role` | none | `sam_secrets` |
| flush (existing) | `ecs-execution-role` | `flush-role` | none | `sam_secrets` |
