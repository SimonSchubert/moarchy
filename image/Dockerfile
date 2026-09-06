# The image builder. Separate from docker/Dockerfile.builder, which builds
# packages: this one consumes them.
#
#   ./image/build.sh
#
# Needs --privileged, because arch-chroot bind-mounts /proc, /sys and /dev to
# run mkinitcpio inside the rootfs. Everything else avoids loop devices on
# purpose -- `mkfs.ext4 -d` and `mcopy` populate a filesystem image from a
# directory without mounting it, which Docker Desktop's VM cannot do reliably.
FROM --platform=linux/arm64 menci/archlinuxarm@sha256:f7c6f64c0f246f41775e01793340c49f8e9abf3991141c25405361d56b100ccb

RUN sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf

# [danctnix] carries the kernel, u-boot, the modem stack and three packages the
# base set needs that Arch Linux ARM does not have (lisgd, mmsd-tng,
# portfolio-file-manager). Read out of the shipped image's /etc/pacman.conf.
RUN printf '\n[danctnix]\nSigLevel = Never\nServer = https://archmobile.mirror.danctnix.org/$repo/$arch/\n' \
      >> /etc/pacman.conf

RUN pacman-key --init && pacman-key --populate archlinuxarm && \
    pacman -Syu --noconfirm \
      arch-install-scripts dosfstools e2fsprogs mtools util-linux \
      uboot-tools xz git

COPY image/build.sh /usr/local/bin/build-image

# The repo, so build.sh can reach image/configure.sh and verify.sh can be run
# from the same image with --entrypoint bash.
COPY . /repo

ENTRYPOINT ["/usr/local/bin/build-image"]
