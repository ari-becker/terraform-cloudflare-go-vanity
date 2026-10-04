locals {
  worker_file = "${path.module}/worker/index.js"

  # Passed to the Worker as its VANITY_CONFIG binding. worker/index.js
  # documents the shape.
  worker_config = {
    redirect_status = var.redirect_status_code
    hosts = {
      for hostname, domain in var.domains : hostname => {
        index = domain.index_redirect
        roots = {
          for path, root in domain.roots : path => {
            vcs        = root.vcs
            repository = root.repository
            # null tells the Worker to redirect to pkg.go.dev.
            redirect = (
              root.redirect != null ? root.redirect :
              var.default_redirect == "repository" && root.vcs != "mod" ? root.repository :
              null
            )
            source = root.source
          }
        }
      }
    }
  }
}

resource "cloudflare_worker" "this" {
  account_id     = var.account_id
  name           = var.worker_name
  logpush        = var.logpush
  observability  = var.observability
  subdomain      = var.workers_dev_subdomain
  tags           = var.tags
  tail_consumers = var.tail_consumers == null ? null : [for name in var.tail_consumers : { name = name }]
}

# Versions are immutable: any change to the code or configuration creates a
# new version, which the deployment below then sends all traffic to.
resource "cloudflare_worker_version" "this" {
  account_id          = var.account_id
  worker_id           = cloudflare_worker.this.id
  compatibility_date  = var.compatibility_date
  compatibility_flags = var.compatibility_flags
  limits              = var.limits
  main_module         = "index.js"

  modules = [{
    name         = "index.js"
    content_type = "application/javascript+module"
    content_file = local.worker_file
  }]

  bindings = [{
    name = "VANITY_CONFIG"
    type = "json"
    json = jsonencode(local.worker_config)
  }]
}

resource "cloudflare_workers_deployment" "this" {
  account_id  = var.account_id
  script_name = cloudflare_worker.this.name
  strategy    = "percentage"

  versions = [{
    version_id = cloudflare_worker_version.this.id
    percentage = 100
  }]
}

resource "cloudflare_workers_custom_domain" "this" {
  for_each = var.domains

  account_id = var.account_id
  hostname   = each.key
  service    = cloudflare_worker.this.name
  zone_id    = each.value.zone_id
  zone_name  = each.value.zone_name

  # Attach hostnames only once a version is serving traffic.
  depends_on = [cloudflare_workers_deployment.this]
}
