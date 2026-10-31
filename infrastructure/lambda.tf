data "archive_file" "validator" {
  type        = "zip"
  source_dir  = "${path.module}/../src/lambda"
  output_path = "${path.module}/validator.zip"
  excludes    = ["__pycache__"]
}

resource "aws_iam_role" "validator" {
  name = "claims-platform-dev-validator"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_cloudwatch_log_group" "validator" {
  name              = "/aws/lambda/claims-platform-dev-validator"
  retention_in_days = 7
}

resource "aws_iam_role_policy" "validator" {
  name = "claims-validator-access"
  role = aws_iam_role.validator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.landing.arn}/incoming/*"
      },
      {
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = [
          "${aws_s3_bucket.landing.arn}/validated/*",
          "${aws_s3_bucket.landing.arn}/quarantine/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.validator.arn}:*"
      }
    ]
  })
}

resource "aws_lambda_function" "validator" {
  function_name = "claims-platform-dev-validator"
  role          = aws_iam_role.validator.arn

  runtime     = "python3.12"
  handler     = "handler.lambda_handler"
  timeout     = 30
  memory_size = 128

  filename         = data.archive_file.validator.output_path
  source_code_hash = data.archive_file.validator.output_base64sha256

  depends_on = [aws_iam_role_policy.validator]
}