output "public_ip" {
  description = "Reserved public IP. Use it for the DNS-only ziti.<domain> A record (server_public_ip in ../opentofu)."
  value       = oci_core_public_ip.reserved.ip_address
}

output "ssh_allowed_from" {
  value = local.ssh_source_cidr
}

output "ssh_command" {
  value = "ssh -i ${trimsuffix(var.ssh_public_key_path, ".pub")} ${local.selected.ssh_user}@${oci_core_public_ip.reserved.ip_address}"
}

output "baked_pasta_ssh_target" {
  description = "Value for deploy-ziti.sh --ssh / make ziti-ssh TARGET="
  value       = "${local.selected.ssh_user}@${oci_core_public_ip.reserved.ip_address}"
}

output "ssh_user" {
  value = local.selected.ssh_user
}

output "ssh_by_name" {
  description = "Once the DNS-only A record exists, SSH by hostname instead of IP"
  value       = "ssh -i ${trimsuffix(var.ssh_public_key_path, ".pub")} ${local.selected.ssh_user}@${var.ziti_advertise_address}"
}

output "image" {
  value = data.oci_core_images.selected.images[0].display_name
}

# Contains no secrets. Run from the repository root after the Cloudflare setup (CLOUDFLARE.md).
output "next_steps" {
  value = <<-EOT
    1. Point a DNS-only (grey-cloud) A record ${var.ziti_advertise_address} -> ${oci_core_public_ip.reserved.ip_address}
       (or set server_public_ip = "${oci_core_public_ip.reserved.ip_address}" in infrastructure/opentofu/terraform.tfvars).
    2. Trust the host key once:  ssh -i ${trimsuffix(var.ssh_public_key_path, ".pub")} ${local.selected.ssh_user}@${oci_core_public_ip.reserved.ip_address} true
    3. Deploy OpenZiti:
       read -rsp 'Tunnel token: ' CLOUDFLARE_TUNNEL_TOKEN; echo; export CLOUDFLARE_TUNNEL_TOKEN
       ./deploy-ziti.sh --ssh ${local.selected.ssh_user}@${oci_core_public_ip.reserved.ip_address} --advertise-address ${var.ziti_advertise_address}
  EOT
}
