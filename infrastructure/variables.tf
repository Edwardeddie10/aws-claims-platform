variable "aws_account_id" {
  description = "AWS account ID where the pipeline will be deployed"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Enter a 12-digit AWS account ID."
  }
}