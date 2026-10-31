resource "aws_iam_role" "glue" {
  name = "claims-platform-dev-glue"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "glue" {
  name = "claims-glue-access"
  role = aws_iam_role.glue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = aws_s3_bucket.landing.arn
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = [
          "${aws_s3_bucket.landing.arn}/validated/*",
          "${aws_s3_bucket.landing.arn}/scripts/*",
          "${aws_s3_bucket.landing.arn}/curated/*",
          "${aws_s3_bucket.landing.arn}/temporary/*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:DeleteObject"]
        Resource = [
          "${aws_s3_bucket.landing.arn}/curated/*",
          "${aws_s3_bucket.landing.arn}/curated_$folder$",
          "${aws_s3_bucket.landing.arn}/temporary/*",
          "${aws_s3_bucket.landing.arn}/temporary_$folder$"
        ]

      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/*"
      }
    ]
  })
}

resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.landing.id
  key    = "scripts/transform_claims.py"
  source = "${path.module}/../src/glue/transform_claims.py"

  source_hash = filemd5("${path.module}/../src/glue/transform_claims.py")
}

resource "aws_glue_job" "claims" {
  name     = "claims-platform-dev-transform"
  role_arn = aws_iam_role.glue.arn

  glue_version            = "5.0"
  worker_type             = "G.1X"
  number_of_workers       = 2
  timeout                 = 10
  max_retries             = 0
  job_run_queuing_enabled = true

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.landing.id}/${aws_s3_object.glue_script.key}"
  }

  default_arguments = {
    "--job-language"        = "python"
    "--job-bookmark-option" = "job-bookmark-disable"
    "--INPUT_PATH"          = "s3://${aws_s3_bucket.landing.id}/validated/"
    "--OUTPUT_PATH"         = "s3://${aws_s3_bucket.landing.id}/curated/claims/"
    "--TempDir"             = "s3://${aws_s3_bucket.landing.id}/temporary/"
  }

  execution_property {
    max_concurrent_runs = 1
  }

  depends_on = [aws_iam_role_policy.glue]
}