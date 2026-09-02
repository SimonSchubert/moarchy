# Build the handful of packages that have no aarch64 binaries anywhere:
# walker, elephant, yay, xdg-terminal-exec, ttf-ia-writer.
#
# On Apple Silicon this container runs NATIVELY (linux/arm64), so these build at
# full speed rather than at PinePhone speed (4x Cortex-A53 @ 1.15GHz, 2-3 GB).
#
#   docker build --platform linux/arm64 -f docker/Dockerfile.builder -t mobileomarchy-builder .
#   docker run --rm -v "$PWD/packages:/out" mobileomarchy-builder

FROM --platform=linux/arm64 menci/archlinuxarm:base-devel

# Docker Desktop's Linux VM kernel does not expose Landlock, which pacman 7 uses
# to sandbox downloads; without this it fails with
#   "restricting filesystem access failed because Landlock is not supported"
RUN sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf

RUN pacman-key --init && pacman-key --populate archlinuxarm && \
    pacman -Syu --noconfirm git go base-devel sudo

# makepkg refuses to run as root.
RUN useradd -m builder && \
    echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder

USER builder
WORKDIR /home/builder

COPY docker/build-packages.sh /usr/local/bin/build-packages
ENTRYPOINT ["/usr/local/bin/build-packages"]
