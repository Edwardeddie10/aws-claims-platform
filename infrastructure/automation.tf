resource "aws_iam_role_policy" "validator_start_glue" {
  name = "claims-validator-start-glue"
  role = aws_iam_role.validator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["glue:StartJobRun"]
      Resource = aws_glue_job.claims.arn
    }]
  })
}