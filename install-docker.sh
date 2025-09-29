#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

LOG_FILE="/var/log/docker-install.log"
SCRIPT_NAME="$(basename "$0")"
ASSUME_YES=0
CHANNEL="stable"
INSTALL_COMPOSE=1
TARGET_USER=""
SKIP_GROUP_ADD=0
RUN_VERIFY=0
VERIFY_RUN_SET=0
DRY_RUN=0
DO_UNINSTALL=0
VERBOSE=0
WSL=0
OS_FAMILY=""
OS_NAME=""
OS_VERSION_ID=""
PACKAGE_MANAGER=""
SYSTEMD_AVAILABLE=1
SUPPORTED_CHANNELS=(stable test)

# shellcheck disable=SC2317
cleanup() {
    local exit_code=$?
    trap - ERR EXIT
    if [[ $exit_code -ne 0 ]]; then
        err "Script exited with status $exit_code"
    fi
}

# shellcheck disable=SC2317
on_error() {
    local exit_code=$?
    local line_no=${BASH_LINENO[0]:-}
    local func=${FUNCNAME[1]:-main}
    echo "[ERROR] ${SCRIPT_NAME}: line ${line_no} (${func}) exited with status ${exit_code}" >&2
}

trap cleanup EXIT
trap on_error ERR

log() {
    local msg="$1"
    printf '[INFO] %s\n' "$msg"
}

warn() {
    local msg="$1"
    printf '[WARN] %s\n' "$msg" >&2
}

err() {
    local msg="$1"
    printf '[ERROR] %s\n' "$msg" >&2
}

die() {
    err "$1"
    exit 1
}

run_cmd() {
    if [[ $DRY_RUN -eq 1 ]]; then
        log "[dry-run] $*"
        return 0
    fi
    if [[ $VERBOSE -eq 1 ]]; then
        log "Running: $*"
    fi
    if ! "$@"; then
        local status=$?
        return $status
    fi
}

run_root_cmd() {
    if [[ $DRY_RUN -eq 1 ]]; then
        log "[dry-run] (root) $*"
        return 0
    fi
    if [[ $(id -u) -eq 0 ]]; then
        if [[ $VERBOSE -eq 1 ]]; then
            log "Running (root): $*"
        fi
        if ! "$@"; then
            local status=$?
            return $status
        fi
    else
        if [[ -z ${SUDO_CMD:-} ]]; then
            die "This action requires sudo privileges."
        fi
        if [[ $VERBOSE -eq 1 ]]; then
            log "Running (sudo): $*"
        fi
        if ! "$SUDO_CMD" "$@"; then
            local status=$?
            return $status
        fi
    fi
}

require_root_or_sudo() {
    if [[ $(id -u) -eq 0 ]]; then
        return
    fi
    if command -v sudo >/dev/null 2>&1; then
        export SUDO_CMD="sudo"
    else
        die "This script requires root privileges or sudo."
    fi
}

ensure_logfile() {
    if [[ $DRY_RUN -eq 1 ]]; then
        return
    fi
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    if [[ $(id -u) -ne 0 ]]; then
        if [[ -z ${SUDO_CMD:-} ]]; then
            die "Cannot write log file without sudo privileges."
        fi
        if [[ $DRY_RUN -eq 0 ]]; then
            run_root_cmd mkdir -p "$log_dir"
            run_root_cmd touch "$LOG_FILE"
            run_root_cmd chmod 600 "$LOG_FILE"
        fi
        exec > >(tee >( "$SUDO_CMD" tee -a "$LOG_FILE" >/dev/null)) 2>&1
    else
        mkdir -p "$log_dir"
        touch "$LOG_FILE"
        chmod 600 "$LOG_FILE"
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--assume-yes)
                ASSUME_YES=1
                shift
                ;;
            --channel=*)
                CHANNEL="${1#*=}"
                shift
                ;;
            --with-compose)
                INSTALL_COMPOSE=1
                shift
                ;;
            --no-compose)
                INSTALL_COMPOSE=0
                shift
                ;;
            --user=*)
                TARGET_USER="${1#*=}"
                shift
                ;;
            --skip-group-add)
                SKIP_GROUP_ADD=1
                shift
                ;;
            --verify-run)
                RUN_VERIFY=1
                VERIFY_RUN_SET=1
                shift
                ;;
            --no-verify-run)
                RUN_VERIFY=0
                VERIFY_RUN_SET=1
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --uninstall)
                DO_UNINSTALL=1
                shift
                ;;
            --verbose)
                VERBOSE=1
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                die "Unknown argument: $1"
                ;;
        esac
    done

    local valid=0
    for c in "${SUPPORTED_CHANNELS[@]}"; do
        if [[ $c == "$CHANNEL" ]]; then
            valid=1
            break
        fi
    done
    if [[ $valid -eq 0 ]]; then
        die "Invalid channel '$CHANNEL'. Supported: ${SUPPORTED_CHANNELS[*]}"
    fi
}

usage() {
    cat <<'USAGE'
Usage: install-docker.sh [options]

Options:
  -y, --assume-yes          Automatic yes to prompts.
      --channel=stable|test Docker repository channel (default: stable).
      --with-compose         Install Docker Compose plugin (default).
      --no-compose           Skip Docker Compose plugin.
      --user=<name>          User to add to docker group.
      --skip-group-add       Do not modify user groups.
      --verify-run           Run docker hello-world after install.
      --no-verify-run        Skip docker hello-world.
      --dry-run              Print actions without executing.
      --uninstall            Remove Docker packages and repositories.
      --verbose              Increase logging verbosity.
      --help                 Show this help message.
USAGE
}

check_prereqs() {
    local tools=(lsb_release curl gpg)
    for t in "${tools[@]}"; do
        if ! command -v "$t" >/dev/null 2>&1; then
            warn "Command '$t' not found. Some functionality may be limited."
        fi
    done
}

read_os_release() {
    if [[ ! -r /etc/os-release ]]; then
        die "Cannot read /etc/os-release; unsupported system."
    fi
    # shellcheck disable=SC1091
    source /etc/os-release
    OS_NAME=${ID:-unknown}
    OS_VERSION_ID=${VERSION_ID:-unknown}
    case "$OS_NAME" in
        debian|ubuntu|pop|elementary)
            OS_FAMILY="debian"
            PACKAGE_MANAGER="apt"
            ;;
        rhel|rocky|almalinux|ol|centos)
            OS_FAMILY="rhel"
            PACKAGE_MANAGER="dnf"
            ;;
        fedora)
            OS_FAMILY="fedora"
            PACKAGE_MANAGER="dnf"
            ;;
        amzn)
            OS_FAMILY="amazon"
            PACKAGE_MANAGER="yum"
            ;;
        opensuse-leap|opensuse-tumbleweed|sles)
            OS_FAMILY="suse"
            PACKAGE_MANAGER="zypper"
            ;;
        arch|manjaro)
            OS_FAMILY="arch"
            PACKAGE_MANAGER="pacman"
            ;;
        *)
            die "Unsupported distribution '$OS_NAME'."
            ;;
    esac
}

validate_supported_versions() {
    case "$OS_FAMILY" in
        debian)
            case "$OS_NAME" in
                debian)
                    [[ $OS_VERSION_ID =~ ^(11|12)$ ]] || die "Unsupported Debian version '$OS_VERSION_ID'."
                    ;;
                ubuntu)
                    case "$OS_VERSION_ID" in
                        20.04|22.04|24.04) : ;;
                        *) die "Unsupported Ubuntu version '$OS_VERSION_ID'." ;;
                    esac
                    ;;
                *)
                    die "Unsupported Debian-based distribution '$OS_NAME'."
                    ;;
            esac
            ;;
        rhel)
            case "$OS_NAME" in
                rhel|rocky|almalinux|centos|ol)
                    case "$OS_VERSION_ID" in
                        8*|9*) : ;;
                        *) die "Unsupported RHEL-based version '$OS_VERSION_ID'." ;;
                    esac
                    ;;
                *) die "Unsupported RHEL-like distribution '$OS_NAME'." ;;
            esac
            ;;
        fedora)
            [[ ${OS_VERSION_ID%%.*} -ge 38 ]] || die "Fedora $OS_VERSION_ID is not supported (need 38+)."
            ;;
        amazon)
            [[ $OS_VERSION_ID == "2" ]] || die "Only Amazon Linux 2 is supported."
            ;;
        suse)
            :
            ;;
        arch)
            :
            ;;
        *)
            die "Unsupported OS family '$OS_FAMILY'."
            ;;
    esac
}

detect_wsl() {
    if grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null; then
        WSL=1
        warn "WSL detected. Docker service management is limited; ensure Docker Desktop integration or alternative service."
    fi
}

detect_systemd() {
    if [[ $WSL -eq 1 ]]; then
        SYSTEMD_AVAILABLE=0
        return
    fi
    if ! command -v systemctl >/dev/null 2>&1; then
        SYSTEMD_AVAILABLE=0
        warn "systemctl not available; skipping service enable/start."
        return
    fi
    if ! systemctl is-system-running >/dev/null 2>&1; then
        warn "systemd not fully running; service enable may not work."
    fi
}

ensure_channel_supported() {
    if [[ $CHANNEL == "test" ]]; then
        warn "Test channel selected; using nightly builds where available."
    fi
}

backup_file() {
    local file="$1"
    if [[ -f $file ]]; then
        local ts
        ts=$(date +%Y%m%d%H%M%S)
        run_root_cmd cp "$file" "$file.bak.$ts"
    fi
}

# Reusable key verification
verify_and_install_key() {
    local url="$1"
    local dest="$2"
    local expected_fpr="$3"
    local temp_key
    temp_key=$(mktemp)
    if [[ $DRY_RUN -eq 1 ]]; then
        log "[dry-run] Would download key from $url to $dest"
        rm -f "$temp_key"
        return
    fi
    curl -fsSL "$url" -o "$temp_key"
    local fpr
    fpr=$(gpg --with-colons --import-options show-only --import "$temp_key" | awk -F: '/^fpr:/ {print $10; exit}')
    if [[ $fpr != ${expected_fpr// /} ]]; then
        rm -f "$temp_key"
        die "GPG fingerprint mismatch for $url (expected $expected_fpr, got $fpr)"
    fi
    local dest_dir
    dest_dir=$(dirname "$dest")
    if [[ ! -d $dest_dir ]]; then
        run_root_cmd mkdir -p "$dest_dir"
    fi
    run_root_cmd install -m 0644 "$temp_key" "$dest"
    rm -f "$temp_key"
}

setup_repo_debian() {
    local arch
    arch=$(dpkg --print-architecture)
    local codename="${VERSION_CODENAME:-}"
    if [[ -z $codename ]]; then
        if command -v lsb_release >/dev/null 2>&1; then
            codename=$(lsb_release -cs)
        else
            die "Unable to determine Debian/Ubuntu codename."
        fi
    fi
    local repo="deb [arch=$arch signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS_NAME $codename $CHANNEL"

    if [[ $DRY_RUN -eq 1 ]]; then
        log "[dry-run] Would configure APT repo: $repo"
        return
    fi

    if ! command -v gpg >/dev/null 2>&1; then
        run_root_cmd apt-get update
        run_root_cmd apt-get install -y gnupg
    fi

    if [[ ! -d /etc/apt/keyrings ]]; then
        run_root_cmd mkdir -p /etc/apt/keyrings
        run_root_cmd chmod 0755 /etc/apt/keyrings
    fi
    verify_and_install_key "https://download.docker.com/linux/$OS_NAME/gpg" \
        "/etc/apt/keyrings/docker.gpg" "9DC858229FC7DD38854AE2D88D81803C0EBFCD88"

    local repo_file="/etc/apt/sources.list.d/docker.list"
    if [[ -f $repo_file ]]; then
        if ! grep -q "download.docker.com" "$repo_file"; then
            backup_file "$repo_file"
        fi
    fi
    if [[ $(id -u) -eq 0 ]]; then
        printf '%s\n' "$repo" > "$repo_file"
    else
        printf '%s\n' "$repo" | "$SUDO_CMD" tee "$repo_file" >/dev/null
    fi
    run_root_cmd apt-get update
}

remove_conflicts_debian() {
    run_root_cmd apt-get remove -y docker docker-engine docker.io containerd runc podman-docker || true
}

install_docker_debian() {
    run_root_cmd apt-get install -y ca-certificates curl gnupg lsb-release || true
    remove_conflicts_debian
    local packages=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin)
    if [[ $INSTALL_COMPOSE -eq 1 ]]; then
        packages+=(docker-compose-plugin)
    fi
    run_root_cmd apt-get install -y "${packages[@]}"
}

uninstall_debian() {
    local packages=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras)
    run_root_cmd apt-get remove -y "${packages[@]}" || true
    run_root_cmd apt-get autoremove -y || true
    if [[ $DRY_RUN -eq 0 ]]; then
        run_root_cmd rm -f /etc/apt/sources.list.d/docker.list
        run_root_cmd rm -f /etc/apt/keyrings/docker.gpg
        run_root_cmd apt-get update
    fi
}

setup_repo_rhel() {
    local repo_file="/etc/yum.repos.d/docker-ce.repo"
    if [[ $DRY_RUN -eq 1 ]]; then
        log "[dry-run] Would add Docker repo at $repo_file"
        return
    fi
    verify_and_install_key "https://download.docker.com/linux/centos/gpg" \
        "/etc/pki/rpm-gpg/docker.gpg" "060A61C50B557AFF2D8E578A4B685A5D4CFC7164"
    if [[ $(id -u) -eq 0 ]]; then
        cat <<REPO > "$repo_file"
[docker-ce-$CHANNEL]
name=Docker CE Repository
baseurl=https://download.docker.com/linux/centos/\$releasever/\$basearch/$CHANNEL
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/docker.gpg
REPO
    else
        cat <<REPO | "$SUDO_CMD" tee "$repo_file" >/dev/null
[docker-ce-$CHANNEL]
name=Docker CE Repository
baseurl=https://download.docker.com/linux/centos/\$releasever/\$basearch/$CHANNEL
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/docker.gpg
REPO
    fi
    run_root_cmd rpm --import /etc/pki/rpm-gpg/docker.gpg || true
}

remove_conflicts_rhel() {
    run_root_cmd dnf remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine podman-docker || true
}

install_docker_rhel() {
    remove_conflicts_rhel
    run_root_cmd dnf -y install yum-utils device-mapper-persistent-data lvm2 || true
    if rpm -q container-selinux >/dev/null 2>&1; then
        :
    else
        run_root_cmd dnf -y install container-selinux || true
    fi
    local packages=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin)
    if [[ $INSTALL_COMPOSE -eq 1 ]]; then
        packages+=(docker-compose-plugin)
    fi
    run_root_cmd dnf install -y "${packages[@]}"
}

uninstall_rhel() {
    local packages=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
    run_root_cmd dnf remove -y "${packages[@]}" || true
    run_root_cmd rm -f /etc/yum.repos.d/docker-ce.repo || true
}

setup_repo_fedora() {
    setup_repo_rhel
}

install_docker_fedora() {
    install_docker_rhel
}

uninstall_fedora() {
    uninstall_rhel
}

setup_repo_amazon() {
    if [[ $DRY_RUN -eq 1 ]]; then
        log "[dry-run] Would enable amazon-linux-extras docker"
        return
    fi
    run_root_cmd amazon-linux-extras enable docker
    run_root_cmd yum clean metadata
}

install_docker_amazon() {
    remove_conflicts_amazon
    local packages=(docker)
    run_root_cmd yum install -y "${packages[@]}"
    if [[ $INSTALL_COMPOSE -eq 1 ]]; then
        run_root_cmd curl -L "https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-$(uname -m)" -o /usr/local/bin/docker-compose
        run_root_cmd chmod +x /usr/local/bin/docker-compose
        warn "Compose V2 installed as docker-compose binary."
    fi
}

uninstall_amazon() {
    run_root_cmd yum remove -y docker docker-engine || true
    run_root_cmd amazon-linux-extras disable docker || true
}

remove_conflicts_amazon() {
    run_root_cmd yum remove -y docker docker-engine docker.io podman-docker || true
}

setup_repo_suse() {
    local repo_file="/etc/zypp/repos.d/docker-ce.repo"
    if [[ $DRY_RUN -eq 1 ]]; then
        log "[dry-run] Would add docker repo via zypper"
        return
    fi
    verify_and_install_key "https://download.docker.com/linux/suse/gpg" \
        "/etc/pki/trust/anchors/docker.gpg" "060A61C50B557AFF2D8E578A4B685A5D4CFC7164"
    if [[ $(id -u) -eq 0 ]]; then
        cat <<REPO > "$repo_file"
[docker-ce-$CHANNEL]
name=Docker CE Repository
baseurl=https://download.docker.com/linux/suse/$CHANNEL
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/trust/anchors/docker.gpg
REPO
    else
        cat <<REPO | "$SUDO_CMD" tee "$repo_file" >/dev/null
[docker-ce-$CHANNEL]
name=Docker CE Repository
baseurl=https://download.docker.com/linux/suse/$CHANNEL
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/trust/anchors/docker.gpg
REPO
    fi
    if command -v update-ca-certificates >/dev/null 2>&1; then
        run_root_cmd update-ca-certificates || true
    fi
    run_root_cmd rpm --import /etc/pki/trust/anchors/docker.gpg || true
}

install_docker_suse() {
    run_root_cmd zypper --non-interactive remove docker docker-client containerd runc || true
    local packages=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin)
    if [[ $INSTALL_COMPOSE -eq 1 ]]; then
        packages+=(docker-compose-plugin)
    fi
    run_root_cmd zypper --non-interactive install "${packages[@]}"
}

uninstall_suse() {
    run_root_cmd zypper --non-interactive remove docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
    run_root_cmd rm -f /etc/zypp/repos.d/docker-ce.repo || true
}

setup_repo_arch() {
    log "Arch Linux uses community repo; no additional configuration required."
}

install_docker_arch() {
    run_root_cmd pacman --noconfirm -Syu docker
    if [[ $INSTALL_COMPOSE -eq 1 ]]; then
        run_root_cmd pacman --noconfirm -S docker-compose
    fi
}

uninstall_arch() {
    run_root_cmd pacman --noconfirm -Rns docker docker-compose || true
}

enable_and_start_service() {
    if [[ $SYSTEMD_AVAILABLE -eq 0 ]]; then
        warn "Skipping service enable/start due to missing systemd."
        return
    fi
    run_root_cmd systemctl enable --now docker
}

configure_group_and_permissions() {
    if [[ $SKIP_GROUP_ADD -eq 1 ]]; then
        log "Skipping docker group modification."
        return
    fi
    local user="$TARGET_USER"
    if [[ -z $user ]]; then
        if [[ -n ${SUDO_USER:-} && ${SUDO_USER} != "root" ]]; then
            user=$SUDO_USER
        else
            user=${USER}
        fi
    fi
    if [[ -z $user ]]; then
        warn "Unable to determine target user for docker group."
        return
    fi
    if ! id "$user" >/dev/null 2>&1; then
        warn "User '$user' does not exist; skipping group add."
        return
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
        log "[dry-run] Would add $user to docker group"
        return
    fi
    run_root_cmd groupadd -f docker
    if id -nG "$user" | grep -qw docker; then
        log "User '$user' already in docker group."
    else
        run_root_cmd usermod -aG docker "$user"
        log "Added '$user' to docker group. User must log out/in to apply."
    fi
}

verify_install() {
    run_cmd docker --version
    if [[ $INSTALL_COMPOSE -eq 1 ]]; then
        if command -v docker >/dev/null 2>&1; then
            run_cmd docker compose version || run_cmd docker-compose --version
        fi
    fi
    if [[ $RUN_VERIFY -eq 1 ]]; then
        if [[ $SYSTEMD_AVAILABLE -eq 0 ]]; then
            warn "Skipping hello-world run due to lack of running Docker daemon."
        else
            run_cmd docker run --rm hello-world
        fi
    fi
}

uninstall_dispatch() {
    case "$OS_FAMILY" in
        debian) uninstall_debian ;;
        rhel) uninstall_rhel ;;
        fedora) uninstall_fedora ;;
        amazon) uninstall_amazon ;;
        suse) uninstall_suse ;;
        arch) uninstall_arch ;;
        *) die "Uninstall not implemented for $OS_FAMILY" ;;
    esac
    log "Docker uninstallation complete."
}

install_dispatch() {
    case "$OS_FAMILY" in
        debian)
            setup_repo_debian
            install_docker_debian
            ;;
        rhel)
            setup_repo_rhel
            install_docker_rhel
            ;;
        fedora)
            setup_repo_fedora
            install_docker_fedora
            ;;
        amazon)
            setup_repo_amazon
            install_docker_amazon
            ;;
        suse)
            setup_repo_suse
            install_docker_suse
            ;;
        arch)
            setup_repo_arch
            install_docker_arch
            ;;
        *)
            die "Installation not implemented for $OS_FAMILY"
            ;;
    esac
}

prompt_confirmation() {
    if [[ $ASSUME_YES -eq 1 ]]; then
        return
    fi
    read -r -p "Proceed with Docker $([ $DO_UNINSTALL -eq 1 ] && echo 'uninstallation' || echo 'installation')? [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY])
            ;;
        *)
            die "Aborted by user."
            ;;
    esac
}

main() {
    parse_args "$@"
    require_root_or_sudo
    ensure_logfile
    log "Starting Docker setup"
    check_prereqs
    read_os_release
    validate_supported_versions
    detect_wsl
    detect_systemd
    ensure_channel_supported

    if [[ $DO_UNINSTALL -eq 1 ]]; then
        prompt_confirmation
        uninstall_dispatch
        return
    fi

    if [[ $VERIFY_RUN_SET -eq 0 ]]; then
        RUN_VERIFY=$([[ $SYSTEMD_AVAILABLE -eq 1 ]] && echo 1 || echo 0)
    fi

    prompt_confirmation
    install_dispatch
    enable_and_start_service
    configure_group_and_permissions
    verify_install
    log "Docker installation complete."
}

main "$@"
