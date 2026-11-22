# Oracle Cloud Infrastructure (OCI) host for the Baked Pasta infrastructure:
# VCN + public subnet + Ubuntu instance + reserved public IP, with a security list that
# exposes only SSH (from your IP) and the OpenZiti mTLS ports (1280 / 8444).

data "http" "my_ip" {
  count = var.ssh_source_cidr == "" ? 1 : 0
  url   = "https://checkip.amazonaws.com"
}

locals {
  compartment_id  = var.compartment_ocid != "" ? var.compartment_ocid : var.tenancy_ocid
  ssh_source_cidr = var.ssh_source_cidr != "" ? var.ssh_source_cidr : "${chomp(data.http.my_ip[0].response_body)}/32"

  # Ampere (ARM) shapes need aarch64 images; everything else uses x86_64 images.
  is_arm  = can(regex("^VM\\.Standard\\.A[0-9]+\\.", var.instance_shape))
  is_flex = can(regex("\\.Flex$", var.instance_shape))
  arch    = local.is_arm ? "aarch64-" : ""

  os = {
    ubuntu = {
      operating_system = "Canonical Ubuntu"
      version          = var.ubuntu_version
      # e.g. Canonical-Ubuntu-24.04-aarch64-2026.10.27-0 / Canonical-Ubuntu-24.04-2026.10.27-0
      image_regex = "^Canonical-Ubuntu-${replace(var.ubuntu_version, ".", "\\.")}-${local.arch}[0-9]{4}\\..*$"
      ssh_user    = "ubuntu"
      cloud_init  = file("${path.module}/cloud-init.yaml")
    }
    oraclelinux = {
      operating_system = "Oracle Linux"
      version          = var.oraclelinux_version
      # e.g. Oracle-Linux-9.6-aarch64-2026.10.01-0 / Oracle-Linux-9.6-2026.10.01-0 (excludes GPU/Minimal builds)
      image_regex = "^Oracle-Linux-${var.oraclelinux_version}\\.[0-9]+-${local.arch}[0-9]{4}\\..*$"
      ssh_user    = "opc"
      cloud_init  = null # firewalld is managed by the playbook as-is
    }
  }
  selected = local.os[var.base_os]
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "selected" {
  compartment_id           = local.compartment_id
  operating_system         = local.selected.operating_system
  operating_system_version = local.selected.version
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"

  filter {
    name   = "display_name"
    values = [local.selected.image_regex]
    regex  = true
  }
}

# ------------------------------------------------------------------------------
# Networking
# ------------------------------------------------------------------------------
resource "oci_core_vcn" "vcn" {
  compartment_id = local.compartment_id
  cidr_block     = var.vcn_cidr
  display_name   = "${var.name_prefix}-vcn"
}

resource "oci_core_internet_gateway" "igw" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "${var.name_prefix}-igw"
}

resource "oci_core_default_route_table" "default" {
  manage_default_resource_id = oci_core_vcn.vcn.default_route_table_id

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

# Replaces the VCN's default rules (which allow SSH from 0.0.0.0/0).
# Re-run `tofu apply` if your public IP changes - only this rule is updated.
resource "oci_core_default_security_list" "default" {
  manage_default_resource_id = oci_core_vcn.vcn.default_security_list_id

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    description = "SSH (restricted source)"
    protocol    = "6" # TCP
    source      = local.ssh_source_cidr
    tcp_options {
      min = 22
      max = 22
    }
  }

  dynamic "ingress_security_rules" {
    for_each = var.ziti_public_ports
    content {
      description = "OpenZiti mTLS ${ingress_security_rules.value}/tcp"
      protocol    = "6"
      source      = "0.0.0.0/0"
      tcp_options {
        min = ingress_security_rules.value
        max = ingress_security_rules.value
      }
    }
  }

  # ICMP for path MTU discovery (same as OCI's defaults)
  ingress_security_rules {
    protocol = "1"
    source   = "0.0.0.0/0"
    icmp_options {
      type = 3
      code = 4
    }
  }

  ingress_security_rules {
    protocol = "1"
    source   = var.vcn_cidr
    icmp_options {
      type = 3
    }
  }
}

resource "oci_core_subnet" "public" {
  compartment_id    = local.compartment_id
  vcn_id            = oci_core_vcn.vcn.id
  cidr_block        = var.subnet_cidr
  display_name      = "${var.name_prefix}-subnet"
  route_table_id    = oci_core_vcn.vcn.default_route_table_id
  security_list_ids = [oci_core_default_security_list.default.id]
}

# ------------------------------------------------------------------------------
# Instance
# ------------------------------------------------------------------------------
resource "oci_core_instance" "ziti" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.availability_domain_index].name
  compartment_id      = local.compartment_id
  shape               = var.instance_shape
  display_name        = "${var.name_prefix}-instance"

  dynamic "shape_config" {
    for_each = local.is_flex ? [1] : []
    content {
      ocpus         = var.instance_ocpus
      memory_in_gbs = var.instance_memory_gbs
    }
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.selected.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_size_gbs
  }

  # The public IP is a separate RESERVED address (below), so it survives instance
  # re-creation and the ziti.<domain> DNS record never has to change.
  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = false
  }

  metadata = merge(
    { ssh_authorized_keys = file(pathexpand(var.ssh_public_key_path)) },
    local.selected.cloud_init == null ? {} : { user_data = base64encode(local.selected.cloud_init) },
  )

  lifecycle {
    # Newer images are published regularly; don't replace a running host because of that.
    ignore_changes = [source_details[0].source_id]
  }
}

data "oci_core_vnic_attachments" "primary" {
  compartment_id = local.compartment_id
  instance_id    = oci_core_instance.ziti.id
}

data "oci_core_private_ips" "primary" {
  vnic_id = data.oci_core_vnic_attachments.primary.vnic_attachments[0].vnic_id
}

resource "oci_core_public_ip" "reserved" {
  compartment_id = local.compartment_id
  lifetime       = "RESERVED"
  display_name   = "${var.name_prefix}-public-ip"
  private_ip_id  = data.oci_core_private_ips.primary.private_ips[0].id
}
