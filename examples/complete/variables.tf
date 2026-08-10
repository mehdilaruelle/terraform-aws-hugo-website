variable "bucket_name" {
  description = "The S3 bucket name that will hold the built site."
  type        = string
  default     = "hugo-blog-example-bucket"
}

variable "dns_name" {
  description = "The domain the site is served from. A Route 53 hosted zone for it must already exist."
  type        = string
  default     = "example.com"
}

variable "region" {
  description = "Region for everything except the ACM certificate, which is always issued in us-east-1."
  type        = string
  default     = "eu-west-3"
}

variable "tags" {
  description = "Tags applied to every resource, through the provider's default_tags."
  type        = map(string)
  default = {
    project = "hugo-blog"
  }
}

variable "github_org" {
  description = "GitHub organisation or user allowed to assume the publishing role. Leave empty to skip the role entirely."
  type        = string
  default     = ""
}

variable "github_repositories" {
  description = "Repositories allowed to assume the publishing role."
  type        = list(string)
  default     = []
}
