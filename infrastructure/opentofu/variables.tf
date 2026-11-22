variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API Token used by OpenTofu only (Zero Trust, DNS, and Zone permissions). Never deploy this token to the host; create a separate Zone.DNS:Edit-only token for DDNS."
  sensitive   = true
}

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID (found in the Cloudflare dashboard overview)"
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare Zone ID for the target domain"
}

variable "domain_name" {
  type        = string
  description = "Target domain name managed in Cloudflare (e.g. example.com)"
}

variable "tunnel_name" {
  type        = string
  description = "Name for the Cloudflare Zero Trust Tunnel"
  default     = "openziti-tunnel"
}

variable "console_subdomain" {
  type        = string
  description = "Subdomain for the OpenZiti Admin Console (ZAC), proxied via Cloudflare Tunnel"
  default     = "zt"
}

variable "ziti_subdomain" {
  type        = string
  description = "DNS-only (grey-cloud) subdomain for OpenZiti mTLS overlay traffic (ports 1280 and 8444)"
  default     = "ziti"
}

variable "server_public_ip" {
  type        = string
  description = "Public IPv4 address of the host (or WAN router forwarding TCP 1280/8444) for the DNS-only ziti_subdomain A record"
  default     = ""
}

variable "enable_access_sso" {
  type        = bool
  description = "Protect the Admin Console hostname with a Cloudflare Access policy. Strongly recommended: the console proxies the OpenZiti management API. Disable only if you protect the hostname another way."
  default     = true
}

variable "allowed_user_emails" {
  type        = list(string)
  description = "List of allowed email addresses for Cloudflare Access policy (required when enable_access_sso = true)"
  default     = []

  validation {
    condition     = alltrue([for e in var.allowed_user_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "allowed_user_emails must contain valid email addresses."
  }
}
