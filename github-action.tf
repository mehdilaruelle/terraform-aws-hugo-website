locals {
  # Enable the AWS OIDC authentication with Github only if var.github_repositories & var.github_org is set
  enable_aws_github_oidc = anytrue([length(var.github_repositories) == 0, var.github_org == ""]) ? 0 : 1
}
data "aws_iam_policy_document" "assume_role" {
  count = local.enable_aws_github_oidc

  statement {
    sid = "1"

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [one(aws_iam_openid_connect_provider.github[*].arn)]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"

      values = flatten([
        for repo in var.github_repositories : [
          for subject in var.github_subjects : "repo:${var.github_org}/${repo}:${subject}"
        ]
      ])
    }

    # Without this, any OIDC token issued by GitHub for any repository can be
    # presented; the sub condition above is the only thing scoping the role.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = var.client_id_list
    }
  }
}

# No thumbprint_list: since 2023 AWS validates the well-known GitHub OIDC
# endpoint against its own trust store and ignores whatever is pinned here. The
# value this stack used to hardcode was a CA fingerprint that has since rotated.
resource "aws_iam_openid_connect_provider" "github" {
  count = local.enable_aws_github_oidc

  url            = var.oidc_url
  client_id_list = var.client_id_list
}

resource "aws_iam_role" "github" {
  count = local.enable_aws_github_oidc

  name                 = var.iam_role_name
  assume_role_policy   = one(data.aws_iam_policy_document.assume_role[*].json)
  max_session_duration = var.max_session_duration
}

resource "aws_iam_role_policy_attachment" "policy" {
  count = local.enable_aws_github_oidc

  role       = one(aws_iam_role.github[*].id)
  policy_arn = one(aws_iam_policy.github_hugo[*].arn)
}

resource "aws_iam_policy" "github_hugo" {
  count = local.enable_aws_github_oidc

  name = var.iam_role_name

  policy = one(data.aws_iam_policy_document.hugo[*].json)
}

data "aws_iam_policy_document" "hugo" {
  count = local.enable_aws_github_oidc

  statement {
    actions = [
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.hugo.arn
    ]
  }
  statement {
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
    resources = [
      "${aws_s3_bucket.hugo.arn}/*"
    ]
  }
  statement {
    actions = [
      "cloudfront:CreateInvalidation"
    ]
    resources = [
      aws_cloudfront_distribution.s3_distribution.arn
    ]
  }
}
