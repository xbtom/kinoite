# Base Image
ARG FEDORA_MAJOR_VERSION=44
ARG BASE_IMAGE=quay.io/fedora-ostree-desktops/kinoite:${FEDORA_MAJOR_VERSION}

# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files
COPY enroll_keys /enroll_keys

FROM ${BASE_IMAGE} AS base
ARG FEDORA_MAJOR_VERSION
RUN test "$(rpm -E %fedora)" = "${FEDORA_MAJOR_VERSION}"

# Build mechrevo drivers
FROM base AS kernel-builder

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/build-kernel-modules.sh

# Build RyzenAdj
FROM base AS ryzenadj-builder
RUN dnf5 install -y cmake curl gcc-c++ git jq make pciutils-devel

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    bash /ctx/ryzenadj-builder/10-build-ryzenadj.sh

# Build and publish image
FROM base
## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:testing
# FROM ghcr.io/ublue-os/aurora:stable
# FROM ghcr.io/ublue-os/bluefin-nvidia-open:stable
# 
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:44
# Fedora Kinoite (ostree desktop): quay.io/fedora-ostree-desktops/kinoite:44
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

RUN rm /opt && mkdir /opt

COPY --from=ryzenadj-builder /out/usr/local/bin/ryzenadj /usr/bin/ryzenadj

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

RUN --mount=type=secret,id=mok_key,required=true \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=kernel-builder,source=/out,target=/kernel-out \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
