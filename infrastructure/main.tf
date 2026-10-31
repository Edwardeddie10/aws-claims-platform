data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "landing" {
  bucket = "claims-platform-dev-landing-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "landing" {
  bucket = aws_s3_bucket.landing.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "landing" {
  bucket = aws_s3_bucket.landing.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

output "landing_bucket_name" {
  value = aws_s3_bucket.landing.id
}