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