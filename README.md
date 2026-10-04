# terraform-cloudflare-go-vanity

[![Test](https://github.com/ari-becker/terraform-cloudflare-go-vanity/actions/workflows/test.yml/badge.svg)](https://github.com/ari-becker/terraform-cloudflare-go-vanity/actions/workflows/test.yml)

An OpenTofu module that serves Go vanity import paths, such as
`go.example.com/foo`, from a Cloudflare Worker.

Vanity import paths name your domain instead of your code host. Moving a
repository from GitHub to somewhere else then means changing one line in this
module, not rewriting every import statement that uses it.

This module is based on Iain Cambridge's article
[Don't couple your Go code to GitHub][article], which makes the case for
vanity import paths and serves them with nginx. This module does the same job
with a Cloudflare Worker instead of a server.

## How it works

The module manages the Worker the way Cloudflare
[recommends for Terraform][iac]: a `cloudflare_worker`, a
`cloudflare_worker_version` holding the code and configuration, and a
`cloudflare_workers_deployment` that sends all traffic to that version. Any
change to the configuration creates a new version and deploys it.

Each of your hostnames is attached to the Worker as a
[Workers Custom Domain][custom-domains], so Cloudflare creates the DNS records
and TLS certificates. The Worker responds as follows:

| Request                          | Response                                                                                       |
| -------------------------------- | ---------------------------------------------------------------------------------------------- |
| `GET /foo/bar?go-get=1` (`go`)   | `go-import` meta tag (plus `go-source`, if configured) for `foo`, the longest matching root    |
| `GET /foo/bar` (browser)         | Redirect to the root's `redirect`, its repository, or `pkg.go.dev/go.example.com/foo/bar`     |
| `GET /` (browser)                | Redirect to the domain's `index_redirect`, if set                                              |
| Anything else                    | 404                                                                                            |

A root serves every import path below it, so packages inside a module resolve
without any extra configuration. Roots match whole path segments: `foo` serves
`foo/bar` but not `foobar`.

## Usage

```hcl
provider "cloudflare" {} # Reads CLOUDFLARE_API_TOKEN.

module "go_vanity" {
  source  = "ari-becker/go-vanity/cloudflare"
  version = "~> 1.0"

  account_id = "0123456789abcdef0123456789abcdef"

  domains = {
    "go.example.com" = {
      zone_name      = "example.com"
      index_redirect = "https://github.com/example"
      roots = {
        foo         = { repository = "https://github.com/example/foo" }
        "tools/bar" = { repository = "https://gitlab.com/example/bar" }
      }
    }
  }
}
```

With this configuration, `go get go.example.com/foo/sub/pkg` clones
`https://github.com/example/foo`, and `go.example.com/tools/bar` clones from
GitLab. A full example is in [`examples/basic`](examples/basic).

The module is published on both the [OpenTofu Registry][tofu-registry] and the
[Terraform Registry][tf-registry], so the same `source` works with either tool.

### Requirements

- OpenTofu 1.8 or later, or Terraform 1.8 or later.
- The `cloudflare/cloudflare` provider, version `~> 5.26`.
- CI tests the oldest and newest versions of each.
- Each hostname's zone must be active on Cloudflare, in the same account as the
  Worker. Don't create DNS records for the hostnames yourself: Cloudflare
  creates them, and won't attach a hostname that already has a CNAME record.
- An API token with these [permissions][permissions]:
  - Workers **Admin** on the account. Creating a Worker requires it.
  - **Zone › Workers Routes › Write** on every zone you use.

## Inputs

| Name                   | Type        | Default        | Description                                                                                         |
| ---------------------- | ----------- | -------------- | --------------------------------------------------------------------------------------------------- |
| `account_id`           | string      |                | Cloudflare account ID.                                                                              |
| `domains`              | map(object) |                | Hostnames to serve, keyed by hostname. See below.                                                   |
| `worker_name`          | string      | `"go-vanity"`  | Name of the Worker.                                                                                 |
| `default_redirect`     | string      | `"repository"` | Where browsers go for roots without `redirect`: `"repository"` or `"pkg.go.dev"`.                   |
| `redirect_status_code` | number      | `302`          | Status for browser redirects: 301, 302, 303, 307 or 308.                                             |

Each entry in `domains` has these fields:

| Field            | Required | Description                                                                                                       |
| ---------------- | -------- | ----------------------------------------------------------------------------------------------------------------- |
| `zone_id`        | One of   | ID of the zone containing the hostname.                                                                           |
| `zone_name`      | One of   | Name of the zone containing the hostname, such as `example.com`.                                                  |
| `index_redirect` | No       | URL to send browsers that visit `/`.                                                                              |
| `roots`          | Yes      | Import roots, keyed by path below the hostname without surrounding slashes. `""` makes the hostname itself a root. |

Each entry in `roots` has these fields:

| Field        | Required | Description                                                                                          |
| ------------ | -------- | ---------------------------------------------------------------------------------------------------- |
| `repository` | Yes      | Repository URL given to the `go` command, such as `https://github.com/example/foo`.                  |
| `vcs`        | No       | `git` (default), `hg`, `svn`, `bzr`, `fossil`, or `mod` for a module proxy.                         |
| `redirect`   | No       | URL to send browsers to. Overrides `default_redirect`.                                               |
| `source`     | No       | [`go-source`][go-source] templates: `home`, `directory` and `file`. See [Source links](#source-links). |

Roots with `vcs = "mod"` send browsers to pkg.go.dev unless `redirect` is set,
since their repository is a module proxy rather than a page to read.

### Worker settings

These inputs are optional and passed straight to the Worker resources. Those
that default to `null` keep the provider's default.

| Name                    | Type        | Default        | Passed to                                                    |
| ----------------------- | ----------- | -------------- | ------------------------------------------------------------ |
| `compatibility_date`    | string      | `"2026-09-01"` | `cloudflare_worker_version.compatibility_date`               |
| `compatibility_flags`   | set(string) | `null`         | `cloudflare_worker_version.compatibility_flags`              |
| `limits`                | object      | `null`         | `cloudflare_worker_version.limits` (`cpu_ms`, `subrequests`) |
| `logpush`               | bool        | `null`         | `cloudflare_worker.logpush`                                  |
| `observability`         | object      | `null`         | `cloudflare_worker.observability`                            |
| `workers_dev_subdomain` | object      | both `false`   | `cloudflare_worker.subdomain` (`enabled`, `previews_enabled`) |
| `tags`                  | set(string) | `null`         | `cloudflare_worker.tags`                                     |
| `tail_consumers`        | set(string) | `null`         | `cloudflare_worker.tail_consumers`, as Worker names          |

The Worker's `*.workers.dev` URL and preview URLs are disabled by default,
since the Worker only serves the hostnames in `domains` and returns 404
anywhere else. Set `enabled` or `previews_enabled` to `true` to turn either on.

`observability` takes the same fields as the provider's attribute:
`enabled`, `head_sampling_rate`, and the `logs`, `traces` and `issues` blocks.
For example, to keep Workers Logs for debugging `go get` failures:

```hcl
observability = {
  enabled = true
  logs    = { enabled = true, invocation_logs = true }
}
```

## Outputs

| Name                | Description                                           |
| ------------------- | ----------------------------------------------------- |
| `worker_id`         | ID of the Worker.                                     |
| `worker_name`       | Name of the Worker.                                   |
| `version_id`        | ID of the Worker version the module deployed.         |
| `import_roots`      | Every import root served, mapped to its repository.   |
| `custom_domain_ids` | IDs of the Workers Custom Domains, keyed by hostname. |

## Choosing roots

Make each root the module path declared in the repository's `go.mod`, without
the hostname. For a repository whose `go.mod` says
`module go.example.com/tools/bar`, use the root `tools/bar`.

Roots can be nested when they live in different repositories. For example,
`tools` and `tools/bar` can point at different repositories, and the longest
match wins.

## Moving a repository

Change the root's `repository` and apply. Import paths don't change. The Go
module mirror (`proxy.golang.org`) keeps serving versions it has already
cached, and new versions are fetched from the new repository.

## Source links

pkg.go.dev builds source links itself when the repository is on a forge it
recognizes, such as GitHub, GitLab or Bitbucket, and ignores `go-source` in
that case. Set `source` only for other forges, for example a self-hosted Gitea
or Forgejo:

```hcl
source = {
  home      = "https://git.example.com/foo"
  directory = "https://git.example.com/foo/src/branch/main{/dir}"
  file      = "https://git.example.com/foo/src/branch/main{/dir}/{file}#L{line}"
}
```

## Cost

The Workers Free plan includes 100,000 requests a day. A vanity domain gets
far fewer than that: by default the `go` command downloads modules through
`proxy.golang.org`, which caches them, so most `go get`s never reach your
domain.

## Development

The Worker is a single dependency-free file, [`worker/index.js`](worker/index.js).
The module passes it the configuration as a JSON binding named `VANITY_CONFIG`.

```sh
tofu test                     # module tests, using a mocked provider
(cd worker && node --test)    # Worker tests; tested with Node.js 24
```

The [Test workflow](.github/workflows/test.yml) runs these on every push and
pull request, and weekly to catch new provider releases. It runs the module
tests with the oldest and newest supported versions of OpenTofu, Terraform and
the Cloudflare provider. To publish a new version, see
[RELEASING.md](RELEASING.md).

## License

[MIT](LICENSE)

[article]: https://iain.rocks/blog/dont-couple-your-go-code-to-github
[custom-domains]: https://developers.cloudflare.com/workers/configuration/routing/custom-domains/
[iac]: https://developers.cloudflare.com/workers/platform/infrastructure-as-code/#terraform
[permissions]: https://developers.cloudflare.com/workers/authorization/workers/
[go-source]: https://github.com/golang/gddo/wiki/Source-Code-Links
[tf-registry]: https://registry.terraform.io/modules/ari-becker/go-vanity/cloudflare
[tofu-registry]: https://search.opentofu.org/module/ari-becker/go-vanity/cloudflare/latest
