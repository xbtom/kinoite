#!/bin/bash

# Signs the out-of-tree kernel modules (NVIDIA from RPM Fusion, Mechrevo and
# ryzen_smu) with the MOK key so the kernel accepts them on a Secure Boot
# system.
#
# Usage: 50-sign-kernel-modules.sh [KERNEL_VERSION]
#
# Responsibility: sign the out-of-tree kernel modules and refresh depmod.

set -euo pipefail

KERNEL_VERSION="${1:-$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)}"

SIGN_FILE="/usr/src/kernels/${KERNEL_VERSION}/scripts/sign-file"
if [ ! -f "${SIGN_FILE}" ]; then
    SIGN_FILE="/usr/lib/modules/${KERNEL_VERSION}/build/scripts/sign-file"
fi

if [ ! -f "${SIGN_FILE}" ]; then
    echo "Installing kernel-devel to provide sign-file..."
    dnf5 install -y "kernel-devel-${KERNEL_VERSION}"

    SIGN_FILE="/usr/src/kernels/${KERNEL_VERSION}/scripts/sign-file"
    if [ ! -f "${SIGN_FILE}" ]; then
        SIGN_FILE="/usr/lib/modules/${KERNEL_VERSION}/build/scripts/sign-file"
    fi
fi

if [ ! -f "${SIGN_FILE}" ]; then
    echo "ERROR: sign-file is still unavailable after installing kernel-devel." >&2
    exit 1
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

            # Recompress with the exact settings the kernel uses for its own
            # in-tree modules (scripts/Makefile.modinst:
            # `xz --check=crc32 --lzma2=dict=1MiB`). The in-kernel module
            # decompressor (CONFIG_MODULE_DECOMPRESS) only understands these
            # parameters; a stream produced by a plain `xz -9` (CRC64, 64 MiB
            # dictionary) is rejected, so the module is never loaded. This is
            # why the compressed NVIDIA modules used to silently fail to load
            # while the uncompressed Mechrevo/ryzen_smu `.ko` modules worked.
            xz -f --check=crc32 --lzma2=dict=1MiB -- "${RAW_KO}" || {
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
            "/usr/lib/modules/${KERNEL_VERSION}/extra" \
            -type f \
            \( -name '*.ko' -o -name '*.ko.xz' -o -name '*.ko.zst' \) \
            -print0
    )

    if ((SIGNED_COUNT == 0)); then
        echo "ERROR: No kernel modules found to sign." >&2
        exit 1
    fi

    depmod -a "${KERNEL_VERSION}"
    echo "===> Signed ${SIGNED_COUNT} kernel modules successfully."
fi
