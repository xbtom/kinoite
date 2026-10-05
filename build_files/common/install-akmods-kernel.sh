#!/bin/bash

set -euo pipefail

KERNEL_VERSION="${1:?Expected the akmods kernel version}"
KERNEL_RPM_DIR="/kernel-rpms"
KERNEL_PACKAGES=(kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra)
KERNEL_RPMS=()

for package in "${KERNEL_PACKAGES[@]}"; do
    rpm_path="${KERNEL_RPM_DIR}/${package}-${KERNEL_VERSION}.rpm"
    if [[ ! -f "${rpm_path}" ]]; then
        echo "Missing cached kernel package: ${rpm_path}" >&2
        exit 1
    fi
    KERNEL_RPMS+=("${rpm_path}")
done

for package in "${KERNEL_PACKAGES[@]}"; do
    if rpm -q "${package}" >/dev/null 2>&1; then
        rpm --erase --nodeps "${package}"
    fi
done

HOOK_DIR="/usr/lib/kernel/install.d"
HOOKS=(05-rpmostree.install 50-dracut.install)
RESTORE_HOOKS=()

restore_hooks() {
    for hook in "${RESTORE_HOOKS[@]}"; do
        mv -f "${HOOK_DIR}/${hook}.akmods-backup" "${HOOK_DIR}/${hook}"
    done
}

for hook in "${HOOKS[@]}"; do
    if [[ -f "${HOOK_DIR}/${hook}" ]]; then
        mv "${HOOK_DIR}/${hook}" "${HOOK_DIR}/${hook}.akmods-backup"
        printf '%s\n' '#!/bin/sh' 'exit 0' > "${HOOK_DIR}/${hook}"
        chmod 0755 "${HOOK_DIR}/${hook}"
        RESTORE_HOOKS+=("${hook}")
    fi
done

trap restore_hooks EXIT
dnf5 install -y --allowerasing "${KERNEL_RPMS[@]}"
restore_hooks
trap - EXIT

INSTALLED_KERNEL_VERSION="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)"
if [[ "${INSTALLED_KERNEL_VERSION}" != "${KERNEL_VERSION}" ]]; then
    echo "Installed kernel ${INSTALLED_KERNEL_VERSION}, expected ${KERNEL_VERSION}." >&2
    exit 1
fi