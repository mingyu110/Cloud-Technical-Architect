output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.lambda_incident_response_function.arn
}

output "quarantine_sg_id" {
  description = "ID of the Quarantine Security Group"
  value       = aws_security_group.quarantine_sg.id
}

output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector"
  value       = aws_guardduty_detector.detector.id
}