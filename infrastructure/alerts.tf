variable "alert_email" {
  description = "Email address for pipeline failure alerts"
  type        = string
  sensitive   = true
}

resource "aws_sns_topic" "pipeline_alerts" {
  name = "claims-platform-dev-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.pipeline_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "claims-platform-dev-lambda-errors"
  alarm_description   = "Claims validator Lambda reported an execution error."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.validator.function_name
  }

  alarm_actions = [aws_sns_topic.pipeline_alerts.arn]
}

resource "aws_cloudwatch_event_rule" "glue_failures" {
  name        = "claims-platform-dev-glue-failures"
  description = "Detect unsuccessful claims transformation runs"

  event_pattern = jsonencode({
    source        = ["aws.glue"]
    "detail-type" = ["Glue Job State Change"]
    detail = {
      jobName = [aws_glue_job.claims.name]
      state   = ["FAILED", "TIMEOUT", "STOPPED"]
    }
  })
}

resource "aws_sns_topic_policy" "pipeline_alerts" {
  arn = aws_sns_topic.pipeline_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridgePublish"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.pipeline_alerts.arn
      },
      {
        Sid       = "AllowCloudWatchPublish"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.pipeline_alerts.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_metric_alarm.lambda_errors.arn
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_event_target" "glue_alerts" {
  rule      = aws_cloudwatch_event_rule.glue_failures.name
  target_id = "SendToPipelineAlerts"
  arn       = aws_sns_topic.pipeline_alerts.arn

  depends_on = [aws_sns_topic_policy.pipeline_alerts]
}