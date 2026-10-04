# Releasing

New versions reach the module registries through Git tags. The Terraform
Registry is notified by a webhook and usually lists a new tag within a minute.
The OpenTofu Registry checks for new tags every 15 minutes. Both take the
module straight from the tagged commit, so there's nothing to build or upload.

## Publishing a version

1. Make sure the [Test workflow][test] passes on `main`.
2. [Draft a new release][new-release] targeting `main`, with a new tag named
   for the version, such as `v1.2.3`. Follow [semantic versioning][semver]:
   bump the major version for changes that break existing configurations, such
   as renamed or removed variables.
3. Select **Generate release notes**, edit them as needed, and publish the
   release.

Publishing the release pushes the tag, which starts the [Release
workflow][release]. It:

- checks that the tag looks like `v1.2.3`;
- runs the tests again on the tagged commit;
- waits until each registry lists the new version, then installs it from
  there with `terraform init` or `tofu init`. Allow up to an hour for the
  OpenTofu Registry.

If the Terraform Registry job times out, open the module on the registry and
choose **Manage Module › Resync Module**, then re-run the job.

If the tests fail after a registry has picked up the version, publish a fixed
version rather than moving the tag: anyone who already installed the broken
version keeps it.

## One-time setup

Both registries need to be told about the module once. After that, every new
tag is picked up automatically.

1. **Protect `main`.** In the repository's branch rules, require the Test
   workflow's checks to pass before merging, so releases are cut from tested
   commits.
2. **Publish the first release** as described above. The Terraform Registry
   only accepts repositories that already have a version tag.
3. **Terraform Registry:** on [registry.terraform.io][tf-registry], select
   **Upload**, sign in with GitHub, select this repository and select
   **Publish Module**. This sets up the webhook that announces new tags.
4. **OpenTofu Registry:** submit the repository with the [Submit new
   Module][tofu-submit] issue form. The OpenTofu team reviews submissions, so
   this can take a while.

The Release workflow for the first release fails if a registry doesn't list
the version before the job times out: after 30 minutes for the Terraform
Registry, and 2 hours for the OpenTofu Registry. Once the module appears on a
registry, re-run the failed job from the workflow run's page.

[test]: https://github.com/ari-becker/terraform-cloudflare-go-vanity/actions/workflows/test.yml
[release]: .github/workflows/release.yml
[new-release]: https://github.com/ari-becker/terraform-cloudflare-go-vanity/releases/new
[semver]: https://semver.org/
[tf-registry]: https://registry.terraform.io/
[tofu-submit]: https://github.com/opentofu/registry/issues/new?labels=module%2Csubmission&template=module.yml&title=Module%3A+
