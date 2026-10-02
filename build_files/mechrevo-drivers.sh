#!/bin/bash
set -ouex pipefail

# 获取当前内核版本
KERNEL_VERSION="$(rpm -q --qf "%{VERSION}-%{RELEASE}.%{ARCH}\n" kernel-core | head -n 1)"
echo "Building Mechrevo drivers for kernel: ${KERNEL_VERSION}"

# 安装编译链及对应的内核头文件
dnf5 install -y \
    kernel-devel-${KERNEL_VERSION} \
    gcc \
    make \
    patch \
    git \
    tar \
    xz

BUILD_DIR="$(mktemp -d)"
cd "${BUILD_DIR}"

# 获取 AUR 补丁与上游源码
git clone https://aur.archlinux.org/mechrevo-drivers-dkms.git aur-repo
cd aur-repo
PKGVER=$(grep -E '^pkgver=' PKGBUILD | head -n1 | cut -d= -f2 | tr -d "'\" ")

curl -L -o "tuxedo-drivers.tar.gz" "https://gitlab.com/tuxedocomputers/development/packages/tuxedo-drivers/-/archive/v${PKGVER}/tuxedo-drivers-v${PKGVER}.tar.gz"
tar -xzf tuxedo-drivers.tar.gz
cd "tuxedo-drivers-v${PKGVER}"

# 打补丁
patch -Np1 -i ../patch.diff

# 编译内核模块
make -C "/usr/lib/modules/${KERNEL_VERSION}/build" M="$(pwd)" modules

# 将编译完成的 .ko 输出到 /out 目录供后续阶段使用
mkdir -p /out/modules
find . -name "*.ko" -exec cp {} /out/modules/ \;
