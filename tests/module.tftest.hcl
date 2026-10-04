mock_provider "cloudflare" {}

variables {
  account_id = "0123456789abcdef0123456789abcdef"
  domains = {
    "go.example.com" = {
      zone_name      = "example.com"
      index_redirect = "https://github.com/example"
      roots = {
        foo = {
          repository = "https://github.com/example/foo"
        }
        "tools/bar" = {
          repository = "https://git.example.com/bar"
          redirect   = "https://git.example.com/bar/about"
          source = {
            home      = "https://git.example.com/bar"
            directory = "https://git.example.com/bar/tree/main{/dir}"
            file      = "https://git.example.com/bar/blob/main{/dir}/{file}#L{line}"
          }
        }
        proxied = {
          repository = "https://proxy.example.com"
          vcs        = "mod"
        }
      }
    }
    "example.org" = {
      zone_id = "fedcba9876543210fedcba9876543210"
      roots = {
        "" = {
          repository = "https://hg.example.org/root"
          vcs        = "hg"
        }
      }
    }
  }
}

run "worker_config" {
  command = plan

  assert {
    condition     = cloudflare_worker.this.name == "go-vanity"
    error_message = "Default worker name not used."
  }

  assert {
    condition = jsondecode(cloudflare_worker_version.this.bindings[0].json) == {
      redirect_status = 302
      hosts = {
        "go.example.com" = {
          index = "https://github.com/example"
          roots = {
            foo = {
              vcs        = "git"
              repository = "https://github.com/example/foo"
              redirect   = "https://github.com/example/foo"
              source     = null
            }
            "tools/bar" = {
              vcs        = "git"
              repository = "https://git.example.com/bar"
              redirect   = "https://git.example.com/bar/about"
              source = {
                home      = "https://git.example.com/bar"
                directory = "https://git.example.com/bar/tree/main{/dir}"
                file      = "https://git.example.com/bar/blob/main{/dir}/{file}#L{line}"
              }
            }
            proxied = {
              vcs        = "mod"
              repository = "https://proxy.example.com"
              redirect   = null
              source     = null
            }
          }
        }
        "example.org" = {
          index = null
          roots = {
            "" = {
              vcs        = "hg"
              repository = "https://hg.example.org/root"
              redirect   = "https://hg.example.org/root"
              source     = null
            }
          }
        }
      }
    }
    error_message = "Worker config doesn't match the domains variable."
  }

  assert {
    condition = output.import_roots == {
      "go.example.com/foo"       = "https://github.com/example/foo"
      "go.example.com/tools/bar" = "https://git.example.com/bar"
      "go.example.com/proxied"   = "https://proxy.example.com"
      "example.org"              = "https://hg.example.org/root"
    }
    error_message = "import_roots output is wrong."
  }
}

run "worker_version_and_deployment" {
  command = plan

  assert {
    condition = (
      cloudflare_worker_version.this.main_module == "index.js" &&
      cloudflare_worker_version.this.compatibility_date == "2026-09-01" &&
      length(cloudflare_worker_version.this.modules) == 1 &&
      one(cloudflare_worker_version.this.modules).name == "index.js" &&
      one(cloudflare_worker_version.this.modules).content_type == "application/javascript+module"
    )
    error_message = "Worker version doesn't upload worker/index.js as its main module."
  }

  assert {
    condition = (
      cloudflare_workers_deployment.this.strategy == "percentage" &&
      length(cloudflare_workers_deployment.this.versions) == 1 &&
      cloudflare_workers_deployment.this.versions[0].percentage == 100
    )
    error_message = "Deployment should send all traffic to one version."
  }
}

run "workers_dev_disabled_by_default" {
  command = plan

  assert {
    condition = (
      cloudflare_worker.this.subdomain.enabled == false &&
      cloudflare_worker.this.subdomain.previews_enabled == false
    )
    error_message = "workers.dev and preview URLs should be disabled by default."
  }
}

run "workers_dev_disabled_when_null" {
  command = plan

  variables {
    workers_dev_subdomain = null
  }

  assert {
    condition = (
      cloudflare_worker.this.subdomain.enabled == false &&
      cloudflare_worker.this.subdomain.previews_enabled == false
    )
    error_message = "A null workers_dev_subdomain should fall back to the disabled default."
  }
}

run "worker_settings" {
  command = plan

  variables {
    compatibility_date    = "2026-01-15"
    compatibility_flags   = ["nodejs_compat"]
    limits                = { cpu_ms = 50 }
    logpush               = true
    observability         = { enabled = true, logs = { enabled = true, invocation_logs = false } }
    workers_dev_subdomain = { enabled = true }
    tags                  = ["go"]
    tail_consumers        = ["log-sink"]
  }

  assert {
    condition = (
      cloudflare_worker.this.logpush == true &&
      cloudflare_worker.this.observability.enabled == true &&
      cloudflare_worker.this.observability.logs.invocation_logs == false &&
      cloudflare_worker.this.subdomain.enabled == true &&
      cloudflare_worker.this.subdomain.previews_enabled == false &&
      cloudflare_worker.this.tags == toset(["go"]) &&
      [for consumer in cloudflare_worker.this.tail_consumers : consumer.name] == ["log-sink"]
    )
    error_message = "Worker settings aren't passed to cloudflare_worker."
  }

  assert {
    condition = (
      cloudflare_worker_version.this.compatibility_date == "2026-01-15" &&
      cloudflare_worker_version.this.compatibility_flags == toset(["nodejs_compat"]) &&
      cloudflare_worker_version.this.limits.cpu_ms == 50
    )
    error_message = "Worker settings aren't passed to cloudflare_worker_version."
  }
}

run "custom_domains" {
  command = plan

  assert {
    condition     = keys(cloudflare_workers_custom_domain.this) == ["example.org", "go.example.com"]
    error_message = "Expected one custom domain per domain."
  }

  assert {
    condition = (
      cloudflare_workers_custom_domain.this["go.example.com"].zone_name == "example.com" &&
      cloudflare_workers_custom_domain.this["example.org"].zone_id == "fedcba9876543210fedcba9876543210" &&
      cloudflare_workers_custom_domain.this["go.example.com"].service == "go-vanity"
    )
    error_message = "Custom domains aren't attached to the right zones and Worker."
  }
}

run "redirect_options" {
  command = plan

  variables {
    default_redirect     = "pkg.go.dev"
    redirect_status_code = 301
  }

  assert {
    condition = (
      jsondecode(cloudflare_worker_version.this.bindings[0].json).redirect_status == 301 &&
      jsondecode(cloudflare_worker_version.this.bindings[0].json).hosts["go.example.com"].roots.foo.redirect == null &&
      jsondecode(cloudflare_worker_version.this.bindings[0].json).hosts["go.example.com"].roots["tools/bar"].redirect == "https://git.example.com/bar/about"
    )
    error_message = "pkg.go.dev default should only apply to roots without an explicit redirect."
  }
}

run "rejects_uppercase_hostname" {
  command = plan
  variables {
    domains = { "Go.Example.com" = { zone_name = "example.com", roots = {} } }
  }
  expect_failures = [var.domains]
}

run "rejects_both_zone_fields" {
  command = plan
  variables {
    domains = { "go.example.com" = { zone_name = "example.com", zone_id = "abc", roots = {} } }
  }
  expect_failures = [var.domains]
}

run "rejects_missing_zone" {
  command = plan
  variables {
    domains = { "go.example.com" = { roots = {} } }
  }
  expect_failures = [var.domains]
}

run "rejects_root_with_slashes" {
  command = plan
  variables {
    domains = {
      "go.example.com" = {
        zone_name = "example.com"
        roots     = { "/foo/" = { repository = "https://github.com/example/foo" } }
      }
    }
  }
  expect_failures = [var.domains]
}

run "rejects_unknown_vcs" {
  command = plan
  variables {
    domains = {
      "go.example.com" = {
        zone_name = "example.com"
        roots     = { foo = { repository = "https://github.com/example/foo", vcs = "cvs" } }
      }
    }
  }
  expect_failures = [var.domains]
}

run "rejects_repository_without_scheme" {
  command = plan
  variables {
    domains = {
      "go.example.com" = {
        zone_name = "example.com"
        roots     = { foo = { repository = "github.com/example/foo" } }
      }
    }
  }
  expect_failures = [var.domains]
}

run "rejects_non_http_redirect" {
  command = plan
  variables {
    domains = {
      "go.example.com" = {
        zone_name = "example.com"
        roots     = { foo = { repository = "https://github.com/example/foo", redirect = "ftp://example.com" } }
      }
    }
  }
  expect_failures = [var.domains]
}

run "rejects_bad_compatibility_date" {
  command = plan
  variables {
    compatibility_date = "September 2026"
  }
  expect_failures = [var.compatibility_date]
}

run "rejects_bad_redirect_status" {
  command = plan
  variables {
    redirect_status_code = 200
  }
  expect_failures = [var.redirect_status_code]
}
