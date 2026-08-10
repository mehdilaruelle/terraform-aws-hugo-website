# A complete deployment: S3 origin, CloudFront, ACM certificate, Route 53
# records, and the GitHub OIDC role a workflow uses to publish the site.
#
# One provider, and no `providers` argument on the module block. The certificate
# still has to be issued in us-east-1, but the module asks for that per resource
# rather than through a second provider you would have to configure and pass.

provider "aws" {
  region = var.region

  default_tags {
    tags = var.tags
  }
}

module "hugo_blog" {
  # Published: source = "mehdilaruelle/hugo-blog/aws"
  #            version = "~> 1.0"
  source = "../../"

  bucket_name = var.bucket_name
  dns_name    = var.dns_name
  tags        = var.tags

  # Optional: the role a GitHub Actions workflow assumes to publish the site.
  github_org          = var.github_org
  github_repositories = var.github_repositories
}
