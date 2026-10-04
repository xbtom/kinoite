#!/bin/bash

set -ouex pipefail

dnf5 remove -y \
    cosign toolbox \
    firefox firefox-langpacks \
    kate kate-plugins kate-krunner-plugin kwrite \
    filelight kfind kde-partitionmanager \
    kamera kcharselect khelpcenter \
    || true

dnf5 install -y \
    pciutils-libs \
    || true

echo "Installing the NVIDIA open driver..."

NVIDIA_KERNEL_VERSION="$(sed -n 's/^KERNEL_VERSION=//p' /nvidia-rpms/kmods/nvidia-vars)"
bash /ctx/install-akmods-kernel.sh "${NVIDIA_KERNEL_VERSION}"
AKMODNV_PATH=/nvidia-rpms IMAGE_NAME=kinoite /nvidia-rpms/ublue-os/nvidia-install.sh

echo "Installing Mechrevo kernel modules..."
bash /ctx/install-kernel-modules.sh

KERNEL_VERSION="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)"

# =========================Signing==============================
SIGN_FILE="/usr/src/kernels/${KERNEL_VERSION}/scripts/sign-file"
if [ ! -f "${SIGN_FILE}" ]; then
    SIGN_FILE="/usr/lib/modules/${KERNEL_VERSION}/build/scripts/sign-file"
fi

MOK_KEY="/run/secrets/mok_key"
MOK_PUB=""
for candidate in \
    "/ctx/certs/mok.pub" \
    "/ctx/enroll_keys/mok.pub" \
    "/etc/enroll_keys/mok.pub" \
    "/etc/pki/akmods/mok.pub"; do
    if [ -s "${candidate}" ]; then
        MOK_PUB="${candidate}"
        break
    fi
done

echo "MOK key diagnostics:"
if [ -e "${MOK_KEY}" ]; then
    echo "  MOK key exists: yes"
    echo "  MOK key size: $(stat -c '%s' "${MOK_KEY}") bytes"
    echo "  MOK key readable: $(test -r "${MOK_KEY}" && echo yes || echo no)"
else
    echo "  MOK key exists: no"
fi

echo "  MOK public certificate: ${MOK_PUB:-<not found>}"
echo "  sign-file: ${SIGN_FILE}"
echo "  sign-file exists: $(test -f "${SIGN_FILE}" && echo yes || echo no)"

if [ ! -e "${MOK_KEY}" ]; then
    echo "ERROR: MOK private key does not exist at ${MOK_KEY}" >&2
elif [ ! -r "${MOK_KEY}" ]; then
    echo "ERROR: MOK private key is not readable: ${MOK_KEY}" >&2
elif [ ! -s "${MOK_KEY}" ]; then
    echo "ERROR: MOK private key is empty: ${MOK_KEY}" >&2
elif [ -z "${MOK_PUB}" ]; then
    echo "ERROR: MOK public certificate was not found." >&2
elif [ ! -f "${SIGN_FILE}" ]; then
    echo "ERROR: sign-file does not exist: ${SIGN_FILE}" >&2
else
    echo "===> Signing kernel modules with MOK key..."

    SIGNED_COUNT=0

    while IFS= read -r -d '' mod; do
        echo "Signing ${mod}..."
        SIGNED_COUNT=$((SIGNED_COUNT + 1))

        if [[ "${mod}" == *.xz ]]; then
            xz -d -- "${mod}" || {
                echo "Failed to decompress ${mod}" >&2
                exit 1
            }

            RAW_KO="${mod%.xz}"

            "${SIGN_FILE}" sha256 "${MOK_KEY}" "${MOK_PUB}" "${RAW_KO}" || {
                echo "Failed to sign ${RAW_KO}" >&2
                exit 1
            }

            xz -f -9 -- "${RAW_KO}" || {
                echo "Failed to recompress ${RAW_KO}" >&2
                exit 1
            }

        elif [[ "${mod}" == *.zst ]]; then
            zstd -d --rm -- "${mod}" || {
                echo "Failed to decompress ${mod}" >&2
                exit 1
            }

            RAW_KO="${mod%.zst}"

            "${SIGN_FILE}" sha256 "${MOK_KEY}" "${MOK_PUB}" "${RAW_KO}" || {
                echo "Failed to sign ${RAW_KO}" >&2
                exit 1
            }

            zstd -f --rm -- "${RAW_KO}" || {
                echo "Failed to recompress ${RAW_KO}" >&2
                exit 1
            }

        else
            "${SIGN_FILE}" sha256 "${MOK_KEY}" "${MOK_PUB}" "${mod}" || {
                echo "Failed to sign ${mod}" >&2
                exit 1
            }
        fi
    done < <(
        find \
            "/usr/lib/modules/${KERNEL_VERSION}/extra/mechrevo" \
            "/usr/lib/modules/${KERNEL_VERSION}/extra/ryzen_smu" \
            -type f \
            \( -name '*.ko' -o -name '*.ko.xz' -o -name '*.ko.zst' \) \
            -print0
    )

    if (( SIGNED_COUNT == 0 )); then
        echo "ERROR: No kernel modules found to sign." >&2
        exit 1
    fi

    depmod -a "${KERNEL_VERSION}"
    echo "===> Signed ${SIGNED_COUNT} kernel modules successfully."
fi
# ==============================================================

INITRAMFS_PATH="/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"
export DRACUT_NO_XATTR=1

# dracut in the build container can try to install the host /root tree when the
# default root module is included; omitting it keeps the ostree initramfs build
# working in this environment while preserving the NVIDIA/Mechrevo modules.
dracut \
    --force \
    --no-hostonly \
    --kver "${KERNEL_VERSION}" \
    --reproducible \
    --add ostree \
    --verbose --keep --show-modules \
    "${INITRAMFS_PATH}"
chmod 0600 "${INITRAMFS_PATH}"
test -s "${INITRAMFS_PATH}"

bash /ctx/install-tuxedo-control-center.sh

# Always clean
dnf5 clean all
rm -rf /boot/*
rm -rf /run/dnf /run/selinux-policy
rm -rf /var/lib/rpm-state
rm -rf /var/lib/xkb/*
rm -rf /var/tmp/*

true
