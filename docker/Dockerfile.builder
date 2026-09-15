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

# bc and libelf are the KERNEL's build tools, and they are here rather than in
# linux-moarchy-sdm670's makedepends because build-packages.sh builds every
# in-repo package with --nodeps (see its pkgbuilds loop) -- makedepends are
# declared for correctness and never installed, so the builder image is what
# actually has to carry them.
#
# Leaving bc out cost a build and read as nothing like a missing package: the
# kernel fails at `include/generated/timeconst.h ... Error 127`, which is
# make's code for "command not found" about a header, four directories away
# from the tool that was missing. kernel/time/timeconst.bc is a bc script.
#
# base-devel already supplies bison, flex, gcc, make and perl. libelf is for
# objtool. pahole is deliberately NOT here: it only enables DEBUG_INFO_BTF,
# which olddefconfig turns off anyway on a GCC build, and it would add a
# toolchain dependency for a debugging feature a phone does not use.
#
# meson and ninja are qbootctl's, and they are here for the same reason bc is:
# build-packages.sh builds with --nodeps, so a package's makedepends are
# DECLARED and never installed. Omitting a build tool is not a missing
# dependency error, it is whatever confusing thing the build system says when
# its own driver is absent.
#
# alsa-lib is q6voiced's, and it is a LIBRARY rather than a tool -- which is
# the same rule one step further. --nodeps does not install `depends` either,
# so anything a package links against has to be here too. Its absence reads as
#
#   Run-time dependency alsa found: NO (tried pkg-config)
#   meson.build:12:7: ERROR: Dependency "alsa" not found
#
# which names the dependency honestly and still points at the wrong place: the
# package declares it correctly, and the container is what has not got it.
RUN pacman-key --init && pacman-key --populate archlinuxarm && \
    pacman -Syu --noconfirm git go base-devel sudo bc libelf meson ninja alsa-lib

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
