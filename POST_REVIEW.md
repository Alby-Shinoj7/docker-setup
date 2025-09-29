# Post-implementation Review

1. **GPG key fetch failures** – Mitigated by verifying fingerprints and surfacing clear errors. Recommended workaround: pre-download keys in environments with restricted egress and rerun with local mirrors.
2. **Corporate proxy or MITM appliances** – Script honors `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY`; advise administrators to export proxy variables and trust the intercepting CA if TLS inspection is present.
3. **Non-systemd hosts (including some WSL2 distributions)** – Detection skips `systemctl` operations and warns, but operators must start Docker manually or rely on Docker Desktop integration.
4. **SELinux denials on RHEL-family systems** – `container-selinux` is installed automatically; if denials persist, review audit logs and ensure policies are updated (e.g., via `dnf update` or custom policy modules).
5. **Kernel lacking required modules (older or minimal installs)** – Script cannot remediate kernel gaps; instruct users to upgrade kernel packages and reboot before re-running the installer.
6. **DNS or network resolution issues for `download.docker.com`** – Installation aborts when repositories are unreachable; operators should validate network connectivity, configure DNS, or add mirror repositories before retrying.
7. **Residual Podman or legacy Docker packages** – Script removes conflicting packages prior to install; if removal is blocked (e.g., dependency locks), users should resolve package conflicts manually.
8. **Amazon Linux 2 Compose plugin availability** – Official plugin packages are absent; script installs the latest Compose V2 standalone binary but warns administrators to track updates manually.
9. **Arch Linux rolling updates breaking package names** – Pacman installs `docker` and optionally `docker-compose`; if package names change, users should adjust the script or pin to known good versions.
10. **`hello-world` verification blocked by firewall or lack of systemd** – Optionally skipped via `--no-verify-run`; instruct operators to run manual verification once connectivity/service availability is restored.
