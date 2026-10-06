#!/bin/bash

# Installs the NVIDIA open kernel driver and userspace from RPM Fusion.
#
# RPM Fusion's akmod-nvidia builds the open kernel module from source, so it is
# compiled here against the kernel that ships in the base image (there is no
# prebuilt kmod to match a pinned kernel anymore). The module is signed
# afterwards by 50-sign-kernel-modules.sh with this image's MOK key so that it
# loads on a Secure Boot system.
#
# Responsibility: install the NVIDIA open driver only.

set -euo pipefail

FEDORA_VERSION="$(rpm -E %fedora)"
KERNEL_VERSION="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | head -n 1)"
EXTRA_MODULE_DIR="/usr/lib/modules/${KERNEL_VERSION}/extra"
DRACUT_CONF="/usr/lib/dracut/dracut.conf.d/99-nvidia.conf"
KARGS_CONF="/usr/lib/bootc/kargs.d/00-nvidia.toml"

# The akmod %post/%posttrans build hooks (see the long comment further down)
# must be replaced by a no-op that exits 0, not merely hidden: the hook is
# `[ -x /usr/sbin/akmods-ostree-post ] && /usr/sbin/akmods-ostree-post ...`, so
# when the executable test fails the scriptlet still reports failure (exit 1),
# which RPM 6.0 treats as a fatal transaction error. These helpers swap the real
# binaries for an exit-0 stub and restore them afterwards.
AKMOD_HOOKS=(/usr/sbin/akmods /usr/sbin/akmods-ostree-post)
stub_akmod_hooks() {
    local hook
    for hook in "${AKMOD_HOOKS[@]}"; do
        [[ -e "${hook}" ]] || continue
        mv "${hook}" "${hook}.real"
        printf '#!/bin/bash\n# no-op during image build; see image/30-install-nvidia-driver.sh\nexit 0\n' > "${hook}"
        chmod 0755 "${hook}"
    done
}
restore_akmod_hooks() {
    local hook
    for hook in "${AKMOD_HOOKS[@]}"; do
        [[ -e "${hook}.real" ]] || continue
        rm -f "${hook}"
        mv "${hook}.real" "${hook}"
    done
}

echo "Enabling the RPM Fusion repositories..."
dnf5 install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"

# Install the akmods tooling and the matching kernel-devel FIRST: this creates
# the unprivileged `akmods` user and provides akmodsbuild, both of which are
# required before any module can be built.
echo "Installing akmods tooling and kernel-devel for ${KERNEL_VERSION}..."
dnf5 install -y \
    akmods \
    kmodtool \
    "kernel-devel-${KERNEL_VERSION}"

# Every kmodtool-generated akmod package runs this in its %post:
#
#     [ -x /usr/sbin/akmods-ostree-post ] && /usr/sbin/akmods-ostree-post ...
#
# which calls `akmodsbuild` directly as root. akmodsbuild refuses to run as root
# (its guard is `[[ -w /var ]]`), and on an ostree/bootc base the hook is NOT
# skipped because /etc/os-release carries OSTREE_VERSION=. Fedora 44 ships RPM
# 6.0, which turns the failed %post into a fatal transaction error, so the whole
# `dnf install` dies with:
#
#     ERROR: Not to be used as root; start as user or 'akmodsbuild' instead.
#     Transaction failed: Rpm transaction failed.
#
# The %posttrans hook (nohup akmods --from-akmod-posttrans ...) tries to build
# for the running kernel, which is wrong inside an image build too. Neutralize
# both hooks so installing the packages is a pure packaging operation; the module
# is built explicitly below with `akmods --force`, which runs akmodsbuild as the
# unprivileged `akmods` user and therefore passes the root guard.
echo "Disabling the akmod %post/%posttrans build hooks..."
stub_akmod_hooks

echo "Installing the NVIDIA open driver and userspace from RPM Fusion..."
# IMPORTANT: use `akmod-nvidia`, not `akmod-nvidia-open`. For the 615 series the
# open modules come from `akmod-nvidia` (it requires xorg-x11-drv-nvidia-kmodsrc,
# i.e. NVIDIA's open-gpu-kernel-modules) and the 615 userspace provides
# nvidia-open-kmod-common. The legacy `akmod-nvidia-open` package tracks an older
# 595 series and does NOT satisfy xorg-x11-drv-nvidia's `nvidia-kmod >= 615`
# dependency, so it would pull the 615 akmod in as well and leave two conflicting
# driver generations installed.
dnf5 install -y \
    akmod-nvidia \
    xorg-x11-drv-nvidia \
    xorg-x11-drv-nvidia-cuda \
    nvidia-settings \
    libva-nvidia-driver

echo "Re-enabling the akmod tooling..."
restore_akmod_hooks

echo "Building the NVIDIA open akmod for kernel ${KERNEL_VERSION}..."
akmods --force --kernels "${KERNEL_VERSION}"

if [[ -z "$(find "${EXTRA_MODULE_DIR}" -type f -name 'nvidia*.ko*' -print -quit)" ]]; then
    echo "ERROR: NVIDIA kernel modules were not built for ${KERNEL_VERSION}." >&2
    find /var/cache/akmods -name '*.log' -print -exec cat {} \; >&2 || true
    exit 1
fi

echo "Configuring dracut and kernel arguments for NVIDIA..."

# RPM Fusion ships a dracut configuration for the driver. If it keeps the
# NVIDIA modules out of the initramfs, force them in instead so the driver is
# available early on NVIDIA-only systems (this matches the previous behaviour).
while IFS= read -r -d '' conf; do
    grep -q 'nvidia' "${conf}" || continue
    sed -i 's/omit_drivers/force_drivers/g' "${conf}"
done < <(grep -rlZ -- 'omit_drivers' /usr/lib/dracut/dracut.conf.d/ 2>/dev/null || true)

mkdir -p "$(dirname "${DRACUT_CONF}")" "$(dirname "${KARGS_CONF}")"

cat > "${DRACUT_CONF}" <<'EOF'
# Force the NVIDIA modules into the initramfs so the driver is available early.
force_drivers+=" nvidia nvidia_drm nvidia_modeset nvidia_uvm "
EOF
chmod 0644 "${DRACUT_CONF}"

cat > "${KARGS_CONF}" <<'EOF'
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1", "nvidia-drm.fbdev=1"]
EOF
chmod 0644 "${KARGS_CONF}"

# Keep the freshly built modules, but drop the akmod source and the compiler
# toolchain: the deployed image is immutable, so an on-host akmods rebuild could
# never work anyway. Back up the built modules first in case dnf decides to
# remove the generated kmod package along with its build dependencies.
MODULE_BACKUP="$(mktemp -d)"
cp -a "${EXTRA_MODULE_DIR}" "${MODULE_BACKUP}/extra"

echo "Removing the NVIDIA akmod build toolchain..."
dnf5 remove -y \
    akmod-nvidia \
    akmods \
    kmodtool \
    kernel-devel \
    gcc gcc-c++ make \
    || true

mkdir -p "${EXTRA_MODULE_DIR}"
cp -a "${MODULE_BACKUP}/extra/." "${EXTRA_MODULE_DIR}/"
rm -rf "${MODULE_BACKUP}"

if [[ -z "$(find "${EXTRA_MODULE_DIR}" -type f -name 'nvidia*.ko*' -print -quit)" ]]; then
    echo "ERROR: NVIDIA kernel modules disappeared after removing the build toolchain." >&2
    exit 1
fi
