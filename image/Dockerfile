# The image builder. Separate from docker/Dockerfile.builder, which builds
# packages: this one consumes them.
#
#   ./image/build.sh
#
# Needs --privileged, because arch-chroot bind-mounts /proc, /sys and /dev to
# run configure.sh inside the rootfs. Everything else avoids loop devices on
# purpose -- `mkfs.ext4 -d` and `mcopy` populate a filesystem image from a
# directory without mounting it, which Docker Desktop's VM cannot do reliably.
# The `docker.io/` prefix is not decoration. Docker resolves a bare
# `menci/archlinuxarm` against Docker Hub implicitly; podman refuses to guess
# and fails the build with "short-name ... did not resolve to an alias and no
# containers-registries.conf(5) was found". Writing the registry out makes the
# file mean the same thing to both engines, and a fully-qualified name is what
# the digest pin below was always claiming to be anyway.
FROM --platform=linux/arm64 docker.io/menci/archlinuxarm@sha256:f7c6f64c0f246f41775e01793340c49f8e9abf3991141c25405361d56b100ccb

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
# fuse2fs is how image/verify.sh mounts the rootfs when there is no loop
# device to mount it on -- which is the case in a ROOTLESS container, where
# setting one up needs CAP_SYS_ADMIN in the initial namespace and --privileged
# cannot grant it. It implements ext4 in userspace over /dev/fuse instead.
#
# A SEPARATE package on Arch Linux ARM -- `fuse2fs` in core, 1.47.4-1, not a
# file inside e2fsprogs, which was checked rather than assumed. So this line is
# load-bearing: without it a rootless verify run has no way to read the image
# it just built, and says so by failing to mount rather than by naming a
# missing package.
RUN pacman-key --init && pacman-key --populate archlinuxarm && \
    pacman -Syu --noconfirm \
      arch-install-scripts dosfstools e2fsprogs fuse2fs mtools util-linux \
      uboot-tools xz git \
      gptfdisk parted \
      android-tools

# --- pacstrap in a rootless container ---------------------------------------
#
# arch-chroot mounts a FRESH devtmpfs on the target's /dev, and that is one of
# the few filesystem types a user namespace may not mount. proc, sysfs and
# tmpfs are all permitted; devtmpfs needs CAP_SYS_ADMIN in the INITIAL
# namespace, which --privileged cannot grant to a rootless container. The
# result is
#
#   mount: /work/rootfs/dev: permission denied.
#   ==> ERROR: failed to setup chroot /work/rootfs
#
# three retries deep, after the package repository has been built -- so it
# reads like a mirror problem and is not one.
#
# upstream's own answer, `pacstrap -N`, swaps in unshare_setup, which binds
# device nodes instead of mounting devtmpfs. It does not work here: -N
# re-unshares, and nesting a user namespace inside rootless podman's hung
# indefinitely at 0.3% CPU with an empty rootfs. Measured, not assumed.
#
# So the same idea is applied directly: recursively bind the container's /dev
# rather than creating one. --make-rslave keeps the submounts from propagating
# back out, and the two explicit devpts/shm mounts are dropped because rbind
# has already brought them along.
#
# The teardown needs --recursive --lazy for the same reason: a plain umount of
# an rbind with submounts under it fails with "target is busy", and a /dev
# left mounted would be COPIED INTO THE IMAGE by `mkfs.ext4 -d`. Verified
# after this patch: nothing stays mounted, and the rootfs's /dev is empty.
#
# BOTH files are patched, and that is not redundancy. pacstrap carries its own
# inline copy of these functions rather than sourcing arch-chroot's, so
# patching one and testing the other is a fix that appears to do nothing.
RUN for f in /usr/bin/pacstrap /usr/bin/arch-chroot; do \
      sed -i \
        -e 's|chroot_add_mount udev "$1/dev" -t devtmpfs -o mode=0755,nosuid|chroot_add_mount /dev "$1/dev" --rbind --make-rslave|' \
        -e '/chroot_add_mount devpts/d' \
        -e '/chroot_add_mount shm/d' \
        -e 's|umount "${CHROOT_ACTIVE_MOUNTS\[@\]}"|umount --recursive --lazy "${CHROOT_ACTIVE_MOUNTS[@]}"|' \
        "$f"; \
    done && \
    for f in /usr/bin/pacstrap /usr/bin/arch-chroot; do \
      grep -q 'chroot_add_mount /dev "$1/dev" --rbind' "$f" || \
        { echo "!! the rootless chroot patch did not apply to $f"; exit 1; }; \
      grep -q 'umount --recursive --lazy' "$f" || \
        { echo "!! the teardown patch did not apply to $f"; exit 1; }; \
    done

# fuse2fs mounts the rootfs when there is no loop device, and a FUSE mount is
# private to the user that mounted it unless allow_other is given -- which the
# kernel only honours when /etc/fuse.conf permits it. Without this, every check
# that runs as the phone's own user fails with "Permission denied" on files
# root can read perfectly well.
RUN printf 'user_allow_other\n' >> /etc/fuse.conf

COPY image/build.sh /usr/local/bin/build-image

# The repo, so build.sh can reach image/configure.sh and verify.sh can be run
# from the same image with --entrypoint bash.
COPY . /repo

ENTRYPOINT ["/usr/local/bin/build-image"]
