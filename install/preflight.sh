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
  echo "mobileomarchy targets aarch64; this is $ARCH." >&2
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
  GLES=$(es2_info 2>/dev/null | sed -n 's/^GL_VERSION: *//p' | head -1)
  RENDERER=$(es2_info 2>/dev/null | sed -n 's/^GL_RENDERER: *//p' | head -1)
  echo "    GPU:  ${RENDERER:-unknown}"
  echo "    GLES: ${GLES:-unknown}"

  if [[ $GLES == *"ES 3."* ]]; then
    echo "    NOTE: this GPU reports GLES 3.x, so upstream Hyprland would also run here."
  fi
else
  echo "    (mesa-demos not installed yet; GLES probe deferred)"
fi

echo "    OK"
