# The image builder. Separate from docker/Dockerfile.builder, which builds
# packages: this one consumes them.
#
#   ./image/build.sh
#
# Needs --privileged, because arch-chroot bind-mounts /proc, /sys and /dev to
# run configure.sh inside the rootfs. Everything else avoids loop devices on
# purpose -- `mkfs.ext4 -d` and `mcopy` populate a filesystem image from a
# directory without mounting it, which Docker Desktop's VM cannot do reliably.
FROM --platform=linux/arm64 menci/archlinuxarm@sha256:f7c6f64c0f246f41775e01793340c49f8e9abf3991141c25405361d56b100ccb

RUN sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf

# [danctnix] carries the kernel, u-boot, the modem stack and megapixels, which
# the base set needs and Arch Linux ARM does not have.
# Read out of the shipped image's /etc/pacman.conf. Three until lisgd left
# with bin/moarchy-gestures (docs/refactor.md A2), portfolio-file-manager
# left with the Files plugin, and mmsd-tng left with chatty -- each one fewer
# foreign package, not one fewer repo.
RUN printf '\n[danctnix]\nSigLevel = Never\nServer = https://archmobile.mirror.danctnix.org/$repo/$arch/\n' \
      >> /etc/pacman.conf

# android-tools is for img2simg/simg2img, and it is a dependency rather than
# something reimplemented -- unlike mkbootimg, avbtool and pil-squasher, this
# one IS packaged for Arch.
#
# It is load-bearing rather than convenient. fastboot cannot flash a raw image
# larger than 4 GiB: FlashPartition takes a uint32_t size, and a 6.06 GiB
# rootfs fails instantly with "Failed reading from userdata" -- a message that
# names the partition, says nothing about size, and is identical to what a
# genuinely unreadable file produces. A 200 MB control file to the same
# partition succeeded in five seconds, which is how the size was pinned down.
#
# An Android sparse image takes a different path through fastboot, which splits
# it by max-download-size (256 MiB here) and streams it in chunks.
RUN pacman-key --init && pacman-key --populate archlinuxarm && \
    pacman -Syu --noconfirm \
      arch-install-scripts dosfstools e2fsprogs mtools util-linux \
      uboot-tools xz git \
      gptfdisk parted \
      android-tools

COPY image/build.sh /usr/local/bin/build-image

# The repo, so build.sh can reach image/configure.sh and verify.sh can be run
# from the same image with --entrypoint bash.
COPY . /repo

ENTRYPOINT ["/usr/local/bin/build-image"]
