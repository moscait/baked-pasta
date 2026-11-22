# Generate a secure 32-byte secret for the Cloudflare tunnel
resource "random_id" "tunnel_secret" {
  byte_length = 32
}

# Create Cloudflare Zero Trust Tunnel
resource "cloudflare_zero_trust_tunnel_cloudflared" "openziti_tunnel" {
  account_id = var.cloudflare_account_id
  name       = var.tunnel_name
  secret     = random_id.tunnel_secret.b64_std
}

# Configure Ingress Rules for the Tunnel
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "openziti_config" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.openziti_tunnel.id

  lifecycle {
    precondition {
      condition     = !var.enable_access_sso || length(var.allowed_user_emails) > 0
      error_message = "enable_access_sso is true but allowed_user_emails is empty: nobody could log in. Add at least one email, or explicitly set enable_access_sso = false (NOT recommended: the console proxies the management API)."
    }
  }

  config {
    warp_routing {
      enabled = false
    }

    # Ingress rule: OpenZiti Admin Console (ZAC) served at root
    ingress_rule {
      hostname = "${var.console_subdomain}.${var.domain_name}"
      service  = "http://127.0.0.1:8080"
    }

    # Default catch-all rule (required by Cloudflare)
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# Proxied DNS CNAME Record for OpenZiti Console Subdomain (Cloudflare Tunnel + Access)
resource "cloudflare_record" "console_cname" {
  zone_id = var.cloudflare_zone_id
  name    = var.console_subdomain
  content = "${cloudflare_zero_trust_tunnel_cloudflared.openziti_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

# DNS-only (grey-cloud) A Record for the OpenZiti Overlay (Controller 1280 + Edge Router 8444)
# OpenZiti requires direct end-to-end mutual TLS; Cloudflare's HTTP proxy cannot terminate or forward it.
resource "cloudflare_record" "ziti_overlay_a" {
  count   = var.server_public_ip != "" ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = var.ziti_subdomain
  content = var.server_public_ip
  type    = "A"
  proxied = false
  ttl     = 120
}

# Cloudflare Access Application (Zero Trust identity verification) - enabled by default
resource "cloudflare_zero_trust_access_application" "console_access" {
  count            = var.enable_access_sso ? 1 : 0
  zone_id          = var.cloudflare_zone_id
  name             = "OpenZiti Console Access"
  domain           = "${var.console_subdomain}.${var.domain_name}"
  session_duration = "24h"
}

# Cloudflare Access Policy - enabled by default
resource "cloudflare_zero_trust_access_policy" "console_policy" {
  count          = var.enable_access_sso ? 1 : 0
  application_id = cloudflare_zero_trust_access_application.console_access[0].id
  zone_id        = var.cloudflare_zone_id
  name           = "Allow Authorized Emails"
  precedence     = 1
  decision       = "allow"

  include {
    email = var.allowed_user_emails
  }
}
