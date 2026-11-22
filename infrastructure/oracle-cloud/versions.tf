terraform {
  required_version = ">= 1.6.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 9.12"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

# Authentication comes from your local OCI CLI config (~/.oci/config), never from this repo.
#   SecurityToken (default): browser login with `oci session authenticate` - no API key needed.
#   ApiKey:                  API signing key configured with `oci setup config`.
provider "oci" {
  region              = var.region
  auth                = var.oci_auth
  config_file_profile = var.oci_config_profile
}
