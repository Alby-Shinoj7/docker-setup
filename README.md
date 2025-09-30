# Docker Setup Installer

This project provides a single, portable Bash script (`install-docker.sh`) that installs or removes Docker Engine and its tooling across multiple Linux distributions in an idempotent and auditable way.

## Supported distributions

- WSL2 (warns and skips service management when systemd is not available)

## Prerequisites
- Run as `root` or with `sudo`. The script automatically escalates privileged operations when possible.
- Internet access to Docker repositories (respecting `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`).
- `curl` and `gpg` are fetched automatically on APT-based systems when missing.

## Usage
```bash
sudo ./install-docker.sh [options]
```

### Common flags
- `-y`, `--assume-yes` — proceed without confirmation prompts.
- `--channel=<stable|test>` — choose Docker repo channel (default: `stable`).
- `--with-compose` / `--no-compose` — explicitly install or skip the Docker Compose V2 plugin.
- `--user=<name>` — add a specific user to the `docker` group (default: invoking user).
- `--skip-group-add` — do not modify user group membership.
- `--verify-run` / `--no-verify-run` — control whether `docker run hello-world` is executed.
- `--dry-run` — show planned actions without making any changes.
- `--uninstall` — remove Docker Engine, plugins, and repository configuration.
- `--verbose` — display commands as they execute.

### Examples
Install Docker non-interactively on Ubuntu:
```bash
sudo ./install-docker.sh -y
```

Install using the `test` channel and skip the hello-world verification:
```bash
sudo ./install-docker.sh -y --channel=test --no-verify-run
```

Install while behind an HTTP proxy:
```bash
sudo HTTPS_PROXY=http://proxy:3128 HTTP_PROXY=http://proxy:3128 NO_PROXY=localhost,127.0.0.1 ./install-docker.sh -y
```

Skip group modification (useful on hardened hosts):
```bash
sudo ./install-docker.sh -y --skip-group-add
```

Dry-run the uninstall workflow:
```bash
sudo ./install-docker.sh --uninstall --dry-run
```

Perform a full uninstall without prompts:
```bash
sudo ./install-docker.sh --uninstall -y
```

All activity is logged to `/var/log/docker-install.log` (or the path specified via `LOG_FILE` environment variable).

## Troubleshooting
- **GPG key import failures** — ensure outbound HTTPS access to `download.docker.com`. If using a proxy, export the proxy variables before running the script. You can also pre-fetch the key and store it locally, then rerun the script.
- **Repository metadata errors** — run `sudo ./install-docker.sh -y --dry-run` to verify repository configuration, then check network/DNS resolution for `download.docker.com`.
- **SELinux denials (RHEL family)** — the script installs `container-selinux`. If denials persist, ensure SELinux remains enforcing and consult `/var/log/audit/audit.log` for detailed AVC messages.
- **Docker service fails to start** — verify that systemd is available (`systemctl status docker`). On WSL2 or non-systemd environments, manually start Docker using the distribution-specific mechanism.
- **`hello-world` fails** — ensure the daemon is running and outbound access to Docker Hub is permitted. You can skip the test with `--no-verify-run`.
- **User cannot run Docker** — log out and back in after the script adds the user to the `docker` group, or explicitly run `newgrp docker`.

## Development
- `make format` — run `shfmt` if installed.
- `make lint` — run `shellcheck` on all shell scripts.
- `make test` — execute `tests/smoke.sh` for a basic sanity check.

## License
MIT
