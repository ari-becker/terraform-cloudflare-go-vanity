terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.26"
    }
  }
}

# Reads the API token from CLOUDFLARE_API_TOKEN.
provider "cloudflare" {}

variable "account_id" {
  description = "Cloudflare account ID."
  type        = string
}

module "go_vanity" {
  source = "../.."

  account_id = var.account_id

  domains = {
    "go.example.com" = {
      zone_name      = "example.com"
      index_redirect = "https://github.com/example"
      roots = {
        # go.example.com/foo/... comes from GitHub.
        foo = {
          repository = "https://github.com/example/foo"
        }
        # go.example.com/tools/bar/... comes from GitLab. Moving it elsewhere
        # means changing this URL; import paths stay the same.
        "tools/bar" = {
          repository = "https://gitlab.com/example/bar"
        }
      }
    }
  }
}

output "import_roots" {
  value = module.go_vanity.import_roots
}
