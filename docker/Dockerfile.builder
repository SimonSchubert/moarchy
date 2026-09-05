# Build the handful of packages that have no aarch64 binaries anywhere:
# moarchy-keyboard, yay, xdg-terminal-exec, ttf-ia-writer, cbonsai.
#
# On Apple Silicon this container runs NATIVELY (linux/arm64), so these build at
# full speed rather than at PinePhone speed (4x Cortex-A53 @ 1.15GHz, 2-3 GB).
#
#   docker build --platform linux/arm64 -f docker/Dockerfile.builder -t moarchy-builder .
#   docker run --rm -v "$PWD/packages:/out" moarchy-builder
#
# Pinned by digest rather than by the `base-devel` tag: a floating tag is a
# clone at HEAD by another name, and the point of manifest.toml is that two
# builds of the same manifest agree. The digest and the tag it came from are in
# manifest.toml under [builder], with the command to re-resolve one to the
# other. Dockerfiles cannot read a file at FROM time, so this is the one pin
# that is written in two places -- keep them in step when bumping.
FROM --platform=linux/arm64 menci/archlinuxarm@sha256:f7c6f64c0f246f41775e01793340c49f8e9abf3991141c25405361d56b100ccb

# Docker Desktop's Linux VM kernel does not expose Landlock, which pacman 7 uses
# to sandbox downloads; without this it fails with
#   "restricting filesystem access failed because Landlock is not supported"
RUN sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf

RUN pacman-key --init && pacman-key --populate archlinuxarm && \
    pacman -Syu --noconfirm git go base-devel sudo

# makepkg refuses to run as root.
RUN useradd -m builder && \
    echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder

# The pins and their reader travel with the builder, so the image is
# self-contained: `docker run` needs no bind mount to know what to build.
COPY manifest.toml scripts/manifest.sh /usr/local/share/moarchy/

USER builder
WORKDIR /home/builder

COPY docker/build-packages.sh /usr/local/bin/build-packages

# The repo itself, so the in-repo pkgbuilds/ can be built without a bind mount.
# Last, because it changes on every commit and everything above it does not.
USER root
COPY . /repo
USER builder

ENTRYPOINT ["/usr/local/bin/build-packages"]
