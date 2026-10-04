variable "account_id" {
  description = "ID of the Cloudflare account that owns the Worker."
  type        = string
}

variable "worker_name" {
  description = "Name of the Worker."
  type        = string
  default     = "go-vanity"
}

variable "domains" {
  description = <<-EOT
    Hostnames to serve import paths from, keyed by hostname (for example
    "go.example.com"). Each hostname is attached to the Worker as a Workers
    Custom Domain, so it must be in an active zone in the account. Cloudflare
    creates its DNS record and certificate, and won't attach a hostname that
    already has a CNAME record.

    - zone_id, zone_name: the zone containing the hostname. Set exactly one.
    - index_redirect: URL to send browsers that visit "/". Without it, "/"
      returns 404 unless "" is a root.
    - roots: import roots under the hostname, keyed by path without leading or
      trailing slashes, such as "foo" or "tools/foo". "" makes the hostname
      itself an import root. A root serves every import path below it.
      - repository: repository URL given to the go command.
      - vcs: one of bzr, fossil, git, hg, mod, svn. Defaults to git.
      - redirect: URL to send browsers to. Defaults per var.default_redirect.
      - source: go-source templates (home, directory, file). pkg.go.dev builds
        source links itself for well-known forges such as GitHub, GitLab and
        Bitbucket, so set this only for forges it doesn't recognize.
  EOT

  type = map(object({
    zone_id        = optional(string)
    zone_name      = optional(string)
    index_redirect = optional(string)
    roots = map(object({
      repository = string
      vcs        = optional(string, "git")
      redirect   = optional(string)
      source = optional(object({
        home      = string
        directory = string
        file      = string
      }))
    }))
  }))

  validation {
    condition     = length(var.domains) > 0
    error_message = "At least one domain is required."
  }

  validation {
    condition = alltrue([
      for hostname in keys(var.domains) :
      can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?$", hostname))
    ])
    error_message = "Domain keys must be lowercase hostnames such as \"go.example.com\"."
  }

  validation {
    condition = alltrue([
      for domain in values(var.domains) : (domain.zone_id == null) != (domain.zone_name == null)
    ])
    error_message = "Each domain must set exactly one of zone_id or zone_name."
  }

  validation {
    condition = alltrue([
      for domain in values(var.domains) :
      domain.index_redirect == null || can(regex("^https?://\\S+$", domain.index_redirect))
    ])
    error_message = "index_redirect must be an http(s) URL."
  }

  validation {
    condition = alltrue(flatten([
      for domain in values(var.domains) : [
        for path in keys(domain.roots) : can(regex("^([A-Za-z0-9._~-]+(/[A-Za-z0-9._~-]+)*)?$", path))
      ]
    ]))
    error_message = "Root keys must be paths without leading or trailing slashes, such as \"foo\" or \"tools/foo\", or \"\" for the hostname itself."
  }

  validation {
    condition = alltrue(flatten([
      for domain in values(var.domains) : [
        for root in values(domain.roots) : contains(["bzr", "fossil", "git", "hg", "mod", "svn"], root.vcs)
      ]
    ]))
    error_message = "vcs must be one of bzr, fossil, git, hg, mod or svn."
  }

  validation {
    condition = alltrue(flatten([
      for domain in values(var.domains) : [
        for root in values(domain.roots) : can(regex("^[a-z][a-z0-9+.-]*://\\S+$", root.repository))
      ]
    ]))
    error_message = "repository must be a URL with a scheme, such as \"https://github.com/example/foo\", and no whitespace."
  }

  validation {
    condition = alltrue(flatten([
      for domain in values(var.domains) : [
        for root in values(domain.roots) : root.redirect == null || can(regex("^https?://\\S+$", root.redirect))
      ]
    ]))
    error_message = "redirect must be an http(s) URL."
  }

  validation {
    condition = alltrue(flatten([
      for domain in values(var.domains) : [
        # A conditional rather than ||: older OpenTofu and Terraform versions
        # evaluate both sides of ||, and values(null) is an error.
        for root in values(domain.roots) : root.source == null ? true : alltrue([
          for template in values(root.source) : can(regex("^\\S+$", template))
        ])
      ]
    ]))
    error_message = "source templates must be non-empty and contain no whitespace."
  }
}

variable "default_redirect" {
  description = <<-EOT
    Where to send browsers for roots without a redirect: "repository" sends
    them to the root's repository, "pkg.go.dev" to the documentation for the
    requested import path. Roots with vcs "mod" always use pkg.go.dev, since
    their repository is a module proxy.
  EOT
  type        = string
  default     = "repository"

  validation {
    condition     = contains(["repository", "pkg.go.dev"], var.default_redirect)
    error_message = "default_redirect must be \"repository\" or \"pkg.go.dev\"."
  }
}

variable "redirect_status_code" {
  description = "HTTP status code for browser redirects. The default, 302, is not cached permanently by browsers, so repositories can move freely."
  type        = number
  default     = 302

  validation {
    condition     = contains([301, 302, 303, 307, 308], var.redirect_status_code)
    error_message = "redirect_status_code must be one of 301, 302, 303, 307 or 308."
  }
}

# Worker settings. Those that default to null keep the provider's defaults.

variable "compatibility_date" {
  description = "Workers runtime compatibility date for the Worker version."
  type        = string
  default     = "2026-09-01"

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.compatibility_date))
    error_message = "compatibility_date must be a date in YYYY-MM-DD format."
  }
}

variable "compatibility_flags" {
  description = "Workers runtime compatibility flags for the Worker version."
  type        = set(string)
  default     = null
}

variable "limits" {
  description = "Runtime limits for the Worker version: cpu_ms (CPU time per request) and subrequests (per request)."
  type = object({
    cpu_ms      = optional(number)
    subrequests = optional(number)
  })
  default = null
}

variable "logpush" {
  description = "Whether Logpush is enabled for the Worker."
  type        = bool
  default     = null
}

variable "observability" {
  description = "Observability settings for the Worker, such as Workers Logs and traces. Matches the observability attribute of the cloudflare_worker resource."
  type = object({
    enabled            = optional(bool)
    head_sampling_rate = optional(number)
    logs = optional(object({
      enabled            = optional(bool)
      head_sampling_rate = optional(number)
      invocation_logs    = optional(bool)
      persist            = optional(bool)
      destinations       = optional(list(string))
    }))
    traces = optional(object({
      enabled            = optional(bool)
      head_sampling_rate = optional(number)
      persist            = optional(bool)
      destinations       = optional(list(string))
      propagation_policy = optional(string)
    }))
    issues = optional(object({
      enabled = optional(bool)
    }))
  })
  default = null
}

variable "workers_dev_subdomain" {
  description = "Whether the Worker is reachable on its *.workers.dev URL (enabled) and on preview URLs (previews_enabled). Both are disabled unless set to true, since the Worker only serves the hostnames in var.domains and returns 404 anywhere else."
  type = object({
    enabled          = optional(bool, false)
    previews_enabled = optional(bool, false)
  })
  default  = {}
  nullable = false
}

variable "tags" {
  description = "Tags for the Worker."
  type        = set(string)
  default     = null
}

variable "tail_consumers" {
  description = "Names of Workers that consume this Worker's logs as Tail Workers."
  type        = set(string)
  default     = null
}
