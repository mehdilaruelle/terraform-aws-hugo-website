output "route53_ns_records" {
  description = "List of Name Server (NS) records to add to your main DNS zone (delegation)."
  value       = data.aws_route53_zone.hugo.name_servers
}

output "aws_role_arn" {
  description = "The AWS role ARN to use in your GitHub Actions to fetch dynamic creds from AWS."
  value       = one(aws_iam_role.github[*].arn)
}
