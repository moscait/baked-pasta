# ==============================================================================
# Top-Level Makefile for Baked Pasta: Demo Apps & Zero-Trust Infrastructure
# ==============================================================================
# This Makefile automatically discovers subdirectories containing maven projects
# (by looking for 'pom.xml') and provides targets to build Maven projects and
# their corresponding Docker images, run the local sandbox, or deploy the
# routable OpenZiti Zero-Trust Infrastructure.

# Detect all apps (directories containing a pom.xml)
APP_DIRS := $(dir $(wildcard */pom.xml))
APPS     := $(patsubst %/,%,$(APP_DIRS))

# Options passed to maven build. Can be overridden from command line.
# Example: make maven-build MVN_FLAGS="" (to run tests)
MVN_FLAGS ?= -DskipTests

# Docker registry/namespace prefix (optional, e.g. "myregistry.io/origname/")
DOCKER_REGISTRY ?=
# Docker image tag
DOCKER_TAG ?= latest

# Default target
.PHONY: all
all: maven-build docker-build

# Maven build target for all apps
.PHONY: maven-build
maven-build: $(addprefix maven-build-,$(APPS))

# Docker build target for all apps
.PHONY: docker-build
docker-build: $(addprefix docker-build-,$(APPS))

# Clean target for all apps
.PHONY: clean
clean: $(addprefix clean-,$(APPS))

# Define rules for each app dynamically
define APP_RULES
.PHONY: maven-build-$(1)
maven-build-$(1):
	@echo "==> Building Maven project in directory: $(1)..."
	@if [ -f $(1)/mvnw ]; then \
		cd $(1) && ./mvnw clean package $$(MVN_FLAGS); \
	else \
		cd $(1) && mvn clean package $$(MVN_FLAGS); \
	fi

.PHONY: docker-build-$(1)
docker-build-$(1): maven-build-$(1)
	@echo "==> Building Docker image for $(1)..."
	@if [ -f $(1)/Dockerfile ]; then \
		docker build -t $$(DOCKER_REGISTRY)$(1):$$(DOCKER_TAG) $(1); \
	else \
		echo "No Dockerfile found in $(1), skipping docker build."; \
	fi

.PHONY: clean-$(1)
clean-$(1):
	@echo "==> Cleaning Maven project in directory: $(1)..."
	@if [ -f $(1)/mvnw ]; then \
		cd $(1) && ./mvnw clean; \
	else \
		cd $(1) && mvn clean; \
	fi
endef

# Evaluate rules for each app
$(foreach app,$(APPS),$(eval $(call APP_RULES,$(app))))

# ==============================================================================
# Mode A: Local Developer Sandbox (Full Demo Environment)
# ==============================================================================
.PHONY: sandbox-up sandbox-down sandbox-logs sandbox-status

# Generate a local .env (mode 600) with a random sandbox admin password on first run.
.env:
	@echo "==> Generating .env with a random OpenZiti sandbox admin password..."
	@umask 077 && printf 'OPENZITI_ADMIN_PASSWORD=%s\n' "$$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 24)" > .env
	@echo "    Admin password stored in .env (user: admin)."

# Admin console for both configurations:
#   zac        OpenZiti Admin Console (default, static SPA)
#   bpc        Baked Pasta Console Web edition (static SPA)
#   bpc-vaadin Baked Pasta Console Vaadin edition (server-side JVM container)
# For an unreleased BPC, pass BPC_DIR=<checkout> (builds web/ or vaadin/ Docker image locally)
# or BPC_ZIP=<archive> (web edition only).
# Example: make sandbox-up CONSOLE=bpc-vaadin
CONSOLE ?= $(or $(BAKED_PASTA_CONSOLE),zac)
CONSOLE_ENV = BAKED_PASTA_CONSOLE='$(CONSOLE)' $(if $(BPC_DIR),BPC_DIR='$(BPC_DIR)',) $(if $(BPC_ZIP),BPC_ZIP='$(BPC_ZIP)',)

# How admins reach the Configuration 2 console (deploy-ziti.sh --console-access):
#   cloudflare  Cloudflare Tunnel + Access (default)
#   ziti        only over the OpenZiti overlay, as http://console.ziti/ (no Cloudflare Tunnel)
#   both        either way
# Example: make ziti-ssh TARGET=user@host ADVERTISE=ziti.example.com ACCESS=ziti
ACCESS ?= $(or $(BAKED_PASTA_CONSOLE_ACCESS),cloudflare)
ACCESS_ENV = BAKED_PASTA_CONSOLE_ACCESS='$(ACCESS)'

# Install the selected console (or build the local Vaadin image when BPC_DIR is set).
# Kept as is when that console is already installed; FORCE=1 replaces it.
.PHONY: sandbox-console
sandbox-console:
ifeq ($(CONSOLE),bpc-vaadin)
	@if [ -n "$(BPC_DIR)" ]; then \
		echo "==> Building Baked Pasta Console (Vaadin) image from $(BPC_DIR)/vaadin..."; \
		DOCKER_BUILDKIT=1 docker build -t baked-pasta-console-vaadin:local "$(BPC_DIR)/vaadin"; \
	else \
		echo "==> Using Baked Pasta Console (Vaadin) container image."; \
	fi
else
	@$(CONSOLE_ENV) ./scripts/fetch-console.sh sandbox $(if $(FORCE),--force,)
endif

sandbox-up: .env sandbox-console
	@echo "==> Starting local developer sandbox (ports bound to 127.0.0.1, console: $(CONSOLE))..."
ifeq ($(CONSOLE),bpc-vaadin)
	@BAKED_PASTA_CONSOLE=bpc-vaadin $(if $(BPC_DIR),BPC_VAADIN_IMAGE=baked-pasta-console-vaadin:local,) docker compose --profile vaadin up -d
else
	@BAKED_PASTA_CONSOLE='$(CONSOLE)' docker compose up -d
endif

sandbox-down:
	@echo "==> Stopping local developer sandbox..."
	@docker compose --profile vaadin down

sandbox-logs:
	@docker compose logs -f

sandbox-status:
	@docker compose ps

# ==============================================================================
# Mode B: Routable OpenZiti Infrastructure (Edge Controller, Router, Console via Cloudflare)
# ==============================================================================
.PHONY: ziti-deploy ziti-check-token ziti-ssh ziti-admin-token ziti-teardown ziti-up ziti-down ziti-logs ziti-status console-fetch console-build console-update

ziti-deploy:
	@echo "==> Running automated OpenZiti Zero-Trust Infrastructure deployment..."
	@$(CONSOLE_ENV) $(ACCESS_ENV) ./deploy-ziti.sh

# Decode CLOUDFLARE_TUNNEL_TOKEN locally and print the tunnel ID it belongs to (deploys nothing).
ziti-check-token:
	@./deploy-ziti.sh --check-token

ziti-ssh:
	@if [ -z "$(TARGET)" ]; then \
		echo "Usage: make ziti-ssh TARGET=user@host [TOKEN=eyJh...] [ADVERTISE=ziti.example.com] [DNS_TOKEN=cf_dns_tok] [USER=admin] [PASSWORD=secret] [QUICK=1] [ACCESS=cloudflare|ziti|both]" && \
		echo "       Prefer exporting CLOUDFLARE_TUNNEL_TOKEN / CLOUDFLARE_DNS_API_TOKEN / OPENZITI_ADMIN_PASSWORD" && \
		echo "       instead of TOKEN=/DNS_TOKEN=/PASSWORD= (make arguments are visible in ps)." && exit 1; \
	fi
	@$(if $(TOKEN),CLOUDFLARE_TUNNEL_TOKEN='$(TOKEN)',) \
	 $(if $(DNS_TOKEN),CLOUDFLARE_DNS_API_TOKEN='$(DNS_TOKEN)',) \
	 $(if $(PASSWORD),OPENZITI_ADMIN_PASSWORD='$(PASSWORD)',) \
	 $(CONSOLE_ENV) $(ACCESS_ENV) ./deploy-ziti.sh --ssh '$(TARGET)' $(if $(ADVERTISE),--advertise-address '$(ADVERTISE)',) $(if $(filter command line,$(origin USER)),-u '$(USER)',) $(if $(QUICK),--quick,)

# Copy the first admin device's enrollment token (ACCESS=ziti or both) from the host to
# ./console-admin.jwt (mode 0600, git-ignored), then enroll it in a Ziti client (Ziti Desktop
# Edge, ziti-edge-tunnel) and open http://console.ziti/. Needs passwordless sudo on the host.
ziti-admin-token:
	@if [ -z "$(TARGET)" ]; then echo "Usage: make ziti-admin-token TARGET=user@host" && exit 1; fi
	@umask 077 && ssh '$(TARGET)' 'sudo -n cat /opt/openziti/console-admin/console-admin.jwt' > console-admin.jwt.tmp \
		&& mv console-admin.jwt.tmp console-admin.jwt \
		&& echo "==> Saved console-admin.jwt (valid 24 hours from the last deploy). Enroll it, then delete the file." \
		|| { rm -f console-admin.jwt.tmp; echo "No token on $(TARGET): console-admin may already be enrolled, or console access over OpenZiti is off. Redeploy to issue a new one."; exit 1; }

# Pin a Baked Pasta Console release (checks it against GitHub's checksum and updates the pin in
# scripts/fetch-console.sh, NOTICE and README.md). Review and commit, then deploy as usual.
# Example: make bpc-pin VERSION=v0.1.2   (default: latest)
.PHONY: bpc-pin
bpc-pin:
	@./scripts/pin-bpc.sh $(or $(VERSION),latest)

# Install the selected console (CONSOLE=zac|bpc, see above) into infrastructure/console/.
# deploy-ziti.sh does this automatically. FORCE=1 replaces a custom build.
console-fetch:
	@$(CONSOLE_ENV) ./scripts/fetch-console.sh infrastructure $(if $(FORCE),--force,)

# Build the Admin Console from source into infrastructure/console/ (default: upstream main).
# Example: make console-build REPO=https://github.com/you/ziti-console.git REF=my-branch
# Or a local checkout: make console-build FROM_DIR=../ziti-console
console-build:
	@./scripts/build-console.sh $(if $(REPO),--repo '$(REPO)',) $(if $(REF),--ref '$(REF)',) $(if $(FROM_DIR),--from-dir '$(FROM_DIR)',)

# Push infrastructure/console/ and the nginx config to a running deployment (no token needed).
console-update:
	@if [ -z "$(TARGET)" ]; then echo "Usage: make console-update TARGET=user@host" && exit 1; fi
	@$(CONSOLE_ENV) ./deploy-ziti.sh --ssh '$(TARGET)' --update-console

# Tear down remote infrastructure over SSH. KEEP_DATA=1 preserves PKI/credentials; YES=1 skips the prompt.
ziti-teardown:
	@if [ -z "$(TARGET)" ]; then \
		echo "Usage: make ziti-teardown TARGET=user@host [KEEP_DATA=1] [YES=1]" && exit 1; \
	fi
	@./deploy-ziti.sh --ssh $(TARGET) --teardown $(if $(KEEP_DATA),--keep-data,) $(if $(YES),--yes,)

# The manual stack always serves the console through Cloudflare. For ACCESS=ziti or both, deploy
# with deploy-ziti.sh (make ziti-deploy / ziti-ssh), which also creates the OpenZiti service.
ziti-up:
	@if [ "$(ACCESS)" != cloudflare ]; then echo "make ziti-up supports only ACCESS=cloudflare; use make ziti-deploy or ziti-ssh for ACCESS=$(ACCESS)." && exit 1; fi
	@echo "==> Starting OpenZiti Infrastructure stack (console: $(CONSOLE))..."
ifeq ($(CONSOLE),bpc-vaadin)
	@CONSOLE_NGINX_CONF=default.vaadin.conf docker compose -f infrastructure/docker-compose.cloudflare.yaml --profile vaadin up -d
else
	@docker compose -f infrastructure/docker-compose.cloudflare.yaml up -d
endif

ziti-down:
	@echo "==> Stopping OpenZiti Infrastructure stack..."
	@docker compose -f infrastructure/docker-compose.cloudflare.yaml --profile vaadin down

ziti-logs:
	@docker compose -f infrastructure/docker-compose.cloudflare.yaml logs -f

ziti-status:
	@docker compose -f infrastructure/docker-compose.cloudflare.yaml ps

# ==============================================================================
# Optional: Oracle Cloud (OCI) host for Mode B (see infrastructure/oracle-cloud/README.md)
# ==============================================================================
.PHONY: oci-init oci-plan oci-apply oci-output oci-destroy

OCI_DIR := infrastructure/oracle-cloud
# Prefer OpenTofu, fall back to Terraform. Override with TF=terraform.
TF ?= $(shell command -v tofu >/dev/null 2>&1 && echo tofu || echo terraform)

oci-init:
	@test -f $(OCI_DIR)/terraform.tfvars || { echo "Create $(OCI_DIR)/terraform.tfvars first (cp $(OCI_DIR)/terraform.tfvars.example $(OCI_DIR)/terraform.tfvars)"; exit 1; }
	@$(TF) -chdir=$(OCI_DIR) init

oci-plan:
	@$(TF) -chdir=$(OCI_DIR) plan

oci-apply:
	@$(TF) -chdir=$(OCI_DIR) apply

oci-output:
	@$(TF) -chdir=$(OCI_DIR) output

oci-destroy:
	@$(TF) -chdir=$(OCI_DIR) destroy
