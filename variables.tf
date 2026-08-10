variable "bucket_name" {
  description = "The S3 bucket name to store the HUGO website."
  type        = string
}

variable "dns_name" {
  description = "The DNS name to use for your HUGO website."
  type        = string
}

variable "cloudfront_price_class" {
  description = "The price class to use for CloudFront distribution."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.cloudfront_price_class)
    error_message = "Must be one of PriceClass_All, PriceClass_200 or PriceClass_100."
  }
}

variable "tags" {
  description = "Tags applied to every resource created by this stack."
  type        = map(string)
  default     = {}
}

###### GITHUB ACTION VARIABLES ######
#      Optionnal configuration      #
# To use this configuration, set    #
# at least github_repositories and  #
# github_org variables              #
#####################################
variable "oidc_url" {
  description = "The URL of the identity provider. Corresponds to the iss claim."
  type        = string
  default     = "https://token.actions.githubusercontent.com"
}

variable "client_id_list" {
  description = "A list of client IDs (also known as audiences)."
  type        = list(string)
  default     = ["sts.amazonaws.com"]
}

variable "github_org" {
  description = "GitHub organisation name."
  type        = string
  default     = ""
}

variable "github_repositories" {
  description = "List of GitHub repository names."
  type        = list(string)
  default     = []
}

variable "github_subjects" {
  description = "GitHub `sub` claim suffixes allowed to assume the role, appended to `repo:<org>/<repo>:`. Use `[\"*\"]` to allow every ref."
  type        = list(string)
  default     = ["ref:refs/heads/main"]
}

variable "iam_role_name" {
  description = "Friendly name of the role. If omitted, Terraform will assign a random, unique name."
  type        = string
  default     = "GitHubOIDCRole"
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds."
  type        = number
  default     = 3600 #1hour (min accepted by AWS)
}
