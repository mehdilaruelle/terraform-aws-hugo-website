# Deploy your Hugo website on AWS with Terraform 

This project is aim to deploy the infrastructure needed by [Hugo](https://gohugo.io/) on [AWS](https://aws.amazon.com/).
This infrastructure force the usage of HTTPS with a specific domain name.

You can read [the dedicated blog post on this on my blog](https://mehdilaruelle.com/posts/2022/08/deploy-your-hugo-site-on-aws-with-terraform/).

## Usage

```hcl
provider "aws" {
  region = "eu-west-3"
}

module "hugo_blog" {
  source  = "mehdilaruelle/hugo-website/aws"
  version = "~> 1.0"

  bucket_name = "my-hugo-bucket"
  dns_name    = "example.com"
}
```

One provider, and nothing to pass. The module configures none of its own — a
module that does cannot be used with `count`, `for_each` or `depends_on`, and
cannot be removed cleanly, because nothing is left able to destroy what it made.

CloudFront accepts ACM certificates from **us-east-1** and nowhere else. The
module asks for that region on the certificate itself, which the AWS provider
has allowed per resource since v6, so there is no second provider for you to
configure and pass.

A working configuration lives in [`examples/complete`](examples/complete), which
is also what CI validates.

## Prerequisites

You need to a domain name (for HTTPS).

### Setting up the domain name

Our Terraform does not create the hosted zone (because it depends on where your domain name is located).
> The hosted zone is not required. It is possible to not use Amazon Route 53 for [configuring Amazon CloudFront](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/CNAMEs.html)
and [to create the certificate](https://docs.aws.amazon.com/acm/latest/userguide/gs-acm-request-public.html). The action will require more effort and manual action.

**TO DO**: [Create the public hosted zone on Amazon Route 53](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/migrate-dns-domain-in-use.html)

## Solution architecture

![AWS Cloudfront website static](.docs/hugo_aws_website.png)

The Terraform deploys:
- A **S3 bucket**: this S3 bucket will contain our static website.
The content thereof is private and accessible only by CloudFront via an [Origin Access Control (OAC)](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html).
In other words, our users will have to go through Amazon CloudFront and not directly on Amazon S3 to access to our website.
ACLs are disabled, public access is blocked and objects are encrypted at rest with SSE-S3.
- A **CloudFront distribution**: will allow us to use HTTPS on our website, to use a custom domain name, to set up a
[Content Delivery Network (CDN)](https://aws.amazon.com/cloudfront/) and
enhance security through the [AWS Shield service](https://aws.amazon.com/shield).
It serves over HTTP/2 and HTTP/3, compresses responses, and applies the managed
`SecurityHeadersPolicy` (HSTS, `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`).
- A **Route 53 record**: an `A` and an `AAAA` Alias will be created for our CloudFront distribution
- A **CloudFront function**: is used to rewrite URL to append `index.html` to the end if not exist.  
- A **AWS Certificate Manager**: Create the public certificate on ACM in N. Virginia (us-east-1) for CloudFront distribution.

A missing page is served as Hugo's `/404.html` with an HTTP 404 status.

### Access logs

S3 server access logging is off. Turn it on by naming a bucket to receive the
logs:

```hcl
access_log_bucket = "my-log-bucket"
access_log_prefix = "hugo/"   # optional, defaults to s3-access-logs/
```

The module does not create that bucket. A log destination needs its own
ownership and delivery permissions, and it is usually shared across several
sources — creating one per site here would be the wrong shape. It has to exist
already, accept log delivery, and sit in the same region as the site bucket.

Worth knowing before turning it on: visitors reach the site through CloudFront,
which reads from S3 only on a cache miss. These logs therefore record
CloudFront fetching origin objects, not people reading pages. For traffic,
CloudFront has its own access logging.

### Invalidating the CDN after a deploy

CloudFront caches for 24 hours by default, so uploading a new build to S3 does not
put it in front of visitors: they keep getting the previous version until the TTL
expires. The IAM role already grants `cloudfront:CreateInvalidation`, so all that is
needed is to tell Hugo which distribution to invalidate.

```bash
$ terraform output cloudfront_distribution_id
```

Put it in the Hugo site's deployment target, then deploy with `hugo deploy --invalidateCDN`:

```toml
[[deployment.targets]]
  name                     = "aws"
  URL                      = "s3://your-bucket?region=eu-west-3"
  cloudFrontDistributionID = "E1234567890ABC"
```

## How is it working ?

Before starting, you need to check if:
- You have created `the public hosted zone on Amazon Route 53`

If so, you can now be able to deploy your infrastructure.

### Deployment

Write a configuration that calls the module — see [Usage](#usage) — supplying at
least:

- `bucket_name`, the S3 bucket that will hold the built site
- `dns_name`, the domain served through Route 53

Then, with your AWS credentials in place:

```bash
$ terraform init
$ terraform plan
$ terraform apply
```

The region comes from your own `provider` block rather than from a module
variable, which is what lets one configuration deploy several sites in different
regions.

### **OPTIONAL** - Create a role for GitHub Action

This stack can create a role for GitHub Action with the Action [configure-aws-credentials
](https://github.com/aws-actions/configure-aws-credentials#configure-aws-credentials-for-github-actions).

To use this option, pass the module the following:
- `github_org` is the GitHub Organization name where your repository `hugo blog` is hosted in GitHub.
  In our case, should be your (in my case `mehdilaruelle`).
- `github_repositories` is a list of GitHub repositories name to allow to assume the Web Identity role.
  In our case, the repository holding the Hugo content (in my case `["blog_hugo"]`).

By default the role can only be assumed from the `main` branch of those repositories.
If you deploy from another branch, or from tags, set `github_subjects` accordingly:

```hcl
github_subjects = ["ref:refs/heads/production"] # or ["*"] for every ref
```

You can also configure some optional variable based on your need like `iam_role_name`, `client_id_list`, etc (see below to have an exhaustive list).

Apply, then read the ARN from the module's output:

```bash
$ terraform output aws_role_arn
```

To learn more about it, [take a look into the blog post](https://mehdilaruelle.com/posts/2023/10/deploy-your-hugo-site-on-aws-with-terraform-v2/#setting-up-temporary-aws-credentials)

### Upgrading an existing deployment

**This repository is now a module rather than a stack you apply directly.** If
you were cloning it and running `terraform apply` inside it, that no longer
works: the `provider` blocks have moved out, so the configuration has nothing to
authenticate with. Point a configuration of your own at it instead — see [Usage](#usage).

Every address changes: `aws_s3_bucket.hugo` becomes `module.<name>.aws_s3_bucket.hugo`,
and so on for all sixteen resources. Apply without telling Terraform that, and it
plans to destroy and recreate the lot — the bucket refuses (`force_destroy` is
false), and the distribution takes about fifteen minutes to come back.

Declare the moves in your root instead. They are reviewable in the plan, unlike
`terraform state mv`, and they survive being run twice:

```hcl
moved {
  from = aws_s3_bucket.hugo
  to   = module.website.aws_s3_bucket.hugo
}
```

One block per resource. Back the state up first (`terraform state pull > backup.tfstate`).

What you are reading the plan for is **no destroys and no recreations** — not an
empty plan. Some in-place changes are expected on this upgrade, and they are
listed below; read them, then apply. Anything proposing to replace a resource
means an address has not landed, and applying would rebuild it for real.

The `region` variable is gone with the provider blocks. Set the region on your
own `provider "aws"` block. The certificate pins itself to us-east-1 regardless,
as CloudFront requires.


The module needs the AWS provider `~> 6.0` and Terraform `>= 1.5`.

The version is yours to pin, not the module's: Terraform reads the **root** module's
`.terraform.lock.hcl` and ignores the one in a child. The file committed here governs
this repository's own checks and nothing else. In your configuration, run
`terraform init`, commit the lock file it writes, and add checksums for any other
platform your CI runs on with `terraform providers lock -platform=<os>_<arch>`.

Read the plan before applying: a few things change in place.

- `aws_s3_bucket_acl` is gone. Buckets created since April 2023 have ACLs disabled and
  that resource fails on them with `AccessControlListNotSupported`; `BucketOwnerEnforced`
  is now set explicitly instead. Removing it from state is a no-op on AWS' side.
- The apex record becomes `aws_route53_record.route53_record["A"]`. A `moved` block keeps
  it in state, so DNS is not dropped and recreated — but only if you apply, not import.
- The cache behaviour switches from the deprecated `forwarded_values` to the managed
  `CachingOptimized` policy. Behaviour is the same (no cookies, no query strings) except
  that TTLs now follow the origin's `Cache-Control` instead of a fixed 24 hours.
- A missing page used to return the home page with HTTP 200. It now returns `/404.html`
  with HTTP 404, which is what search engines should see.
- The GitHub role is restricted to the `main` branch (see `github_subjects` above). If
  you deploy from elsewhere, set that variable before applying or the deploy will start
  failing with `Not authorized to perform sts:AssumeRoleWithWebIdentity`.

### Cleanup

The bucket is created with `force_destroy = false`, so Terraform will not delete it
while the site is still in it. Empty it first, then destroy:

```bash
$ aws s3 rm s3://<bucket> --recursive
$ terraform destroy
```

Skip the first line and the destroy fails part way through with `BucketNotEmpty`,
leaving the rest of the stack half removed.

After that, remove by hand:
- the public hosted zone on Amazon Route 53

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.57.1 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_acm_certificate.hugo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate) | resource |
| [aws_acm_certificate_validation.hugo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation) | resource |
| [aws_cloudfront_distribution.s3_distribution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution) | resource |
| [aws_cloudfront_function.redirect](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_function) | resource |
| [aws_cloudfront_origin_access_control.hugo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_control) | resource |
| [aws_iam_openid_connect_provider.github](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_policy.github_hugo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.github](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_route53_record.hugo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.route53_record](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_s3_bucket.hugo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_logging.hugo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_logging) | resource |
| [aws_s3_bucket_ownership_controls.hugo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.hugo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.hugo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.hugo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_cloudfront_cache_policy.caching_optimized](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/cloudfront_cache_policy) | data source |
| [aws_cloudfront_response_headers_policy.security_headers](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/cloudfront_response_headers_policy) | data source |
| [aws_iam_policy_document.assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.hugo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.s3_bucket_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_route53_zone.hugo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_access_log_bucket"></a> [access\_log\_bucket](#input\_access\_log\_bucket) | Bucket that receives S3 server access logs for the site bucket. Empty, the default, leaves logging off. The bucket must already exist, allow log delivery, and sit in the same region. | `string` | `""` | no |
| <a name="input_access_log_prefix"></a> [access\_log\_prefix](#input\_access\_log\_prefix) | Key prefix for the access logs. Only read when access_log_bucket is set. Ends with a slash, or the prefix runs into the object name. | `string` | `"s3-access-logs/"` | no |
| <a name="input_bucket_name"></a> [bucket\_name](#input\_bucket\_name) | The S3 bucket name to store the HUGO website. | `string` | n/a | yes |
| <a name="input_client_id_list"></a> [client\_id\_list](#input\_client\_id\_list) | A list of client IDs (also known as audiences). | `list(string)` | <pre>[<br/>  "sts.amazonaws.com"<br/>]</pre> | no |
| <a name="input_cloudfront_price_class"></a> [cloudfront\_price\_class](#input\_cloudfront\_price\_class) | The price class to use for CloudFront distribution. | `string` | `"PriceClass_100"` | no |
| <a name="input_dns_name"></a> [dns\_name](#input\_dns\_name) | The DNS name to use for your HUGO website. | `string` | n/a | yes |
| <a name="input_github_org"></a> [github\_org](#input\_github\_org) | GitHub organisation name. | `string` | `""` | no |
| <a name="input_github_repositories"></a> [github\_repositories](#input\_github\_repositories) | List of GitHub repository names. | `list(string)` | `[]` | no |
| <a name="input_github_subjects"></a> [github\_subjects](#input\_github\_subjects) | GitHub `sub` claim suffixes allowed to assume the role, appended to `repo:<org>/<repo>:`. Use `["*"]` to allow every ref. | `list(string)` | <pre>[<br/>  "ref:refs/heads/main"<br/>]</pre> | no |
| <a name="input_iam_role_name"></a> [iam\_role\_name](#input\_iam\_role\_name) | Friendly name of the role. If omitted, Terraform will assign a random, unique name. | `string` | `"GitHubOIDCRole"` | no |
| <a name="input_max_session_duration"></a> [max\_session\_duration](#input\_max\_session\_duration) | Maximum session duration in seconds. | `number` | `3600` | no |
| <a name="input_oidc_url"></a> [oidc\_url](#input\_oidc\_url) | The URL of the identity provider. Corresponds to the iss claim. | `string` | `"https://token.actions.githubusercontent.com"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to taggable resources created by this module. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aws_role_arn"></a> [aws\_role\_arn](#output\_aws\_role\_arn) | The AWS role ARN to use in your GitHub Actions to fetch dynamic creds from AWS. |
| <a name="output_cloudfront_distribution_id"></a> [cloudfront\_distribution\_id](#output\_cloudfront\_distribution\_id) | The CloudFront distribution ID, for `cloudFrontDistributionID` in Hugo's deployment target so `hugo deploy --invalidateCDN` can clear the cache. |
| <a name="output_route53_ns_records"></a> [route53\_ns\_records](#output\_route53\_ns\_records) | List of Name Server (NS) records to add to your main DNS zone (delegation). |
<!-- END_TF_DOCS -->

## Contact

You see something wrong ? You want extra information or more ?

Contact me: 3exr269ch@mozmail.com
