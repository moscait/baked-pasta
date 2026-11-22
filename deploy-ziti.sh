#!/usr/bin/env bash
# ==============================================================================
# Automated OpenZiti Zero-Trust Infrastructure Deployer (Fedora & Ubuntu)
# Packages Controller, Edge Router, and Admin Console protected by Cloudflare Tunnel
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$SCRIPT_DIR/infrastructure" ]; then
    ROOT_DIR="$SCRIPT_DIR"
elif [ -d "$SCRIPT_DIR/ansible" ]; then
    ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
    ROOT_DIR="$SCRIPT_DIR"
fi
TOKEN="${CLOUDFLARE_TUNNEL_TOKEN:-}"
DNS_TOKEN="${CLOUDFLARE_DNS_API_TOKEN:-}"
ADMIN_USER="${OPENZITI_ADMIN_USER:-admin}"
ADMIN_PASSWORD="${OPENZITI_ADMIN_PASSWORD:-}"
ADVERTISE_ADDRESS="${OPENZITI_ADVERTISE_ADDRESS:-}"
TARGET="localhost"
SSH_STREAM_HOST=""
QUICK_MODE=false
TEARDOWN=false
UPDATE_CONSOLE=false
CONSOLE="${BAKED_PASTA_CONSOLE:-zac}"
CHECK_TOKEN_ONLY=false
KEEP_DATA=false
ASSUME_YES=false
CLI_SECRET_USED=false

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_banner() {
    cat << "EOF"
======================================================================
   ____                  _____ _ _   _ 
  / __ \                |___  (_) | (_)
 | |  | |_ __   ___ _ __   / / _| |_ _ 
 | |  | | '_ \ / _ \ '_ \ / / | | __| |
 | |__| | |_) |  __/ | | / /__| | |_| |
  \____/| .__/ \___|_| |_\_____|_|\__|_|
        | |                             
        |_|  Zero-Trust Edge Infrastructure (Cloudflare)
======================================================================
EOF
}

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Automated, single-command deployment of the OpenZiti Zero-Trust Infrastructure
(Controller, Edge Router, and Admin Console) on Fedora and Ubuntu,
exposed securely without public inbound ports via Cloudflare Tunnel.

Options:
  -s, --ssh <USER@HOST>       Stream and deploy directly to remote Linux host over SSH.
                              NO git clone or GitHub access required on the target machine!
  -t, --token <TOKEN>         Cloudflare Zero Trust Tunnel Token.
                              Prefer the CLOUDFLARE_TUNNEL_TOKEN env var (CLI args are visible in 'ps').
  -a, --advertise-address <HOST>
                              Publicly routable DNS hostname (or IP) advertised by the OpenZiti
                              Controller (1280) and Edge Router (8444) for client enrollment and
                              mTLS overlay connections (e.g. ziti.example.com — use a DNS-only /
                              grey-cloud record in Cloudflare).
  -d, --dns-token <API_TOKEN> Cloudflare API Token scoped ONLY to Zone.DNS:Edit on this zone. Starts
                              the openziti-ddns container so dynamic home WAN IPs automatically
                              create and update the DNS-only A record for --advertise-address.
                              Prefer the CLOUDFLARE_DNS_API_TOKEN env var.
  -u, --user <USERNAME>       OpenZiti Admin username (default: admin).
  -p, --password <PASSWORD>   OpenZiti Admin password (default: auto-generated 24-char random string).
                              Min 12 chars; no quotes, backslashes, '$', backticks or spaces.
                              Prefer the OPENZITI_ADMIN_PASSWORD env var.
  -r, --target <HOST>         Target host via local Ansible over SSH (default: localhost).
  -q, --quick                 Opt in to TryCloudflare Quick Tunnel mode. WARNING: the Admin Console
                              (and the management API behind it) is then reachable by anyone who
                              learns the random URL, protected only by the admin password.
      --teardown              Tear down the infrastructure instead of deploying it. Removes all
                              containers, the network, the PKI volume and /opt/openziti.
      --keep-data             With --teardown: remove containers only; preserve the PKI volume
                              and install directory (credentials, enrolled identities).
  -y, --yes                   With --teardown: skip the confirmation prompt.
      --update-console        Refresh only the Admin Console files and nginx config on an existing
                              deployment, then restart the console container. No tunnel token
                              needed; the controller, PKI and identities are untouched.
      --console <zac|bpc>     Admin console to deploy: zac (OpenZiti Admin Console, default) or bpc
                              (Baked Pasta Console). Also BAKED_PASTA_CONSOLE. For bpc, set BPC_DIR
                              to a checkout to build, or BPC_ZIP to a built archive.
      --check-token           Check that CLOUDFLARE_TUNNEL_TOKEN is a well-formed tunnel token,
                              print the tunnel ID it belongs to, and exit without deploying.
  -h, --help                  Show this help message.

Secrets are read from environment variables (recommended):
  CLOUDFLARE_TUNNEL_TOKEN, CLOUDFLARE_DNS_API_TOKEN, OPENZITI_ADMIN_PASSWORD

Examples:
  # 1. Zero git clone over SSH with automatic Cloudflare DDNS (RECOMMENDED for home/dynamic IPs):
  read -rs CLOUDFLARE_TUNNEL_TOKEN && read -rs CLOUDFLARE_DNS_API_TOKEN && \
    export CLOUDFLARE_TUNNEL_TOKEN CLOUDFLARE_DNS_API_TOKEN
  ./$(basename "$0") --ssh user@192.0.2.10 -a ziti.example.com

  # 2. Run locally directly on a Fedora or Ubuntu host:
  CLOUDFLARE_TUNNEL_TOKEN=... ./$(basename "$0") -a ziti.example.com

  # 3. Quick Tunnel (TryCloudflare - no account; console publicly reachable, see --quick):
  ./$(basename "$0") --quick

  # 4. Tear down remote infrastructure completely over SSH:
  ./$(basename "$0") --ssh user@192.0.2.10 --teardown

  # 5. Stop/remove containers but keep PKI, identities and credentials:
  ./$(basename "$0") --ssh user@192.0.2.10 --teardown --keep-data

Note: SSH host keys are verified. Connect once with 'ssh user@host' to trust a new host first.
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--ssh)
            SSH_STREAM_HOST="$2"
            shift 2
            ;;
        -t|--token)
            TOKEN="$2"
            CLI_SECRET_USED=true
            shift 2
            ;;
        -a|--advertise-address)
            ADVERTISE_ADDRESS="$2"
            shift 2
            ;;
        -d|--dns-token)
            DNS_TOKEN="$2"
            CLI_SECRET_USED=true
            shift 2
            ;;
        -u|--user)
            ADMIN_USER="$2"
            shift 2
            ;;
        -p|--password)
            ADMIN_PASSWORD="$2"
            CLI_SECRET_USED=true
            shift 2
            ;;
        -r|--target)
            TARGET="$2"
            shift 2
            ;;
        -q|--quick)
            QUICK_MODE=true
            TOKEN=""
            shift
            ;;
        --teardown)
            TEARDOWN=true
            shift
            ;;
        --keep-data)
            KEEP_DATA=true
            shift
            ;;
        -y|--yes)
            ASSUME_YES=true
            shift
            ;;
        --check-token)
            CHECK_TOKEN_ONLY=true
            shift
            ;;
        --update-console)
            UPDATE_CONSOLE=true
            shift
            ;;
        --console)
            CONSOLE="${2:-}"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

case "$CONSOLE" in
    zac|bpc) ;;
    *) echo -e "${RED}Error: --console must be zac or bpc (got '$CONSOLE').${NC}"; exit 1 ;;
esac

# Sanitize and extract raw Cloudflare token if present
if [ -n "$TOKEN" ]; then
    if [[ "$TOKEN" =~ (eyJh[A-Za-z0-9_.+/-]+={0,2}) ]]; then
        TOKEN="${BASH_REMATCH[1]}"
    else
        TOKEN="${TOKEN#\'}"
        TOKEN="${TOKEN%\'}"
        TOKEN="${TOKEN#\"}"
        TOKEN="${TOKEN%\"}"
        TOKEN="$(echo "$TOKEN" | tr -d '\r\n ')"
    fi
fi
DNS_TOKEN="$(printf '%s' "$DNS_TOKEN" | tr -d '\r\n ')"

# ------------------------------------------------------------------------------
# Input validation (fail fast; these values are forwarded to remote shells,
# Ansible, and docker compose .env files)
# ------------------------------------------------------------------------------
die() {
    echo -e "${RED}Error: $*${NC}" >&2
    exit 1
}

HOST_REGEX='^[A-Za-z0-9]([A-Za-z0-9._@-]*[A-Za-z0-9])?$'
ADDR_REGEX='^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$'
USER_REGEX='^[A-Za-z0-9._@-]{1,64}$'
TOKEN_REGEX='^[A-Za-z0-9_.+/=-]*$'
PASSWORD_REGEX='^[][A-Za-z0-9!#%&()*+,./:;<=>?@^_{|}~-]{12,128}$'

validate_inputs() {
    if [ -n "$SSH_STREAM_HOST" ] && [[ ! "$SSH_STREAM_HOST" =~ $HOST_REGEX ]]; then
        die "invalid --ssh target '$SSH_STREAM_HOST' (expected user@host)."
    fi
    if [[ ! "$TARGET" =~ $HOST_REGEX ]]; then
        die "invalid --target '$TARGET'."
    fi
    if [ -n "$ADVERTISE_ADDRESS" ] && [[ ! "$ADVERTISE_ADDRESS" =~ $ADDR_REGEX ]]; then
        die "invalid --advertise-address '$ADVERTISE_ADDRESS' (expected a DNS hostname or IPv4 address)."
    fi
    if [[ ! "$ADMIN_USER" =~ $USER_REGEX ]]; then
        die "invalid admin username (allowed: letters, digits, . _ @ -; max 64 chars)."
    fi
    if [ -n "$ADMIN_PASSWORD" ] && [[ ! "$ADMIN_PASSWORD" =~ $PASSWORD_REGEX ]]; then
        die "admin password must be 12-128 chars and must not contain quotes, backslashes, '\$', backticks or whitespace."
    fi
    if [[ ! "$TOKEN" =~ $TOKEN_REGEX ]]; then
        die "Cloudflare Tunnel token contains unexpected characters."
    fi
    if [[ ! "$DNS_TOKEN" =~ $TOKEN_REGEX ]]; then
        die "Cloudflare DNS API token contains unexpected characters."
    fi
}
validate_inputs

# A Cloudflare Tunnel token is base64-encoded JSON: {"a":"<account tag>","t":"<tunnel UUID>","s":"<secret>"}.
# Decode it locally and check its shape, so a truncated or wrong value (for example the tunnel ID
# instead of the token) fails here instead of in a cloudflared restart loop. This cannot prove the
# secret is current; only Cloudflare can, when cloudflared connects.
check_tunnel_token() {
    local tok="$1" padded json tunnel_id
    padded="$(printf '%s' "$tok" | tr -- '-_' '+/')"
    while [ $(( ${#padded} % 4 )) -ne 0 ]; do padded="${padded}="; done
    json="$(printf '%s' "$padded" | base64 --decode 2>/dev/null)" ||
        die "Cloudflare Tunnel token is not valid base64 (truncated or mistyped?). Copy the full 'eyJh...' value from the tunnel's install command."
    [[ "$json" =~ \"a\":\"[0-9a-f]{32}\" ]] ||
        die "Cloudflare Tunnel token has no account tag. Make sure you copied the token, not the tunnel ID or an API token."
    [[ "$json" =~ \"s\":\"[A-Za-z0-9+/=]{20,}\" ]] ||
        die "Cloudflare Tunnel token has no secret (it may be truncated). Copy the full token again."
    [[ "$json" =~ \"t\":\"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\" ]] ||
        die "Cloudflare Tunnel token has no tunnel ID. Copy the full token again."
    tunnel_id="${BASH_REMATCH[1]}"
    echo -e "${GREEN}Cloudflare Tunnel token looks valid (tunnel ID ${tunnel_id}).${NC}"
}

# The admin console is build output and is not committed. scripts/fetch-console.sh installs the
# selected one (--console) unless a console of that kind is already present, for example one
# built with scripts/build-console.sh. On a remote host the console arrives in the SSH bundle
# (without the fetch script), so it is used as is.
ensure_console() {
    if [ ! -x "$ROOT_DIR/scripts/fetch-console.sh" ]; then
        [ -f "$ROOT_DIR/infrastructure/console/index.html" ] && return 0
        die "infrastructure/console/ is missing. Run scripts/fetch-console.sh infrastructure (or make console-fetch)."
    fi
    "$ROOT_DIR/scripts/fetch-console.sh" infrastructure --console "$CONSOLE"
}

# Teardown and console refresh act on an existing deployment: no token or advertise address.
MAINTENANCE=false
if [ "$TEARDOWN" = true ] || [ "$UPDATE_CONSOLE" = true ]; then
    MAINTENANCE=true
fi
[ "$TEARDOWN" = true ] && [ "$UPDATE_CONSOLE" = true ] && die "--teardown and --update-console cannot be combined."

if [ "${CHECK_TOKEN_ONLY:-false}" = true ]; then
    [ -n "$TOKEN" ] || die "no token to check. Set CLOUDFLARE_TUNNEL_TOKEN first."
    check_tunnel_token "$TOKEN"
    echo "Compare this ID with the tunnel in Cloudflare Zero Trust > Networks > Tunnels."
    exit 0
fi
if [ -n "$TOKEN" ] && [ "$QUICK_MODE" = false ] && [ "$MAINTENANCE" = false ]; then
    check_tunnel_token "$TOKEN"
fi

print_banner

if [ "$CLI_SECRET_USED" = true ]; then
    echo -e "${YELLOW}Warning: secrets passed as command-line arguments are visible to other local users"
    echo -e "         (ps, /proc) and may be saved in shell history. Prefer environment variables.${NC}\n"
fi

# Confirm destructive teardown before doing anything (locally, before any SSH hop)
TEARDOWN_ARGS=""
if [ "$UPDATE_CONSOLE" = true ]; then
    TEARDOWN_ARGS="--update-console"
fi
if [ "$TEARDOWN" = true ]; then
    TEARDOWN_ARGS="--teardown --yes"
    if [ "$KEEP_DATA" = true ]; then
        TEARDOWN_ARGS="$TEARDOWN_ARGS --keep-data"
    fi

    if [ "$ASSUME_YES" = false ]; then
        TEARDOWN_WHERE="${SSH_STREAM_HOST:-$TARGET}"
        echo -e "${RED}⚠  TEARDOWN requested for the OpenZiti infrastructure on: ${YELLOW}${TEARDOWN_WHERE}${NC}"
        if [ "$KEEP_DATA" = true ]; then
            echo -e "   Containers and network will be removed. PKI volume and /opt/openziti are ${GREEN}preserved${NC}."
        else
            echo -e "   Containers, network, PKI volume and /opt/openziti will be ${RED}permanently deleted${NC}."
            echo -e "   All enrolled identities (laptops, phones, apps) will stop working and must re-enroll."
        fi
        if [ ! -t 0 ]; then
            echo -e "${RED}Error: non-interactive session. Re-run with --yes to confirm teardown.${NC}"
            exit 1
        fi
        read -rp "Type 'yes' to continue: " CONFIRM
        if [ "$CONFIRM" != "yes" ]; then
            echo -e "${YELLOW}Teardown aborted.${NC}"
            exit 1
        fi
    fi
fi

# If SSH streaming is requested, copy files first, then run interactively with a full terminal
if [ -n "$SSH_STREAM_HOST" ]; then
    echo -e "${CYAN}======================================================================${NC}"
    if [ "$UPDATE_CONSOLE" = true ]; then
        echo -e "${CYAN}🖥  Refreshing the Admin Console on $SSH_STREAM_HOST over SSH...${NC}"
    elif [ "$TEARDOWN" = true ]; then
        echo -e "${CYAN}🧹 Tearing down infrastructure on $SSH_STREAM_HOST over SSH...${NC}"
    else
        echo -e "${CYAN}🚀 Deploying to $SSH_STREAM_HOST over SSH...${NC}"
    fi
    echo -e "${CYAN}   (Zero git clone or repository access required on remote host)${NC}"
    echo -e "${CYAN}======================================================================${NC}\n"

    REMOTE_FLAGS=""
    if [ "$QUICK_MODE" = true ]; then
        REMOTE_FLAGS="--quick"
    fi
    if [ -n "$TEARDOWN_ARGS" ]; then
        REMOTE_FLAGS="$REMOTE_FLAGS $TEARDOWN_ARGS"
    fi

    # Run a script on the remote host under bash, independent of the account's login shell
    # (fish/csh/dash). Scripts passed here must not contain single quotes; REMOTE_DIR is
    # validated to [A-Za-z0-9/-] so it is safe to embed unquoted.
    remote_bash() {
        local tty_flag=""
        if [ "$1" = "-t" ]; then
            tty_flag="-t"
            shift
        fi
        case "$1" in
            *"'"*) die "internal error: remote script must not contain single quotes." ;;
        esac
        ssh $tty_flag "$SSH_STREAM_HOST" "exec bash -c '$1'"
    }

    # Files the remote installer reads: this script plus the Ansible playbooks, the compose
    # template, the nginx config and the console. The console is needed only to deploy or refresh it.
    BUNDLE_PATHS=(deploy-ziti.sh infrastructure/ansible infrastructure/templates infrastructure/nginx)
    if [ "$TEARDOWN" = false ]; then
        ensure_console
        BUNDLE_PATHS+=(infrastructure/console)
    fi

    # Step 1: Create a private (0700) working directory on the remote host
    REMOTE_DIR="$(remote_bash 'umask 077 && mktemp -d /tmp/openziti-deploy-XXXXXX')"
    if [[ ! "$REMOTE_DIR" =~ ^/tmp/openziti-deploy-[A-Za-z0-9]+$ ]]; then
        die "could not create a private working directory on $SSH_STREAM_HOST."
    fi
    cleanup_remote() {
        remote_bash "rm -rf $REMOTE_DIR" >/dev/null 2>&1 || true
    }

    # Step 2: Transfer payload archive into the private directory (suppressing macOS extended attributes).
    # Only what the remote run needs is sent. Never the whole infrastructure/ directory: locally it
    # can hold git-ignored OpenTofu state, tfvars and provider binaries, which must not leave this machine.
    echo -e "${BLUE}▶ Packaging and transferring OpenZiti infrastructure bundle...${NC}"
    if ! COPYFILE_DISABLE=1 tar --no-xattrs --exclude='.DS_Store' --exclude='*.retry' -czf - -C "$ROOT_DIR" \
        "${BUNDLE_PATHS[@]}" | \
      remote_bash "cd $REMOTE_DIR && cat > payload.tar.gz && { tar --warning=no-unknown-keyword -xzf payload.tar.gz 2>/dev/null || tar -xzf payload.tar.gz; } && rm -f payload.tar.gz"; then
        cleanup_remote
        die "failed to transfer the infrastructure bundle."
    fi

    # Step 3: Send secrets over stdin into a 0600 file (never on a command line)
    if ! {
        printf 'export CLOUDFLARE_TUNNEL_TOKEN=%q\n' "$TOKEN"
        printf 'export CLOUDFLARE_DNS_API_TOKEN=%q\n' "$DNS_TOKEN"
        printf 'export OPENZITI_ADMIN_USER=%q\n' "$ADMIN_USER"
        printf 'export OPENZITI_ADMIN_PASSWORD=%q\n' "$ADMIN_PASSWORD"
        printf 'export OPENZITI_ADVERTISE_ADDRESS=%q\n' "$ADVERTISE_ADDRESS"
    } | remote_bash "umask 077 && cat > $REMOTE_DIR/.deploy-secrets"; then
        cleanup_remote
        die "failed to transfer deployment settings."
    fi

    # Step 4: Execute installer with an interactive pseudo-terminal (-t).
    # The secrets file is sourced and deleted before the installer starts.
    echo -e "${GREEN}✔ Transfer complete.${NC}"
    echo -e "${BLUE}▶ Launching interactive $( [ "$UPDATE_CONSOLE" = true ] && echo "console update" || { [ "$TEARDOWN" = true ] && echo teardown || echo installer; } ) on $SSH_STREAM_HOST...${NC}\n"

    set +e
    remote_bash -t "cd $REMOTE_DIR && . ./.deploy-secrets && rm -f ./.deploy-secrets && bash ./deploy-ziti.sh $REMOTE_FLAGS; RET=\$?; cd / && rm -rf $REMOTE_DIR; exit \$RET"
    RET=$?
    set -e
    if [ "$RET" -ne 0 ]; then
        cleanup_remote
    fi
    exit "$RET"
fi

# Detect macOS running locally
OS_NAME="$(uname -s)"
if [ "$OS_NAME" = "Darwin" ] && [ "$TARGET" = "localhost" ]; then
    echo -e "${YELLOW}Notice: Detected macOS local environment.${NC}"
    echo -e "The OpenZiti Infrastructure target is a Linux host (${CYAN}Fedora${NC} or ${CYAN}Ubuntu${NC})."
    echo -e "\nTo deploy directly to your remote Linux host without cloning the repo on it, run:"
    echo -e "  ${GREEN}./$(basename "$0") --ssh user@<host-ip> [options]${NC}\n"
    read -rp "Would you like to enter a remote SSH target now? (e.g. user@192.0.2.10 or leave empty to exit): " REMOTE_INPUT
    if [ -n "$REMOTE_INPUT" ]; then
        export CLOUDFLARE_TUNNEL_TOKEN="$TOKEN" CLOUDFLARE_DNS_API_TOKEN="$DNS_TOKEN" \
               OPENZITI_ADMIN_USER="$ADMIN_USER" OPENZITI_ADMIN_PASSWORD="$ADMIN_PASSWORD"
        REEXEC_ARGS=(--ssh "$REMOTE_INPUT" --console "$CONSOLE")
        [ -n "$ADVERTISE_ADDRESS" ] && REEXEC_ARGS+=(--advertise-address "$ADVERTISE_ADDRESS")
        [ "$QUICK_MODE" = true ] && REEXEC_ARGS+=(--quick)
        # TEARDOWN_ARGS holds only fixed flags (no user input), so word splitting is intended.
        # shellcheck disable=SC2206
        [ -n "$TEARDOWN_ARGS" ] && REEXEC_ARGS+=($TEARDOWN_ARGS)
        exec "$0" "${REEXEC_ARGS[@]}"
    else
        exit 0
    fi
fi

warn_quick_tunnel() {
    echo -e "${YELLOW}⚠  Quick Tunnel mode: there is NO Cloudflare Access in front of the Admin Console."
    echo -e "   Anyone who learns the random trycloudflare.com URL can reach the console login and the"
    echo -e "   OpenZiti management API behind it; only the admin password protects it.${NC}"
}

# Prompt for token if not supplied and quick mode not explicitly requested
if [ -z "$TOKEN" ] && [ "$QUICK_MODE" = false ] && [ "$MAINTENANCE" = false ]; then
    if [ ! -t 0 ]; then
        die "no Cloudflare Tunnel token supplied. Set CLOUDFLARE_TUNNEL_TOKEN, or pass --quick to explicitly opt in to an unauthenticated TryCloudflare Quick Tunnel."
    fi
    echo -e "${CYAN}Cloudflare Zero Trust Tunnel Configuration:${NC}"
    echo -e "  1) Enter a Cloudflare Zero Trust Tunnel Token (${GREEN}Recommended: custom domain + Cloudflare Access${NC})"
    echo -e "  2) Use TryCloudflare Quick Tunnel (${YELLOW}no account needed, console publicly reachable${NC})"
    MODE_CHOICE=""
    while [[ "$MODE_CHOICE" != "1" && "$MODE_CHOICE" != "2" ]]; do
        read -rp "Select mode [1/2]: " MODE_CHOICE
    done
    if [[ "$MODE_CHOICE" == "1" ]]; then
        read -rsp "Paste Cloudflare Tunnel Token: " TOKEN
        echo ""
        TOKEN="$(printf '%s' "$TOKEN" | tr -d '\r\n ')"
        [ -n "$TOKEN" ] || die "empty Cloudflare Tunnel token."
        [[ "$TOKEN" =~ $TOKEN_REGEX ]] || die "Cloudflare Tunnel token contains unexpected characters."
        check_tunnel_token "$TOKEN"
    else
        warn_quick_tunnel
        read -rp "Type 'yes' to continue in Quick Tunnel mode: " QUICK_CONFIRM
        [ "$QUICK_CONFIRM" = "yes" ] || die "aborted."
        QUICK_MODE=true
    fi
elif [ "$QUICK_MODE" = true ] && [ "$MAINTENANCE" = false ]; then
    warn_quick_tunnel
fi

# Prompt for advertised overlay hostname if not supplied
if [ -z "$ADVERTISE_ADDRESS" ] && [ "$MAINTENANCE" = false ] && [ -t 0 ]; then
    echo -e "${CYAN}OpenZiti Overlay Advertised Hostname (ports 1280 & 8444):${NC}"
    read -rp "Public DNS hostname or IP for client/router mTLS [default: ziti-controller.local]: " ADV_INPUT
    ADVERTISE_ADDRESS="${ADV_INPUT:-ziti-controller.local}"
    [[ "$ADVERTISE_ADDRESS" =~ $ADDR_REGEX ]] || die "invalid advertised hostname '$ADVERTISE_ADDRESS'."
    if [ "$ADVERTISE_ADDRESS" != "ziti-controller.local" ] && [ -z "$DNS_TOKEN" ]; then
        read -rsp "Optional Cloudflare DNS API Token (Zone.DNS:Edit only) for automatic DDNS updates (Enter to skip): " DNS_TOKEN
        echo ""
        DNS_TOKEN="$(printf '%s' "$DNS_TOKEN" | tr -d '\r\n ')"
        [[ "$DNS_TOKEN" =~ $TOKEN_REGEX ]] || die "Cloudflare DNS API token contains unexpected characters."
    fi
fi
ADVERTISE_ADDRESS="${ADVERTISE_ADDRESS:-ziti-controller.local}"

# With no password supplied, Ansible reuses the one stored by a previous deployment or,
# on first deploy, generates one on the host. It is never printed or sent over SSH.
PASSWORD_GENERATED=false
[ -z "$ADMIN_PASSWORD" ] && PASSWORD_GENERATED=true

# Function to ensure Ansible is installed on the local system
ensure_ansible_local() {
    if command -v ansible-playbook >/dev/null 2>&1; then
        echo -e "${GREEN}✔ Ansible is already installed. ($(ansible-playbook --version | head -n 1))${NC}"
        return 0
    fi

    # Check if sudo requires password authentication
    if ! sudo -n true 2>/dev/null; then
        echo -e "${YELLOW}Administrator (sudo) privileges are required to install Ansible.${NC}"
        sudo -v
    fi

    echo -e "${YELLOW}Ansible is not installed. Installing automatically...${NC}"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian|pop|linuxmint)
                echo -e "${BLUE}Detected Debian/Ubuntu family ($ID). Installing Ansible via apt...${NC}"
                sudo apt-get update -y
                sudo apt-get install -y ansible curl git
                ;;
            fedora|rhel|centos|rocky|alma|almalinux|ol)
                echo -e "${BLUE}Detected RedHat/Fedora family ($ID). Installing Ansible via dnf...${NC}"
                sudo dnf install -y ansible-core curl git
                ;;
            *)
                echo -e "${RED}Unsupported OS: $ID. Please install Ansible manually: https://docs.ansible.com/${NC}"
                exit 1
                ;;
        esac
    else
        echo -e "${RED}Unable to detect OS from /etc/os-release.${NC}"
        exit 1
    fi
}

# Deploy logic
EXTRA_BECOME_FLAG=""
if [ "$TARGET" = "localhost" ] || [ "$TARGET" = "127.0.0.1" ]; then
    echo -e "${CYAN}Preparing local $( [ "$UPDATE_CONSOLE" = true ] && echo "console update" || { [ "$TEARDOWN" = true ] && echo teardown || echo deployment; } ) on this Linux host...${NC}"
    # Check if user requires a sudo password for Ansible become operations
    if ! (sudo -k && sudo -n true 2>/dev/null); then
        EXTRA_BECOME_FLAG="--ask-become-pass"
    fi
    ensure_ansible_local
    INVENTORY="localhost,"
    EXTRA_CONN="-c local"
else
    echo -e "${CYAN}Preparing remote deployment to $TARGET over SSH...${NC}"
    if ! command -v ansible-playbook >/dev/null 2>&1; then
        ensure_ansible_local
    fi
    INVENTORY="$TARGET,"
    EXTRA_CONN=""
fi

if [ "$TEARDOWN" = false ]; then
    ensure_console
fi

if [ "$UPDATE_CONSOLE" = true ]; then
    echo -e "\n${BLUE}▶ Running Ansible Console Update Playbook...${NC}\n"
    ANSIBLE_CONFIG="$ROOT_DIR/infrastructure/ansible/ansible.cfg" ansible-playbook \
        -i "$INVENTORY" \
        $EXTRA_CONN \
        $EXTRA_BECOME_FLAG \
        "$ROOT_DIR/infrastructure/ansible/update-console.yml"
    echo -e "\n${GREEN}✔ Admin Console refreshed.${NC} $( { sed -n 's/^name=//p' "$ROOT_DIR/infrastructure/console/.console-source" 2>/dev/null; [ -f "$ROOT_DIR/infrastructure/console/BUILD-INFO.txt" ] && head -n 3 "$ROOT_DIR/infrastructure/console/BUILD-INFO.txt"; } | tr '\n' ' ' )"
    exit 0
fi

echo -e "\n${BLUE}======================================================${NC}"
if [ "$TEARDOWN" = true ]; then
    echo -e "${BLUE}▶ Running Ansible Teardown Playbook...${NC}"
else
    echo -e "${BLUE}▶ Running Ansible Deployment Playbook...${NC}"
fi
echo -e "${BLUE}======================================================${NC}\n"

if [ "$TEARDOWN" = true ]; then
    ANSIBLE_CONFIG="$ROOT_DIR/infrastructure/ansible/ansible.cfg" ansible-playbook \
        -i "$INVENTORY" \
        $EXTRA_CONN \
        $EXTRA_BECOME_FLAG \
        "$ROOT_DIR/infrastructure/ansible/teardown.yml" \
        -e "keep_data=$KEEP_DATA"

    echo -e "\n${GREEN}======================================================${NC}"
    echo -e "${GREEN}✔ OPENZITI INFRASTRUCTURE TORN DOWN SUCCESSFULLY!${NC}"
    echo -e "${GREEN}======================================================${NC}"
    if [ "$KEEP_DATA" = true ]; then
        echo -e "PKI volume & credentials:     ${GREEN}preserved${NC} (redeploy to resume)"
    else
        echo -e "PKI volume & credentials:     ${RED}deleted${NC}"
    fi
    echo -e "Not reverted:                 ${YELLOW}container runtime, firewall hardening${NC}"
    echo -e "Cloudflare cleanup:           ${CYAN}cd infrastructure/opentofu && tofu destroy${NC}"
    echo -e "                              (or delete tunnel/DNS/Access app in the dashboard)"
    echo -e "======================================================\n"
    exit 0
fi

# Secrets reach Ansible via environment variables read by vars/main.yml (lookup('env')).
# They never appear in the ansible-playbook argv, and lookup results are treated as
# unsafe by Ansible, so they are never evaluated as Jinja templates.
ALLOW_QUICK_TUNNEL=false
if [ "$QUICK_MODE" = true ]; then
    ALLOW_QUICK_TUNNEL=true
fi
CLOUDFLARE_TUNNEL_TOKEN="$TOKEN" \
CLOUDFLARE_DNS_API_TOKEN="$DNS_TOKEN" \
OPENZITI_ADMIN_USER="$ADMIN_USER" \
OPENZITI_ADMIN_PASSWORD="$ADMIN_PASSWORD" \
OPENZITI_ADVERTISE_ADDRESS="$ADVERTISE_ADDRESS" \
ANSIBLE_CONFIG="$ROOT_DIR/infrastructure/ansible/ansible.cfg" ansible-playbook \
    -i "$INVENTORY" \
    $EXTRA_CONN \
    $EXTRA_BECOME_FLAG \
    "$ROOT_DIR/infrastructure/ansible/playbook.yml" \
    -e "allow_quick_tunnel=$ALLOW_QUICK_TUNNEL"

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN}✔ OPENZITI INFRASTRUCTURE DEPLOYED SUCCESSFULLY!${NC}"
echo -e "${GREEN}======================================================${NC}"
echo -e "OpenZiti Admin Console (ZAC): ${CYAN}http://127.0.0.1:8080/ (loopback + Cloudflare Tunnel)${NC}"
echo -e "OpenZiti Client & Ctrl Plane: ${CYAN}https://${ADVERTISE_ADDRESS}:1280/ (public mTLS)${NC}"
echo -e "OpenZiti Edge Router:         ${CYAN}tls://${ADVERTISE_ADDRESS}:8444 (public mTLS)${NC}"
echo -e "OpenZiti Management API:      ${GREEN}internal-only (1281, reachable solely via ZAC)${NC}"
if [ -n "$DNS_TOKEN" ] && [ "$ADVERTISE_ADDRESS" != "ziti-controller.local" ]; then
    echo -e "Cloudflare DDNS Updater:      ${GREEN}ACTIVE (openziti-ddns keeps ${ADVERTISE_ADDRESS} synced)${NC}"
fi
echo -e "Administrator Username:       ${YELLOW}${ADMIN_USER}${NC}"
if [ "$PASSWORD_GENERATED" = true ]; then
    echo -e "Administrator Password:       ${YELLOW}stored on the host (not printed)${NC}"
else
    echo -e "Administrator Password:       ${YELLOW}the password you supplied${NC}"
fi
echo -e "Credentials file (0600):      ${BLUE}/opt/openziti/.ziti-credentials${NC}"
echo -e "                              view on the host with: ${CYAN}sudo cat /opt/openziti/.ziti-credentials${NC}"
if [ "$QUICK_MODE" = true ]; then
    echo -e "Console Ingress:              ${YELLOW}TryCloudflare Quick Tunnel (NO Cloudflare Access)${NC}"
else
    echo -e "Protected Console Ingress:    ${GREEN}Cloudflare Tunnel (port 8080 loopback-only) - enable Cloudflare Access!${NC}"
fi
echo -e "======================================================\n"
