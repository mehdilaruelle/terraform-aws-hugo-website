terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"

      # A module meant to be called by others must not configure providers of
      # its own: doing so makes it incompatible with count, for_each and
      # depends_on, and leaves nothing able to destroy its resources once the
      # module block is removed.
      #
      # aws.aws_cloudfront has to reach us-east-1, because CloudFront only
      # accepts ACM certificates issued there. The caller supplies both, which
      # is also what lets a caller deploy several of these side by side.
      configuration_aliases = [aws, aws.aws_cloudfront]
    }
  }
}
