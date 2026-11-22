# ------------------------------------------------------------------------------
# Account & authentication
# ------------------------------------------------------------------------------
variable "tenancy_ocid" {
  type        = string
  description = "Tenancy OCID (OCI Console → Profile → Tenancy). Also printed by `grep tenancy ~/.oci/config`."
}

variable "compartment_ocid" {
  type        = string
  description = "Compartment to create resources in. Leave empty to use the tenancy (root) compartment."
  default     = ""
}

variable "region" {
  type        = string
  description = "OCI region identifier, e.g. us-ashburn-1. Must be a region your tenancy is subscribed to (Always Free A1 capacity is in your home region)."
}

variable "oci_auth" {
  type        = string
  description = "OCI provider auth method: SecurityToken (`oci session authenticate`) or ApiKey (`oci setup config`)."
  default     = "SecurityToken"

  validation {
    condition     = contains(["SecurityToken", "ApiKey"], var.oci_auth)
    error_message = "oci_auth must be SecurityToken or ApiKey."
  }
}

variable "oci_config_profile" {
  type        = string
  description = "Profile name in ~/.oci/config."
  default     = "DEFAULT"
}

# ------------------------------------------------------------------------------
# Naming & networking
# ------------------------------------------------------------------------------
variable "name_prefix" {
  type        = string
  description = "Prefix for display names of all created resources."
  default     = "openziti"
}

variable "vcn_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "ssh_source_cidr" {
  type        = string
  description = "CIDR allowed to SSH (port 22). Leave empty to auto-detect your current public IPv4 as a /32."
  default     = ""
}

# Matches infrastructure/ansible/vars/main.yml (ziti_ctrl_port / ziti_router_port).
# The Admin Console is reached only through Cloudflare Tunnel (outbound), so 80/443/8080 stay closed.
variable "ziti_public_ports" {
  type        = list(number)
  description = "TCP ports open to the internet for OpenZiti mTLS: controller client API (1280) and edge router (8444)."
  default     = [1280, 8444]
}

# ------------------------------------------------------------------------------
# Instance
# ------------------------------------------------------------------------------
variable "ssh_public_key_path" {
  type        = string
  description = "Path to the SSH public key installed for the `ubuntu` user. Keep the matching private key - OCI cannot recover it."
  default     = "~/.ssh/id_ed25519.pub"
}

variable "instance_shape" {
  type        = string
  description = "Compute shape. VM.Standard.A1.Flex (Ampere ARM) is Always Free up to 2 OCPUs / 12 GB in total per tenancy (1,500 OCPU-hours and 9,000 GB-hours per month)."
  default     = "VM.Standard.A1.Flex"
}

variable "instance_ocpus" {
  type        = number
  description = "OCPUs for Flex shapes. Always Free covers 2 A1 OCPUs in total across all instances; more is billed on Pay As You Go accounts."
  default     = 1
}

variable "instance_memory_gbs" {
  type        = number
  description = "Memory (GB) for Flex shapes. Always Free covers 12 GB of A1 memory in total across all instances; more is billed on Pay As You Go accounts."
  default     = 6
}

variable "boot_volume_size_gbs" {
  type        = number
  description = "Boot volume size. Always Free covers 200 GB of boot + block storage in total in the home region."
  default     = 50
}

variable "availability_domain_index" {
  type        = number
  description = "Which availability domain to use (0-based). Try another index if you get 'Out of host capacity'."
  default     = 0
}

variable "base_os" {
  type        = string
  description = "Instance OS: ubuntu (Docker Engine + ufw) or oraclelinux (Podman + firewalld + SELinux, RHEL-compatible)."
  default     = "ubuntu"

  validation {
    condition     = contains(["ubuntu", "oraclelinux"], var.base_os)
    error_message = "base_os must be ubuntu or oraclelinux."
  }
}

variable "ubuntu_version" {
  type        = string
  description = "Ubuntu release when base_os = ubuntu."
  default     = "24.04"
}

variable "oraclelinux_version" {
  type        = string
  description = "Oracle Linux major release when base_os = oraclelinux."
  default     = "9"
}

# ------------------------------------------------------------------------------
# OpenZiti (used only to print a ready-to-run deploy command)
# ------------------------------------------------------------------------------
variable "ziti_advertise_address" {
  type        = string
  description = "DNS-only hostname that will point at the instance's public IP, e.g. ziti.example.com (see infrastructure/CLOUDFLARE.md)."
  default     = "ziti.example.com"
}
