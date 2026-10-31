# AWS Claims Data Platform

A hands-on AWS data engineering project that ingests synthetic healthcare claims, validates incoming CSV files, separates accepted and rejected files, transforms accepted claims into Parquet, and queries the results with Athena.

Built with Python, Amazon S3, AWS Lambda, AWS Glue, Amazon Athena, CloudWatch, Terraform, and IAM Identity Center.

> This README documents the implementation and successful tests completed during the build. Commands assume Windows with Git Bash. The AWS account ID and names below match this lab; substitute your own when reproducing it in another account. All sample claims are fictional.

## Contents

- [Architecture and behavior](#architecture-and-behavior)
- [Verified results](#verified-results)
- [Project structure](#project-structure)
- [1. Install and verify tools](#1-install-and-verify-tools)
- [2. Configure AWS access](#2-configure-aws-access)
- [3. Create the local project](#3-create-the-local-project)
- [4. Configure Terraform](#4-configure-terraform)
- [5. Deploy the S3 landing bucket](#5-deploy-the-s3-landing-bucket)
- [6. Generate and validate sample data](#6-generate-and-validate-sample-data)
- [7. Deploy Lambda and its S3 trigger](#7-deploy-lambda-and-its-s3-trigger)
- [8. Route accepted and rejected files](#8-route-accepted-and-rejected-files)
- [9. Deploy the Glue transformation](#9-deploy-the-glue-transformation)
- [10. Register and query data in Athena](#10-register-and-query-data-in-athena)
- [11. Automate Glue execution](#11-automate-glue-execution)
- [12. Commit and push to GitHub](#12-commit-and-push-to-github)
- [Troubleshooting](#troubleshooting)
- [Limitations and next improvements](#limitations-and-next-improvements)
- [Daily commands and cleanup](#daily-commands-and-cleanup)

## Architecture and behavior

1. A CSV is uploaded to the bucket under `incoming/`.
2. An S3 ObjectCreated notification invokes Lambda for keys ending in `.csv`.
3. Lambda reads the file and checks required fields, dates, and positive amounts.
4. If every row passes, Lambda copies the file to `validated/` and starts Glue.
5. If any row fails, Lambda copies the entire file to `quarantine/`; it does not start Glue.
6. Lambda writes validation details and, when applicable, the Glue run ID to CloudWatch.
7. Glue reads **all CSV files in `validated/`**, converts dates and amounts, and overwrites the curated Parquet dataset.
8. Athena queries those Parquet files using table metadata registered in the Glue Data Catalog.

Original files remain under `incoming/`. Routing copies files; it does not move or delete them. The S3 trigger watches only `incoming/`, preventing the routed copies from triggering the same Lambda again.

Glue permits one active run. Additional start requests use job run queuing, which has AWS-defined waiting limits and is not an unlimited durable queue.

### Resource configuration

| Component | Configuration |
|---|---|
| Region | `us-east-1` — Northern Virginia |
| Development CLI profile | `claims-dev` |
| Landing bucket | `claims-platform-dev-landing-764888049772` |
| Lambda function | `claims-platform-dev-validator` |
| Lambda runtime | Python 3.12 |
| Lambda memory / timeout | 128 MB / 30 seconds |
| Lambda log group | `/aws/lambda/claims-platform-dev-validator` |
| Lambda log retention | 7 days |
| Glue job | `claims-platform-dev-transform` |
| Glue version | 5.0 |
| Glue workers | 2 × `G.1X` |
| Glue timeout / retries | 10 minutes / 0 |
| Glue concurrent runs | 1, with job run queuing enabled |
| Athena database / table | `claims_lab.claims` |
| Curated output | `curated/claims/` |
| Query output | `athena-results/` |

### S3 layout

| Prefix | Purpose |
|---|---|
| `incoming/` | Original uploaded claims CSVs; triggers Lambda |
| `validated/` | Copies of files that passed all validation checks |
| `quarantine/` | Copies of files with one or more failed checks |
| `scripts/` | Glue script uploaded by Terraform |
| `curated/claims/` | Glue-generated Parquet dataset |
| `temporary/` | Glue temporary working location |
| `athena-results/` | Athena query output |

## Verified results

| Test | Observed outcome |
|---|---|
| Local valid CSV | `valid: true`, 3 claims, no errors |
| Local invalid CSV | `valid: false`, expected field/date/amount errors |
| Valid S3 upload | Lambda invoked and valid result logged |
| Invalid S3 upload | Lambda invoked and invalid result logged |
| Routing | Valid CSV in `validated/`; invalid CSV in `quarantine/` |
| Manual Glue run | Succeeded and produced Parquet |
| Athena query | 3 claims totaling 460.50 |
| Automatic Glue run | Valid upload started Glue; run succeeded after IAM fix |
| Final Athena verification | 3 claims totaling 460.50 |
| GitHub backup | `main` pushed and tracks `origin/main` |

## Project structure

| Path | Purpose |
|---|---|
| `infrastructure/versions.tf` | Terraform and provider requirements |
| `infrastructure/providers.tf` | Region, profile, allowed account, default tags |
| `infrastructure/main.tf` | S3 bucket, public access block, encryption, output |
| `infrastructure/lambda.tf` | Deployment ZIP, execution role/policy, logs, function |
| `infrastructure/s3_trigger.tf` | S3 invoke permission and bucket notification |
| `infrastructure/glue.tf` | Glue role/policy, script object, job configuration |
| `infrastructure/automation.tf` | Lambda permission to start the Glue job |
| `infrastructure/.terraform.lock.hcl` | Provider selections and checksums; committed |
| `src/lambda/validator.py` | Reusable validation logic and local CLI entry point |
| `src/lambda/handler.py` | S3 event handling, validation, routing, Glue start |
| `src/glue/transform_claims.py` | CSV-to-Parquet Spark transformation |
| `scripts/generate_claims.py` | Generates the valid synthetic sample CSV |
| `data/sample/claims.csv` | Valid sample |
| `data/sample/claims_invalid.csv` | Invalid sample |
| `.gitignore` | Excludes environments, state, credentials, and ZIPs |
| `docs/` | Reserved for further documentation |
| `.github/workflows/` | Reserved; no CI/CD workflow implemented yet |

Generated local files include `.venv/`, `infrastructure/.terraform/`, Terraform state, and `validator.zip`. These are excluded from Git.

## 1. Install and verify tools

AWS CLI was installed from PowerShell:

```powershell
winget install --exact --id Amazon.AWSCLI
```

Close and reopen the terminal after installation. Verify tools:

```bash
aws --version
terraform -version
python --version
git --version
code --version
```

The development computer reported Python 3.12.10, Git 2.34.1.windows.1, and VS Code 1.141.1. Python's standard library is sufficient for the local validator. Lambda supplies Boto3, and Glue supplies its own Spark and Glue libraries.

## 2. Configure AWS access

### Initial sign-in and identity check

The initial attempt used:

```bash
aws login --region us-east-1
```

The default profile already contained access-key credentials, so a separate initial profile was created:

```bash
aws login --profile claims-lab --region us-east-1
aws sts get-caller-identity --profile claims-lab
```

That identity check returned a root ARN. Development was then switched to IAM Identity Center. `claims-lab` was only a local authentication profile name; it did not install or deploy a claims project.

### IAM Identity Center setup in the console

1. Open IAM Identity Center in Northern Virginia.
2. Enable an organization instance, creating AWS Organizations as part of this account's setup.
3. Select **Single-Region instance** with an **AWS owned key**.
4. Under **Users → Add user**, create username `edward`, supply name/email details, and select email-based password setup.
5. Continue past optional groups, review, and click **Add user** to actually create the user and send the invitation.
6. Use the invitation to set a password. A passkey was also registered during sign-in.
7. Under **AWS accounts**, select the account and assign user `edward`.
8. Create a predefined **AdministratorAccess** permission set with the default one-hour session duration.
9. Return to the assignment flow, refresh the permission-set list, select AdministratorAccess, and submit.
10. Wait for successful provisioning.

AdministratorAccess provides broad account administration for this personal lab. The Lambda and Glue service roles have separate, narrower policies defined in Terraform.

### Configure the development profile

```bash
aws configure sso --profile claims-dev
```

| Prompt | Value |
|---|---|
| SSO session name | `edward-sso` |
| SSO start URL | IPv4-only AWS access portal URL copied from the Identity Center dashboard |
| SSO region | `us-east-1` |
| Registration scopes | `sso:account:access` |
| Account | The lab account |
| Role | `AdministratorAccess` |
| Default client region | `us-east-1` |
| Default output format | `json` |

The access portal URL is different from the AWS admin console URL. Sign in as `edward` using the new password and approve the CLI access request.

```bash
aws sts get-caller-identity --profile claims-dev
```

The verified ARN contained `assumed-role/AWSReservedSSO_AdministratorAccess_.../edward`.

For later sessions:

```bash
aws sso login --profile claims-dev
```

## 3. Create the local project

Commands used in Git Bash:

```bash
mkdir -p /c/project/aws-claims-platform
cd /c/project/aws-claims-platform
git init
python -m venv .venv
source .venv/Scripts/activate
code .
mkdir -p infrastructure src/lambda scripts data/sample docs .github/workflows
touch README.md .gitignore
```

The Glue folder was added later as `src/glue`, alongside `src/lambda`.

The `.gitignore` configuration:

```gitignore
# Python
.venv/
__pycache__/
*.pyc

# Terraform
**/.terraform/
*.tfstate
*.tfstate.*
*.tfplan
*.tfvars
!*.tfvars.example
crash.log

# Credentials and local configuration
.aws/
.env
.env.*

# Generated packages
*.zip
```

## 4. Configure Terraform

Copy infrastructure/terraform.tfvars.example to infrastructure/terraform.tfvars, then replace the example account ID and email with your own. The terraform.tfvars file is excluded from Git.
`versions.tf` declares Terraform `>= 1.5.0`, AWS provider `~> 6.0`, and archive provider `~> 2.0`.

`providers.tf` sets:

```hcl
provider "aws" {
  region              = "us-east-1"
  profile             = "claims-dev"
  allowed_account_ids = ["764888049772"]

  default_tags {
    tags = {
      Project     = "aws-claims-platform"
      Environment = "dev"
      ManagedBy   = "Terraform"
    }
  }
}
```

Run Terraform from the infrastructure directory:

```bash
cd /c/project/aws-claims-platform/infrastructure
terraform init
terraform fmt
terraform validate
terraform plan
```

| Command | Purpose |
|---|---|
| `init` | Initializes the working directory and installs providers |
| `fmt` | Formats Terraform configuration |
| `validate` | Checks configuration structure and references |
| `plan` | Previews changes without applying them |
| `apply` | Creates or updates resources after confirmation |

State remains local; no remote backend was configured. A fresh clone does not include the existing state and must not be applied blindly against the same account.

## 5. Deploy the S3 landing bucket

`main.tf` defines:

- `aws_caller_identity.current` to obtain the account ID.
- `aws_s3_bucket.landing` with the account ID in its name.
- `aws_s3_bucket_public_access_block.landing` with all four blocking settings enabled.
- `aws_s3_bucket_server_side_encryption_configuration.landing` using AES256/SSE-S3.
- Output `landing_bucket_name`.

```bash
terraform fmt
terraform validate
terraform plan
terraform apply
```

The initial deployment added three managed resources. Enter `yes` when reviewing the apply confirmation. The bucket was confirmed in the AWS Console.

## 6. Generate and validate sample data

`scripts/generate_claims.py` uses `csv` and `pathlib` to write three fictional records into `data/sample/claims.csv`.

From `infrastructure/`:

```bash
python ../scripts/generate_claims.py
```

### Valid sample

```csv
claim_id,member_id,provider_id,service_date,procedure_code,claim_amount
CLM001,MEM001,PRV001,2026-10-01,99213,150.00
CLM002,MEM002,PRV002,2026-10-02,99214,225.00
CLM003,MEM003,PRV001,2026-10-03,80053,85.50
```

### Invalid sample

`data/sample/claims_invalid.csv` was created manually:

```csv
claim_id,member_id,provider_id,service_date,procedure_code,claim_amount
CLM004,,PRV001,2026-02-30,99213,-50.00
```

### Validation rules

`src/lambda/validator.py` exposes `validate_claims(file)` and a local command-line entry point. It checks:

1. All six required column names exist.
2. Required values are nonblank after trimming.
3. Service dates are valid calendar dates in `YYYY-MM-DD` format.
4. Claim amounts are finite positive decimal numbers.
5. At least one claim exists.

```bash
python ../src/lambda/validator.py ../data/sample/claims.csv
python ../src/lambda/validator.py ../data/sample/claims_invalid.csv
```

The valid result:

```json
{"valid": true, "claim_count": 3, "errors": []}
```

The invalid result:

```json
{
  "valid": false,
  "claim_count": 1,
  "errors": [
    "Row 2: member_id is blank.",
    "Row 2: service_date must be YYYY-MM-DD.",
    "Row 2: claim_amount must be a positive number."
  ]
}
```

Row 1 is the header, so the first claim is row 2. Local validation exits with status 1 when validation fails; this is intentional.

Initial upload command:

```bash
aws s3 cp ../data/sample/claims.csv s3://claims-platform-dev-landing-764888049772/incoming/claims.csv --profile claims-dev
```

## 7. Deploy Lambda and its S3 trigger

The archive provider packages `src/lambda/` into `infrastructure/validator.zip`. `lambda.tf` defines the ZIP data source plus four managed resources:

1. Lambda execution role trusting `lambda.amazonaws.com`.
2. CloudWatch log group with seven-day retention.
3. Inline execution policy.
4. Python 3.12 function with handler `handler.lambda_handler`, 128 MB memory, and a 30-second timeout.

The handler reads each S3 event record, decodes the object key with `unquote_plus`, reads and closes the S3 response body, decodes UTF-8 content, and passes an in-memory `StringIO` stream to the validator.

After adding the archive provider:

```bash
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

The Lambda stage initially added four managed resources.

`s3_trigger.tf` adds:

- `aws_lambda_permission.allow_s3`, restricted to the landing bucket and source account.
- `aws_s3_bucket_notification.landing`, matching `s3:ObjectCreated:*`, prefix `incoming/`, and suffix `.csv`.

That stage added two resources. Existing objects do not generate a new creation event merely because the trigger was configured; re-upload a sample to test it.

```bash
aws s3 cp ../data/sample/claims.csv s3://claims-platform-dev-landing-764888049772/incoming/claims_test.csv --profile claims-dev
```

Read logs from Git Bash:

```bash
MSYS_NO_PATHCONV=1 aws logs tail /aws/lambda/claims-platform-dev-validator --since 10m --follow --profile claims-dev --region us-east-1
```

Press Ctrl+C to stop following. `MSYS_NO_PATHCONV=1` prevents Git Bash from converting the log group name into a Windows filesystem path.

## 8. Route accepted and rejected files

The Lambda policy allows:

| Permission | Scope |
|---|---|
| `s3:GetObject` | Landing bucket `incoming/*` |
| `s3:PutObject` | Landing bucket `validated/*` and `quarantine/*` |
| `logs:CreateLogStream`, `logs:PutLogEvents` | Validator log group |

The handler chooses the destination using the file-level validation result, removes the `incoming/` prefix, and calls `s3.copy_object`.

Example outcomes:

- `incoming/claims.csv` → `validated/claims.csv`.
- `incoming/claims_invalid.csv` → `quarantine/claims_invalid.csv`.

Updating both policy and handler produced a plan with two changes. After applying, both samples were uploaded again:

```bash
aws s3 cp ../data/sample/claims.csv s3://claims-platform-dev-landing-764888049772/incoming/claims.csv --profile claims-dev
aws s3 cp ../data/sample/claims_invalid.csv s3://claims-platform-dev-landing-764888049772/incoming/claims_invalid.csv --profile claims-dev
```

Both destination prefixes and their expected files were verified in the console. Validation errors remain in CloudWatch; a separate error-report object is not yet written to S3.

## 9. Deploy the Glue transformation

Create `src/glue/transform_claims.py`, alongside—not inside—`src/lambda`.

The script:

1. Resolves `JOB_NAME`, `INPUT_PATH`, and `OUTPUT_PATH` arguments.
2. Initializes Spark, GlueContext, and Job.
3. Reads header-based CSV input with schema inference disabled.
4. Trims string fields and preserves IDs and procedure codes as strings.
5. Converts `service_date` to a date and `claim_amount` to `DECIMAL(18,2)`.
6. Writes Parquet in `overwrite` mode and commits the job.

`glue.tf` defines four managed resources: the execution role, inline policy, uploaded script object, and Glue job.

### Job arguments

| Argument | Value |
|---|---|
| `--job-language` | `python` |
| `--job-bookmark-option` | `job-bookmark-disable` |
| `--INPUT_PATH` | `s3://claims-platform-dev-landing-764888049772/validated/` |
| `--OUTPUT_PATH` | `s3://claims-platform-dev-landing-764888049772/curated/claims/` |
| `--TempDir` | `s3://claims-platform-dev-landing-764888049772/temporary/` |

### Glue role permissions

- Bucket listing and location lookup on the landing bucket.
- GetObject for `validated/*`, `scripts/*`, `curated/*`, and `temporary/*`.
- PutObject and DeleteObject for `curated/*` and `temporary/*`.
- PutObject/DeleteObject coverage for exact marker keys `curated_$folder$` and `temporary_$folder$`.
- CloudWatch log group/stream creation and event writing under `/aws-glue/*`.

```bash
terraform fmt
terraform validate
terraform plan
terraform apply
```

Initial plan: four resources added. Creating the job does not start processing. The first manual run used:

```bash
aws glue start-job-run --job-name claims-platform-dev-transform --profile claims-dev --region us-east-1
```

Follow status under **AWS Glue → ETL jobs → claims-platform-dev-transform → Runs**. The run succeeded, and `.parquet` files appeared in `curated/claims/`.

Glue execution incurs compute charges. The configured timeout and worker count bound each run's configuration, not total monthly spending or the number of runs.

## 10. Register and query data in Athena

These metadata and query settings were configured manually in the console; they are **not yet managed by Terraform**.

1. Open Athena in Northern Virginia.
2. Select **Query your data in Athena console**.
3. In the query editor, open **Query settings** and configure the S3 query result location:

```text
s3://claims-platform-dev-landing-764888049772/athena-results/
```

Run each SQL statement separately:

```sql
CREATE DATABASE IF NOT EXISTS claims_lab;
```

```sql
CREATE EXTERNAL TABLE IF NOT EXISTS claims_lab.claims (
    claim_id STRING,
    member_id STRING,
    provider_id STRING,
    service_date DATE,
    procedure_code STRING,
    claim_amount DECIMAL(18,2)
)
STORED AS PARQUET
LOCATION 's3://claims-platform-dev-landing-764888049772/curated/claims/';
```

```sql
SELECT *
FROM claims_lab.claims
ORDER BY claim_id;
```

```sql
SELECT
    COUNT(*) AS total_claims,
    SUM(claim_amount) AS total_claim_amount
FROM claims_lab.claims;
```

Verified result: **3 claims, total amount 460.50**. Athena reads the files in S3; creating this external table registers metadata rather than loading another copy of the data.

## 11. Automate Glue execution

`automation.tf` grants the Lambda role `glue:StartJobRun` scoped to `aws_glue_job.claims.arn`. This added one inline policy resource.

In the existing Glue job resource:

```hcl
job_run_queuing_enabled = true

execution_property {
  max_concurrent_runs = 1
}
```

The final Lambda handler initializes a Glue client and, after copying a valid file, starts the job:

```python
glue = boto3.client("glue")

# Inside lambda_handler, after successful validation and copy:
if result["valid"]:
    run = glue.start_job_run(
        JobName="claims-platform-dev-transform",
        JobRunQueuingEnabled=True,
    )
    summary["glue_job_run_id"] = run["JobRunId"]
```

Lambda logs the start response; it does not wait for the Glue job to finish. A Glue run ID confirms submission, not successful transformation.

Deploy code/configuration updates:

```bash
terraform fmt
terraform validate
terraform plan
terraform apply
```

Re-upload the valid CSV using the **same key**:

```bash
aws s3 cp ../data/sample/claims.csv s3://claims-platform-dev-landing-764888049772/incoming/claims.csv --profile claims-dev
```

A new Glue run appeared automatically. After fixing the folder-marker permission issue described below, the automatic run succeeded and Athena again returned three claims totaling 460.50.

## 12. Commit and push to GitHub

From the project root:

```bash
cd /c/project/aws-claims-platform
git add .gitignore README.md infrastructure/*.tf infrastructure/.terraform.lock.hcl src scripts data/sample
git status
git commit -m "Build claims pipeline with validation, Glue transformation, and Athena verification"
```

Verify the staged list excludes state, credentials, virtual environments, provider downloads, and ZIPs. The initial local checkpoint was commit `3584ef3` with 16 tracked files.

A GitHub repository was created without an initial README, license, or gitignore, then connected:

```bash
git branch -M main
git remote add origin https://github.com/Edwardeddie10/aws-claims-platform.git
git push -u origin main
```

The push succeeded after refreshing GitHub authentication. `main` now tracks `origin/main`.

To commit this README after replacing the local file:

```bash
git add README.md
git commit -m "Document claims pipeline setup, configuration, and troubleshooting"
git push
```

## Pipeline failure alerts

Email notifications use a shared SNS topic:
`claims-platform-dev-alerts`.

Configuration is defined in `infrastructure/alerts.tf`.

### Configure the email destination

Create `infrastructure/terraform.tfvars`:

```hcl
alert_email = "your-email@example.com"
```

This file is excluded from Git. The email address is still stored in local
Terraform state; `sensitive = true` hides it from normal CLI output.

Run from `infrastructure/`:

```bash
terraform fmt
terraform validate
terraform plan
terraform apply
```

Open the AWS subscription confirmation email and click **Confirm subscription**.

### Alert conditions

| Component | Trigger | Delivery path |
|---|---|---|
| Lambda | At least one execution error in a one-minute evaluation period | CloudWatch alarm → SNS → email |
| Glue | Job enters FAILED, TIMEOUT, or STOPPED | EventBridge rule → SNS → email |

Invalid claims are handled validation results and do not trigger the Lambda
execution-error alarm. Manually stopping Glue also generates an alert.

### Tests completed

1. Published a test SNS message and received the email.
2. Manually set the Lambda alarm to ALARM and received the alarm email.
3. Started a separate Glue run with a nonexistent input path.
4. Confirmed that run failed and received the Glue failure email.

SNS delivery test:

```bash
aws sns publish \
  --topic-arn arn:aws:sns:us-east-1:764888049772:claims-platform-dev-alerts \
  --subject "Claims pipeline alert test" \
  --message "Test notification from the claims pipeline." \
  --profile claims-dev \
  --region us-east-1
```

Lambda alarm delivery test:

```bash
aws cloudwatch set-alarm-state \
  --alarm-name claims-platform-dev-lambda-errors \
  --state-value ALARM \
  --state-reason "Manual test of pipeline failure notifications" \
  --profile claims-dev \
  --region us-east-1
```

This tests the alarm notification path; it does not cause a Lambda execution
failure. CloudWatch resumes evaluating the real metric afterward.

Controlled Glue failure test:

```bash
aws glue start-job-run \
  --job-name claims-platform-dev-transform \
  --arguments '{"--INPUT_PATH":"s3://claims-platform-dev-landing-764888049772/alert-test-missing/","--OUTPUT_PATH":"s3://claims-platform-dev-landing-764888049772/alert-test-output/"}' \
  --profile claims-dev \
  --region us-east-1
```

The overrides apply only to that run. It failed while reading the nonexistent
input, before writing output. Glue compute charges apply to the test.
Notification delivery can take a few minutes.

These tests verify delivery paths, not guaranteed delivery of every future
failure. Glue queue expiration and notification-delivery failures need
additional monitoring.

## Troubleshooting

### Terraform says “No changes” before anything was deployed

The initial `.tf` files existed but were zero bytes on disk. Editor content had not been saved yet. Use **File → Save All**, then inspect:

```bash
pwd
ls -l *.tf
wc -c main.tf providers.tf versions.tf
cat main.tf
```

Then rerun `terraform init`, `terraform validate`, and `terraform plan`. Validation of an empty configuration does not prove the intended resources are present.

### Root identity returned by STS

Browser sign-in and CLI authentication are separate. The initial `claims-lab` login used a root session. Configure and use `claims-dev` with IAM Identity Center; verify its assumed-role ARN with STS.

### Identity Center invitation did not arrive

The user-creation wizard had not been completed. Continue through optional groups and review, then click **Add user**. Password setup email is sent after final submission.

### Permission set is “Not provisioned”

Creating the permission set is separate from assigning it. In **AWS accounts**, select the account, assign user `edward`, select the permission set, and submit. Provisioning occurs during assignment.

### Lambda: “I/O operation on closed file”

The first streaming implementation failed while the CSV reader was consuming the body. The handler was changed to read the S3 body completely, close it explicitly, decode the bytes, and validate through `io.StringIO`. This is suitable for the small lab files; large files need a bounded-memory design.

### CloudWatch logGroupName validation error in Git Bash

Git Bash converted `/aws/lambda/...` to a local Windows path. Disable path conversion for the command:

```bash
MSYS_NO_PATHCONV=1 aws logs tail /aws/lambda/claims-platform-dev-validator --since 10m --profile claims-dev --region us-east-1
```

### Terraform cannot find the Glue script

The script was accidentally created at `src/lambda/glue/transform_claims.py`. The expected location is `src/glue/transform_claims.py`. From `infrastructure/`, the correction used:

```bash
mv ../src/lambda/glue ../src/glue
```

Run this move only if the misplaced source folder still exists and the destination is not already populated.

### References to undeclared Lambda or log-group resources

Only a policy block had been retained when editing `lambda.tf`. Restore the complete file with the archive data source, execution role, log group, inline policy, and function. Replace a single resource block only when instructed to do so; do not replace the whole file with a fragment.

### Plan shows one change instead of the expected two

If only the policy changed, verify the handler contains the new routing or automation code and save it. The archive hash changes only when the saved source package changes. Plan counts depend on what is already deployed.

### Glue denied PutObject on `curated_$folder$`

During overwrite, Glue attempted to write a folder-marker object at the bucket root. The original `curated/*` resource scope did not match `curated_$folder$`. The write-policy resource list was updated to:

```hcl
Resource = [
  "${aws_s3_bucket.landing.arn}/curated/*",
  "${aws_s3_bucket.landing.arn}/curated_$folder$",
  "${aws_s3_bucket.landing.arn}/temporary/*",
  "${aws_s3_bucket.landing.arn}/temporary_$folder$"
]
```

Apply the policy update and re-upload the valid sample. A failed overwrite can remove previous output before replacement completes; query Athena after the recovery run succeeds.

### Terraform invalid expression after a Resource list

Inside `Statement = [...]`, each policy object must close before the next one begins:

```hcl
      Resource = [
        "example-resource"
      ]
    },
    {
      Effect = "Allow"
      # next statement
    }
```

The final diagnosed issue was a missing `},` between the write-policy statement and the logging statement. Use `cat -n glue.tf` to inspect the saved file and line numbers.

### GitHub rejects username or token

GitHub account passwords are not accepted for HTTPS Git operations. Cached credentials were cleared, then browser sign-in was completed:

```bash
printf 'protocol=https\nhost=github.com\n\n' | git credential reject
git push -u origin main
```

This can clear the cached GitHub credential used by other HTTPS repositories too. Never put tokens or passwords into the repository or README.

## Limitations and next improvements

- **Lab implementation:** uses fictional data and does not implement production healthcare compliance controls.
- **Whole-file acceptance:** one failed row quarantines the entire CSV.
- **Basic validation:** checks presence, dates, and positive finite amounts; does not verify member/provider existence, procedure validity, duplicate IDs, or decimal precision compatibility with Glue.
- **No deduplication:** different validated filenames containing the same claims will duplicate rows. Re-uploading the same key replaces that object instead.
- **Full rebuild:** each Glue run scans all validated CSVs and overwrites curated output. Athena queries during overwrite can see missing/incomplete data.
- **No exactly-once guarantee:** S3 notifications and Lambda retries can cause duplicate job submissions. Queuing serializes runs but does not deduplicate events.
- **Mutable input keys:** overwriting the same key during processing can cause validation/copy races; immutable batch keys or version-aware reads are future improvements.
- **No stale-copy cleanup:** an invalid replacement of a previously valid key does not remove the older copy from `validated/`.
- **Finite queueing:** job queue expiration and failures need monitoring/recovery beyond this lab.
- **Manual catalog setup:** Athena database/table and query settings were created outside Terraform.
- **Local state:** state is excluded from Git and has no remote backend or cross-computer locking.
- **No CI/CD yet:** GitHub Actions workflows are not configured.
- **Not implemented yet:** Redshift, alerts/SNS, structured S3 error reports, a dashboard, and automated end-to-end tests.
- **Cost controls:** worker count, timeout, and zero retries are configured, but a budget alert and lifecycle policies have not been added.

Suggested next work: document SQL in versioned files, move catalog/workgroup resources into Terraform, configure remote state, add failure alerts and idempotency, improve batch processing, then add CI/CD.

## Daily commands and cleanup

### Resume work on the existing computer

```bash
cd /c/project/aws-claims-platform
source .venv/Scripts/activate
aws sso login --profile claims-dev
aws sts get-caller-identity --profile claims-dev
cd infrastructure
terraform plan
```

### Inspect a Glue run

The following is a template; replace `YOUR_JOB_RUN_ID` with the returned ID:

```bash
aws glue get-job-run --job-name claims-platform-dev-transform --run-id YOUR_JOB_RUN_ID --profile claims-dev --region us-east-1
```

### List files and inspect logs

```bash
aws s3 ls s3://claims-platform-dev-landing-764888049772/curated/claims/ --profile claims-dev
MSYS_NO_PATHCONV=1 aws logs tail /aws/lambda/claims-platform-dev-validator --since 10m --profile claims-dev --region us-east-1
```

### Using another computer

Clone the repository, install the tools, recreate the virtual environment, and configure the `claims-dev` SSO profile there. AWS credentials, local environments, and Terraform state are not copied by Git. Before running Terraform against the deployed lab from another computer, transfer the current state securely or migrate to a remote backend. Do not create a second empty state and apply it against the existing lab.

### Cleanup procedure — not executed during the build

When intentionally retiring this lab:

1. Stop new uploads and allow active/queued processing to finish or stop the runs.
2. Back up anything needed from S3 and the current Terraform state.
3. Review a destruction plan from the existing state using `terraform plan -destroy`.
4. Empty only the lab bucket when ready to delete its data. The configured bucket does not force-delete nonempty contents.
5. Run `terraform destroy` and carefully review the confirmation.
6. Remove the manually created Athena table/database and review any residual query outputs or Glue-created log groups separately.

Terraform does not manage the IAM Identity Center organization/user/permission-set setup in this repository, so destroying the pipeline will not remove that account-access setup.

## References

- [AWS CLI IAM Identity Center configuration](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html)
- [Terraform AWS Glue job resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_job)
- [Terraform AWS Lambda function resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function)
- [AWS Glue job configuration and queueing](https://docs.aws.amazon.com/glue/latest/dg/add-job.html)
- [Athena CREATE TABLE](https://docs.aws.amazon.com/athena/latest/ug/create-table.html)
