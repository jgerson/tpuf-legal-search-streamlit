variable "hcp_project_id" {
  description = "The HCP project the service principal can manage. Defaults to the HCP_PROJECT_ID environment variable when left null."
  type        = string
  default     = null
}

variable "region" {
  description = "AWS region for the HCP network and Vault cluster. us-east-1 sits next to turbopuffer's aws-us-east-1."
  type        = string
  default     = "us-east-1"
}
