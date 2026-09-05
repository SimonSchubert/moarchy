#!/bin/bash
# Assert we are on the hardware this was built for, and record the GPU's actual
# capability -- the fact that drives the whole Sway-instead-of-Hyprland design.

echo "==> preflight"

if (( EUID == 0 )); then
  echo "Run as your normal user, not root." >&2
  exit 1
fi

ARCH=$(uname -m)
if [[ $ARCH != "aarch64" ]]; then
  echo "moarchy targets aarch64; this is $ARCH." >&2
  echo "(For x86_64, use upstream Omarchy: https://omarchy.org)" >&2
  exit 1
fi

if [[ ! -f /etc/arch-release ]]; then
  echo "Expected an Arch Linux ARM / DanctNIX base." >&2
  exit 1
fi

# Report the GLES ceiling. Mali-400 tops out at OpenGL ES 2.0, which is why the
# compositor is Sway: Hyprland aborts without a GLES 3.0 context
# (src/render/OpenGL.cpp -- RASSERT on "either GLES3.2 or 3.0").
if command -v es2_info >/dev/null; then
  # es2_info needs an EGL display and exits 255 when there is none -- which is
  # always true here, because the installer runs before any session exists.
  # install.sh runs under `set -eo pipefail`, so without the `|| true` that 255
  # propagates out of the pipeline and aborts the whole install on a probe whose
  # result is purely informational.
  #
  # This only bites on a re-run: the first pass runs preflight *before*
  # packages.sh installs mesa-demos, so `command -v es2_info` is false and the
  # branch never executes. That asymmetry is why it looked like a fresh install
  # worked and a resumed one did not.
  GLES=$( { es2_info 2>/dev/null || true; } | sed -n 's/^GL_VERSION: *//p' | head -1)
  RENDERER=$( { es2_info 2>/dev/null || true; } | sed -n 's/^GL_RENDERER: *//p' | head -1)
  echo "    GPU:  ${RENDERER:-unknown}"
  echo "    GLES: ${GLES:-unknown}"

  if [[ $GLES == *"ES 3."* ]]; then
    echo "    NOTE: this GPU reports GLES 3.x, so upstream Hyprland would also run here."
  fi
else
  echo "    (mesa-demos not installed yet; GLES probe deferred)"
fi

echo "    OK"
