output "route53_ns_records" {
  description = "Name servers to delegate the domain to, if the zone is not already delegated."
  value       = module.hugo_blog.route53_ns_records
}

output "aws_role_arn" {
  description = "Role ARN for the GitHub Actions workflow, when the OIDC role is enabled."
  value       = module.hugo_blog.aws_role_arn
}

output "cloudfront_distribution_id" {
  description = "Distribution ID for `hugo deploy --invalidateCDN`."
  value       = module.hugo_blog.cloudfront_distribution_id
}
