output "worker_id" {
  description = "ID of the Worker."
  value       = cloudflare_worker.this.id
}

output "worker_name" {
  description = "Name of the Worker."
  value       = cloudflare_worker.this.name
}

output "version_id" {
  description = "ID of the Worker version the module deployed."
  value       = cloudflare_worker_version.this.id
}

output "import_roots" {
  description = "Every import root served, mapped to its repository."
  value = merge([
    for hostname, domain in var.domains : {
      for path, root in domain.roots : (path == "" ? hostname : "${hostname}/${path}") => root.repository
    }
  ]...)
}

output "custom_domain_ids" {
  description = "IDs of the Workers Custom Domains, keyed by hostname."
  value       = { for hostname, domain in cloudflare_workers_custom_domain.this : hostname => domain.id }
}
