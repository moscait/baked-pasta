output "tunnel_id" {
  description = "Unique identifier of the Cloudflare Tunnel"
  value       = cloudflare_zero_trust_tunnel_cloudflared.openziti_tunnel.id
}

output "tunnel_token" {
  description = "Authentication token for running cloudflared daemon in Docker / Ansible"
  value       = cloudflare_zero_trust_tunnel_cloudflared.openziti_tunnel.tunnel_token
  sensitive   = true
}

output "console_url" {
  description = "Public Zero-Trust URL for the OpenZiti Admin Console (ZAC)"
  value       = "https://${var.console_subdomain}.${var.domain_name}"
}

output "ziti_advertise_address" {
  description = "Publicly routable DNS hostname for OpenZiti Controller (1280) and Edge Router (8444)"
  value       = "${var.ziti_subdomain}.${var.domain_name}"
}

# Contains no secrets: the tunnel token is read from state at run time, and the DDNS token
# must be a SEPARATE Cloudflare API token scoped to Zone.DNS:Edit on this zone only
# (never the broad OpenTofu token in var.cloudflare_api_token).
output "deploy_command" {
  description = "Command template to deploy the OpenZiti infrastructure over SSH (run from the repository root)"
  value       = <<-EOT
    export CLOUDFLARE_TUNNEL_TOKEN="$(tofu -chdir=infrastructure/opentofu output -raw tunnel_token)"
    read -rsp 'Zone.DNS:Edit-only Cloudflare token for DDNS (Enter to skip): ' CLOUDFLARE_DNS_API_TOKEN; echo; export CLOUDFLARE_DNS_API_TOKEN
    ./deploy-ziti.sh --ssh user@host --advertise-address '${var.ziti_subdomain}.${var.domain_name}'
  EOT
}
