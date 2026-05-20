#!/usr/bin/env bash
#
# Total VFD Odoo module — friendly installer / updater
# Works with Docker or standard (non-Docker) Odoo on Linux/macOS.
#
# Usage: ./install-total-vfd.sh
# One-line (no clone): curl -fsSL https://raw.githubusercontent.com/Thajr100/total_vfd_installer/main/install-total-vfd.sh | bash
# Optional: copy config.example.env to .env and set DEFAULT_ZIP_URL
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${TOTAL_VFD_INSTALLER_CONFIG:-$HOME/.config/total_vfd/installer.conf}"
STATE_DIR="${TMPDIR:-/tmp}/total_vfd_installer_$$"
MODULE_DIR_NAME="total_vfd"
ZIP_NAME="total_vfd.zip"

# --- styling (only when interactive terminal) ---
if [[ -t 1 ]]; then
  BOLD='\033[1m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  RED='\033[0;31m'
  CYAN='\033[0;36m'
  RESET='\033[0m'
else
  BOLD='' GREEN='' YELLOW='' RED='' CYAN='' RESET=''
fi

info()  { printf '%b\n' "${CYAN}→${RESET} $*"; }
ok()    { printf '%b\n' "${GREEN}✓${RESET} $*"; }
warn()  { printf '%b\n' "${YELLOW}!${RESET} $*"; }
err()   { printf '%b\n' "${RED}✗${RESET} $*" >&2; }
title() { printf '\n%b%b\n%b\n' "$BOLD" "$*" "$RESET" '============================================'; }

cleanup() {
  [[ -d "$STATE_DIR" ]] && rm -rf "$STATE_DIR"
}
trap cleanup EXIT

load_env() {
  if [[ -f "$SCRIPT_DIR/.env" ]]; then
    # shellcheck disable=SC1091
    set -a && source "$SCRIPT_DIR/.env" && set +a
  fi
}

load_saved_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  fi
}

save_config() {
  mkdir -p "$(dirname "$CONFIG_FILE")"
  cat >"$CONFIG_FILE" <<EOF
# Saved by install-total-vfd.sh — safe to edit
INSTALL_MODE="${INSTALL_MODE:-}"
ZIP_URL="${ZIP_URL:-}"
DOCKER_CONTAINER="${DOCKER_CONTAINER:-}"
DOCKER_ADDONS_PATH="${DOCKER_ADDONS_PATH:-}"
DOCKER_ODOO_USER="${DOCKER_ODOO_USER:-odoo}"
NATIVE_ADDONS_PATH="${NATIVE_ADDONS_PATH:-}"
NATIVE_ODOO_USER="${NATIVE_ODOO_USER:-odoo}"
NATIVE_RESTART_CMD="${NATIVE_RESTART_CMD:-}"
EOF
  chmod 600 "$CONFIG_FILE" 2>/dev/null || true
}

require_commands() {
  local missing=()
  for cmd in curl unzip; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing required tools: ${missing[*]}"
    err "Install them first (e.g. apt install curl unzip)."
    exit 1
  fi
}

ask() {
  # ask "Prompt" "default"
  local prompt="$1"
  local default="${2:-}"
  local reply=""
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " reply
    reply="${reply:-$default}"
  else
    while [[ -z "$reply" ]]; do
      read -r -p "$prompt: " reply
    done
  fi
  printf '%s' "$reply"
}

ask_yes_no() {
  # ask_yes_no "Question" default_y|n
  local prompt="$1"
  local default="${2:-y}"
  local hint="Y/n"
  [[ "$default" == "n" ]] && hint="y/N"
  local reply=""
  read -r -p "$prompt ($hint): " reply
  reply="${reply:-$default}"
  [[ "$reply" =~ ^[Yy] ]]
}

pause_enter() {
  read -r -p "Press Enter to continue..."
}

print_odoo_ui_steps() {
  local action="$1" # install | upgrade
  local verb="Install"
  [[ "$action" == "upgrade" ]] && verb="Upgrade"
  title "Next steps — in your Odoo web browser"
  cat <<EOF
  1. Log in as Administrator.
  2. Open Settings → turn on Developer mode (if needed).
  3. Go to Apps → click "Update Apps List".
  4. Search: Total VFD Fiscalisation
  5. Click ${verb} (do NOT use "Import Module").

If you already tried Import Module and see errors, uninstall that copy first,
then run this installer again and use Install from Apps.
EOF
  printf '\n'
}

get_zip_url() {
  local url="${ZIP_URL:-${DEFAULT_ZIP_URL:-}}"
  if [[ -z "$url" ]]; then
    title "Download link"
    echo "Your vendor should give you a web link (HTTPS) to total_vfd.zip."
    url="$(ask "Paste the full URL to total_vfd.zip" "")"
  else
    info "Using zip URL: $url"
    if ! ask_yes_no "Use this download URL?" "y"; then
      url="$(ask "Paste the full URL to total_vfd.zip" "$url")"
    fi
  fi
  ZIP_URL="$url"
}

download_zip() {
  mkdir -p "$STATE_DIR"
  local dest="$STATE_DIR/$ZIP_NAME"
  title "Downloading module"
  info "From: $ZIP_URL"
  if ! curl -fsSL --connect-timeout 30 --max-time 600 -o "$dest" "$ZIP_URL"; then
    err "Download failed. Check the URL and your internet connection."
    exit 1
  fi
  if [[ ! -s "$dest" ]]; then
    err "Downloaded file is empty."
    exit 1
  fi
  ok "Downloaded $(du -h "$dest" | awk '{print $1}') → $dest"
  echo "$dest"
}

verify_zip() {
  local zip_path="$1"
  if ! unzip -l "$zip_path" | grep -q "${MODULE_DIR_NAME}/__manifest__.py"; then
    err "This zip does not look like a Total VFD Odoo module."
    err "Expected ${MODULE_DIR_NAME}/__manifest__.py inside the archive."
    exit 1
  fi
  ok "Zip contents look valid."
}

choose_install_mode() {
  title "How is Odoo running on this server?"
  echo "  1) Docker — Odoo runs inside a container (common on VPS/cloud)"
  echo "  2) Normal install — files on the server, no Docker"
  echo ""
  local choice
  choice="$(ask "Enter 1 or 2" "${INSTALL_MODE:-1}")"
  case "$choice" in
    1|docker|Docker) INSTALL_MODE="docker" ;;
    2|native|normal|Normal) INSTALL_MODE="native" ;;
    *)
      err "Invalid choice."
      exit 1
      ;;
  esac
}

collect_docker_settings() {
  title "Docker settings"
  DOCKER_CONTAINER="$(ask "Odoo container name" "${DOCKER_CONTAINER:-odoo}")"
  DOCKER_ADDONS_PATH="$(ask "Addons folder inside the container" "${DOCKER_ADDONS_PATH:-/mnt/extra-addons}")"
  DOCKER_ODOO_USER="$(ask "Linux user that owns Odoo files in the container" "${DOCKER_ODOO_USER:-odoo}")"

  if ! docker ps --format '{{.Names}}' | grep -qx "$DOCKER_CONTAINER"; then
    warn "Container '$DOCKER_CONTAINER' is not running (or Docker is not available)."
    if ! ask_yes_no "Continue anyway?" "n"; then
      exit 1
    fi
  fi
}

collect_native_settings() {
  title "Normal (non-Docker) settings"
  NATIVE_ADDONS_PATH="$(ask "Full path to your Odoo custom addons folder" "${NATIVE_ADDONS_PATH:-/opt/odoo/custom-addons}")"
  NATIVE_ODOO_USER="$(ask "Linux user that should own the module files" "${NATIVE_ODOO_USER:-odoo}")"
  NATIVE_RESTART_CMD="$(ask "Command to restart Odoo" "${NATIVE_RESTART_CMD:-sudo systemctl restart odoo}")"

  if [[ ! -d "$(dirname "$NATIVE_ADDONS_PATH")" ]]; then
    warn "Parent directory does not exist: $(dirname "$NATIVE_ADDONS_PATH")"
    ask_yes_no "Create addons path?" "y" && sudo mkdir -p "$NATIVE_ADDONS_PATH" || true
  fi
}

deploy_to_docker() {
  local zip_path="$1"
  local target="${DOCKER_ADDONS_PATH%/}/${MODULE_DIR_NAME}"
  title "Installing into Docker container: $DOCKER_CONTAINER"

  docker cp "$zip_path" "${DOCKER_CONTAINER}:/tmp/${ZIP_NAME}"
  ok "Copied zip into container"

  docker exec "$DOCKER_CONTAINER" sh -c "
    set -e
    rm -rf '${target}'
    unzip -o -q '/tmp/${ZIP_NAME}' -d '${DOCKER_ADDONS_PATH%/}'
    chown -R '${DOCKER_ODOO_USER}:${DOCKER_ODOO_USER}' '${target}'
    rm -f '/tmp/${ZIP_NAME}'
  "
  ok "Module extracted to ${target}"

  info "Restarting container..."
  docker restart "$DOCKER_CONTAINER" >/dev/null
  ok "Container restarted."
}

deploy_to_native() {
  local zip_path="$1"
  local target="${NATIVE_ADDONS_PATH%/}/${MODULE_DIR_NAME}"
  title "Installing on server (non-Docker)"

  local parent="${NATIVE_ADDONS_PATH%/}"
  if [[ ! -w "$parent" ]] && [[ "$(id -u)" -ne 0 ]]; then
    info "Need elevated permissions for $parent"
    sudo mkdir -p "$parent"
    sudo rm -rf "$target"
    sudo unzip -o -q "$zip_path" -d "$parent"
    sudo chown -R "${NATIVE_ODOO_USER}:${NATIVE_ODOO_USER}" "$target"
  else
    mkdir -p "$parent"
    rm -rf "$target"
    unzip -o -q "$zip_path" -d "$parent"
    chown -R "${NATIVE_ODOO_USER}:${NATIVE_ODOO_USER}" "$target" 2>/dev/null \
      || sudo chown -R "${NATIVE_ODOO_USER}:${NATIVE_ODOO_USER}" "$target"
  fi
  ok "Module extracted to ${target}"

  info "Restarting Odoo: $NATIVE_RESTART_CMD"
  eval "$NATIVE_RESTART_CMD"
  ok "Restart command completed."
}

install_qr_packages_docker() {
  collect_docker_settings
  title "Python packages for QR codes (Docker)"
  warn "Fiscalisation works without these; PDF QR images need qrcode + Pillow."
  if ! ask_yes_no "Install qrcode and Pillow inside container ${DOCKER_CONTAINER}?" "y"; then
    return 0
  fi
  docker exec -u root "$DOCKER_CONTAINER" python3 -m pip install --break-system-packages qrcode Pillow \
    || docker exec -u root "$DOCKER_CONTAINER" python3 -m pip install qrcode Pillow
  ok "QR packages installed (or already present)."
}

install_qr_packages_native() {
  title "Python packages for QR codes (non-Docker)"
  warn "Use the same Python environment that runs Odoo."
  local py
  py="$(ask "Python command (e.g. python3 or /opt/odoo/venv/bin/python)" "python3")"
  if ! ask_yes_no "Run: $py -m pip install qrcode Pillow ?" "y"; then
    return 0
  fi
  sudo -H "$py" -m pip install qrcode Pillow 2>/dev/null \
    || "$py" -m pip install --user qrcode Pillow
  ok "Done. Restart Odoo if it was running during install."
}

run_install_or_update() {
  local action="$1" # install | update
  load_saved_config
  require_commands
  load_env

  title "Total VFD — Odoo module ${action}"
  echo "This wizard copies the module to your server and restarts Odoo."
  echo "You will still click Install or Upgrade inside the Odoo website."
  printf '\n'

  if [[ "$action" == "update" ]] && [[ -f "$CONFIG_FILE" ]]; then
    info "Found saved settings: $CONFIG_FILE"
    if ask_yes_no "Use saved Docker/native settings from last time?" "y"; then
      INSTALL_MODE="${INSTALL_MODE:-}"
    else
      unset INSTALL_MODE DOCKER_CONTAINER DOCKER_ADDONS_PATH NATIVE_ADDONS_PATH
    fi
  fi

  choose_install_mode
  get_zip_url

  if [[ "$INSTALL_MODE" == "docker" ]]; then
    command -v docker >/dev/null 2>&1 || { err "Docker not found."; exit 1; }
    collect_docker_settings
  else
    collect_native_settings
  fi

  if ! ask_yes_no "Ready to download and ${action} now?" "y"; then
    warn "Cancelled."
    exit 0
  fi

  local zip_path
  zip_path="$(download_zip)"
  verify_zip "$zip_path"

  if [[ "$INSTALL_MODE" == "docker" ]]; then
    deploy_to_docker "$zip_path"
  else
    deploy_to_native "$zip_path"
  fi

  save_config
  ok "Files are on the server and Odoo was restarted."

  if [[ "$action" == "install" ]]; then
    print_odoo_ui_steps "install"
  else
    print_odoo_ui_steps "upgrade"
  fi

  if ask_yes_no "Install optional QR Python packages now?" "n"; then
    if [[ "$INSTALL_MODE" == "docker" ]]; then
      install_qr_packages_docker
    else
      install_qr_packages_native
    fi
  fi

  ok "All done. Settings saved to: $CONFIG_FILE"
}

show_saved_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    warn "No saved config yet. Run Install or Update first."
    return
  fi
  title "Saved configuration"
  cat "$CONFIG_FILE"
  printf '\n'
}

main_menu() {
  load_env
  while true; do
    title "Total VFD installer"
    echo "  1) Install module (first time on this server)"
    echo "  2) Update module (new zip from your vendor)"
    echo "  3) Install QR Python packages only (qrcode + Pillow)"
    echo "  4) Show saved settings"
    echo "  5) Help / what this does not do"
    echo "  6) Exit"
    printf '\n'
    local choice
    choice="$(ask "Choose an option" "1")"
    case "$choice" in
      1) run_install_or_update "install" ; pause_enter ;;
      2) run_install_or_update "update" ; pause_enter ;;
      3)
        load_saved_config
        if [[ -z "${INSTALL_MODE:-}" ]]; then
          choose_install_mode
        fi
        if [[ "$INSTALL_MODE" == "docker" ]]; then
          install_qr_packages_docker
        else
          install_qr_packages_native
        fi
        save_config
        pause_enter
        ;;
      4) show_saved_config ; pause_enter ;;
      5)
        title "Help"
        cat <<'EOF'
  • You need SSH access to the Odoo server (or run this on that machine).
  • You need a download URL for total_vfd.zip from your vendor.
  • This script does NOT configure license or Total VFD API — do that in Odoo Settings.
  • Never use Apps → Import Module for Total VFD (use Install from addons path).
  • For updates: run option 2, then Upgrade the app in Odoo Apps.
EOF
        pause_enter
        ;;
      6|0|q|Q) ok "Goodbye."; exit 0 ;;
      *) warn "Unknown option." ;;
    esac
  done
}

# Non-interactive quick mode:
#   ./install-total-vfd.sh --update --docker --zip-url https://... --container odoo
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
Usage:
  $0                    Interactive menu (recommended)
  $0 --install          Skip menu, run install wizard
  $0 --update           Skip menu, run update wizard
  $0 --update --docker --zip-url URL --container NAME --addons-path /mnt/extra-addons

One-line install (download and run, no git clone):
  curl -fsSL https://raw.githubusercontent.com/Thajr100/total_vfd_installer/main/install-total-vfd.sh | bash

Environment / files:
  .env                  DEFAULT_ZIP_URL=...
  \$CONFIG_FILE         Default: ~/.config/total_vfd/installer.conf
EOF
  exit 0
fi

if [[ "${1:-}" == "--install" ]]; then
  run_install_or_update "install"
  exit 0
fi

if [[ "${1:-}" == "--update" ]]; then
  load_env
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --docker) INSTALL_MODE="docker" ;;
      --native) INSTALL_MODE="native" ;;
      --zip-url) ZIP_URL="$2"; shift ;;
      --container) DOCKER_CONTAINER="$2"; shift ;;
      --addons-path)
        DOCKER_ADDONS_PATH="$2"
        NATIVE_ADDONS_PATH="$2"
        shift
        ;;
    esac
    shift
  done
  run_install_or_update "update"
  exit 0
fi

main_menu
