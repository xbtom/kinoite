#!/bin/bash

# Assigns files to dedicated chunked-OCI layers to keep delta updates small.
#
# `rpm-ostree compose build-chunked-oci` (run by `just ostree-rechunk` after the
# build) honours the `user.component` xattr: any file carrying it -- or living
# under a directory that carries it -- is packed into a stable layer named after
# the component. This lets us
#
#   * group content that always changes together (e.g. an NVIDIA driver bump
#     rewrites both the kernel modules and the userspace libraries) into a
#     single layer, and
#   * isolate content that changes on *every* build (the RPM database) so it
#     cannot drag a shared "small files" layer along with it.
#
# As a result the layer digests of unrelated content stay identical between
# builds and clients only re-download the few layers that really changed.
#
# Responsibility: assign `user.component` xattrs only.

set -euo pipefail

KERNEL_VERSION="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | head -n 1)"
EXTRA_MODULE_DIR="/usr/lib/modules/${KERNEL_VERSION}/extra"

# `setfattr` ships in the `attr` package. Install it only for this step and drop
# it again so the final image stays minimal.
ATTR_INSTALLED=false
if ! command -v setfattr >/dev/null 2>&1; then
    echo "Installing attr (provides setfattr)..."
    dnf5 install -y attr
    ATTR_INSTALLED=true
fi

# tag <component> <path>...  -- sets user.component on every existing path.
# Directories are tagged recursively by build-chunked-oci, so tagging a single
# directory covers its whole subtree.
tag_component() {
    local component="$1"
    shift

    local path
    for path in "$@"; do
        [[ -e "${path}" ]] || continue
        if ! setfattr -n user.component -v "${component}" "${path}" 2>/dev/null; then
            echo "WARN: could not tag ${path} as '${component}'" >&2
        fi
    done
}

# rpm_files <pkg>... -- lists the files owned by the given (installed) packages.
rpm_files() {
    [[ "$#" -gt 0 ]] || return 0
    rpm -ql "$@" 2>/dev/null | sort -u
}

echo "===> Tagging delta-update components"

# --- NVIDIA: kernel modules and userspace ship together and are bumped
# together, so a driver update rewrites exactly one layer.
mapfile -t nvidia_kmods < <(find "${EXTRA_MODULE_DIR}" -type f -name 'nvidia*.ko*' 2>/dev/null)
tag_component nvidia "${nvidia_kmods[@]}"

mapfile -t nvidia_pkgs < <(
    rpm -qa --qf '%{NAME}\n' |
        grep -E '^(xorg-x11-drv-nvidia|nvidia-|libva-nvidia-driver)' |
        sort -u
)
mapfile -t nvidia_userspace < <(rpm_files "${nvidia_pkgs[@]}")
tag_component nvidia "${nvidia_userspace[@]}"

# --- Out-of-tree modules built here: isolate them from the NVIDIA layer so an
# NVIDIA-only bump does not invalidate them (and vice versa).
tag_component kernel-modules \
    "${EXTRA_MODULE_DIR}/mechrevo" \
    "${EXTRA_MODULE_DIR}/ryzen_smu"

# --- initramfs: a single large file that is regenerated whenever the kernel or
# any module changes; a dedicated layer keeps unrelated updates away from it.
tag_component initramfs "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"

# --- TUXEDO Control Center: large, third-party and rarely updated.
mapfile -t tuxedo_files < <(rpm_files tuxedo-control-center)
tag_component tuxedo "${tuxedo_files[@]}"

# --- RPM database: rewritten on every build (timestamps, install order). Keep
# it in its own layer so it does not churn a shared layer with it.
tag_component rpmdb /usr/lib/sysimage/rpm

if [[ "${ATTR_INSTALLED}" == true ]]; then
    echo "Removing attr again..."
    dnf5 remove -y attr || true
fi

echo "===> Component tagging complete"
