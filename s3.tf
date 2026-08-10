locals {
  bucket_name = var.bucket_name
  dns_name    = var.dns_name
  origin_name = "s3-cloudfront-hugo"
}

resource "aws_acm_certificate" "hugo" {
  provider          = aws.aws_cloudfront # CloudFront uses certificates from US-EAST-1 region only
  domain_name       = local.dns_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

data "aws_route53_zone" "hugo" {
  name         = local.dns_name
  private_zone = false
}

resource "aws_route53_record" "hugo" {
  for_each = {
    for dvo in aws_acm_certificate.hugo.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.hugo.zone_id
}

resource "aws_acm_certificate_validation" "hugo" {
  provider                = aws.aws_cloudfront # CloudFront uses certificates from US-EAST-1 region only
  certificate_arn         = aws_acm_certificate.hugo.arn
  validation_record_fqdns = [for record in aws_route53_record.hugo : record.fqdn]
}

resource "aws_cloudfront_origin_access_control" "hugo" {
  name                              = local.origin_name
  description                       = "Origin Access Control for S3 bucket Hugo."
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_iam_policy_document" "s3_bucket_policy" {
  statement {
    sid = "1"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "${aws_s3_bucket.hugo.arn}/*",
    ]
    condition {
      test     = "StringLike"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.s3_distribution.arn]
    }
  }
}

resource "aws_s3_bucket" "hugo" {
  bucket        = local.bucket_name
  force_destroy = false

  tags = var.tags
}

resource "aws_s3_bucket_policy" "hugo" {
  bucket = aws_s3_bucket.hugo.id
  policy = data.aws_iam_policy_document.s3_bucket_policy.json
}

resource "aws_s3_bucket_public_access_block" "hugo" {
  bucket = aws_s3_bucket.hugo.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Buckets created since April 2023 have ACLs disabled, so `aws_s3_bucket_acl`
# fails on a fresh bucket with AccessControlListNotSupported. Say so explicitly.
resource "aws_s3_bucket_ownership_controls" "hugo" {
  bucket = aws_s3_bucket.hugo.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "hugo" {
  bucket = aws_s3_bucket.hugo.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_cloudfront_function" "redirect" {
  name    = "redirect"
  runtime = "cloudfront-js-2.0"
  comment = "Redirect users from cloudfront to s3 real object name."
  code    = file("${path.module}/redirect.js")
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# HSTS, X-Content-Type-Options, X-Frame-Options, Referrer-Policy.
data "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "Managed-SecurityHeadersPolicy"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = aws_s3_bucket.hugo.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.hugo.id
    origin_id                = local.origin_name
  }

  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  default_root_object = "index.html"

  aliases = [local.dns_name]

  default_cache_behavior {
    allowed_methods = [
      "GET",
      "HEAD",
    ]

    cached_methods = [
      "GET",
      "HEAD",
    ]

    target_origin_id = local.origin_name

    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
    compress                   = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.redirect.arn
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = var.cloudfront_price_class

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.hugo.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # With OAC, a missing object comes back from S3 as a 403. Serve Hugo's 404
  # page and keep the 404 status, so search engines do not index dead URLs as
  # if they were the home page.
  custom_error_response {
    error_code            = 403
    response_code         = 404
    error_caching_min_ttl = 10
    response_page_path    = "/404.html"
  }

  custom_error_response {
    error_code            = 404
    response_code         = 404
    error_caching_min_ttl = 10
    response_page_path    = "/404.html"
  }

  wait_for_deployment = false

  tags = var.tags
}

# Keeps the existing apex record in state instead of destroying and recreating
# it, which would take the site off DNS for the length of the apply.
moved {
  from = aws_route53_record.route53_record
  to   = aws_route53_record.route53_record["A"]
}

resource "aws_route53_record" "route53_record" {
  for_each = toset(["A", "AAAA"]) # is_ipv6_enabled is useless without the AAAA alias

  zone_id = data.aws_route53_zone.hugo.zone_id
  name    = local.dns_name
  type    = each.value

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = false
  }
}
