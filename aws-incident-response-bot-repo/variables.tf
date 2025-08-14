variable "region" {
  description = "This represents the region for resources deployment."

}
variable "vpc_id" {
  description = "The VPC ID where the quarantine security group will be created"
  type        = string
}

variable "slack_webhook_url" {
  description = "The Slack webhook URL for sending notifications"
  type        = string
}
variable "minimum_severity" {
  description = "The minimum severity level for GuardDuty findings"
  type        = number
}