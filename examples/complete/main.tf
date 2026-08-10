# A complete deployment: S3 origin, CloudFront, ACM certificate, Route 53
# records, and the GitHub OIDC role a workflow uses to publish the site.
#
# The providers are configured here rather than inside the module. That is what
# lets you call the module twice in one configuration, wrap it in for_each, or
# remove it cleanly — none of which is possible when a module configures its own
# providers.

provider "aws" {
  region = var.region

  default_tags {
    tags = var.tags
  }
}

# CloudFront only accepts ACM certificates issued in us-east-1, whatever region
# the rest of the stack lives in.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = var.tags
  }
}

module "hugo_blog" {
  # Published: source = "mehdilaruelle/hugo-blog/aws"
  #            version = "~> 1.0"
  source = "../../"

  providers = {
    aws                = aws
    aws.aws_cloudfront = aws.us_east_1
  }

  bucket_name = var.bucket_name
  dns_name    = var.dns_name
  tags        = var.tags

  # Optional: the role a GitHub Actions workflow assumes to publish the site.
  github_org          = var.github_org
  github_repositories = var.github_repositories
}
