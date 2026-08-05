output "route53_ns_records" {
  description = "List of Name Server (NS) records to add to your main DNS zone (delegation)."
  value       = data.aws_route53_zone.hugo.name_servers
}

output "aws_role_arn" {
  description = "The AWS role ARN to use in your GitHub Actions to fetch dynamic creds from AWS."
  value       = one(aws_iam_role.github[*].arn)
}

output "cloudfront_distribution_id" {
  description = "The CloudFront distribution ID, for `cloudFrontDistributionID` in Hugo's deployment target so `hugo deploy --invalidateCDN` can clear the cache."
  value       = aws_cloudfront_distribution.s3_distribution.id
}
