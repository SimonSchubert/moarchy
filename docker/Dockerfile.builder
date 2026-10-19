# Build the handful of packages that have no aarch64 binaries anywhere:
# moarchy-keyboard, yay, xdg-terminal-exec, ttf-ia-writer, cbonsai.
#
# On Apple Silicon this container runs NATIVELY (linux/arm64), so these build at
# full speed rather than at handset speed (a phone SoC with 2-4 GB).
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
# The `docker.io/` prefix is not decoration. Docker resolves a bare
# `menci/archlinuxarm` against Docker Hub implicitly; podman refuses to guess
# and fails the build with "short-name ... did not resolve to an alias and no
# containers-registries.conf(5) was found". Writing the registry out makes the
# file mean the same thing to both engines, and a fully-qualified name is what
# the digest pin below was always claiming to be anyway.
FROM --platform=linux/arm64 docker.io/menci/archlinuxarm@sha256:f7c6f64c0f246f41775e01793340c49f8e9abf3991141c25405361d56b100ccb

# Docker Desktop's Linux VM kernel does not expose Landlock, which pacman 7 uses
# to sandbox downloads; without this it fails with
#   "restricting filesystem access failed because Landlock is not supported"
RUN sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf

# [danctnix], for the same reason image/Dockerfile carries it and no further:
# it is where libdng and libmegapixels live, and pkgbuilds/megapixels links
# against both. Arch Linux ARM has neither, so without this the megapixels
# build stops at `Dependency "gtk4" not found` -- the first missing one, which
# is not even one of the two that are actually absent.
#
# The image's OWN /etc/pacman.conf still does not get this (structure.md R8a):
# a flashed phone syncs [moarchy], [moarchy-apps] and the Arch repos, and
# nothing else. This is the builder, where a foreign repo is an input to a
# build rather than a thing a phone updates itself from.
#
# SigLevel = Never matches image/Dockerfile's stanza. It is the weaker half of
# this trade and worth naming: these packages are verified by nothing but the
# transport.
RUN printf '\n[danctnix]\nSigLevel = Never\nServer = https://archmobile.mirror.danctnix.org/$repo/$arch/\n' \
      >> /etc/pacman.conf

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
# feedbackd is megapixels'. It is kept here as a CACHE rather than as the only
# source of truth, which is what this list used to be.
#
# build-packages.sh now installs each in-repo recipe's declared dependencies
# before building it (sync_deps), so a name missing from this line is slow
# rather than fatal. That changed because the old arrangement failed twice in
# one evening: megapixels stopped on libfeedback, this line was added, and the
# next pass stopped on zbar with eight more behind it -- each round costing an
# image rebuild and a full pass to learn exactly one name.
#
# Anything listed here is one thing the build does not have to fetch. Anything
# missing is fetched at build time from what the PKGBUILD declares.
RUN pacman-key --init && pacman-key --populate archlinuxarm && \
    pacman -Syu --noconfirm git go base-devel sudo bc libelf meson ninja \
      alsa-lib feedbackd

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

# The container runs as ROOT, and build-packages.sh drops to `builder` for
# every makepkg. It used to end on `USER builder` and reach for sudo, which
# cannot work in a rootless container: the kernel forces MS_NOSUID on a mount
# made by an unprivileged user namespace, so the setuid bit on sudo is ignored
# and makepkg's `-s` fails with "effective uid is not 0". Measured, along with
# --privileged and --cap-add=SETUID, neither of which restores it -- the
# restriction is the kernel's, not the runtime's.
#
# So the privileged half (refresh the databases, install dependencies) is done
# by root directly and makepkg never is. `builder` still exists and is still
# the only thing that ever runs makepkg; what changed is who invokes it.
#
# This is not a rootless-only concession. Under Docker the daemon hands you
# root anyway, so running as root there too keeps ONE code path instead of a
# branch nobody exercises.
ENTRYPOINT ["/usr/local/bin/build-packages"]
