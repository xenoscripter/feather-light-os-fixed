#!/bin/sh
set -eu
WORK="${1:-work}"
OUT="${2:-out}"
ARCH="x86_64"
TAG="edge"
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APORTS="$WORK/aports"
rm -rf "$WORK" "$OUT"
mkdir -p "$WORK" "$OUT"

if [ "${ALPINE_NATIVE:-0}" != "1" ]; then
    command -v docker >/dev/null 2>&1 || { echo "Docker is required (or set ALPINE_NATIVE=1 on Alpine)." >&2; exit 1; }
    docker run --rm --privileged \
      -v "$ROOT":/src -w /src alpine:edge \
      sh -c 'apk add --no-cache bash git alpine-conf syslinux xorriso squashfs-tools grub mtools curl jq ca-certificates abuild coreutils >/dev/null && ALPINE_NATIVE=1 sh /src/build.sh "$1" "$2"' -- "$WORK" "$OUT"
    exit $?
fi

apk update
apk add --no-cache bash git alpine-conf syslinux xorriso squashfs-tools grub mtools curl jq ca-certificates abuild coreutils
mkdir -p "$WORK/apk-cache" "$WORK/tmp" "$WORK/mkimage"
export TMPDIR="$ROOT/$WORK/tmp"

# apk-tools v3 requires the cache directory to exist for alternate roots.
# update-kernel creates its own temporary root and must initialize that root's
# apk database/cache before its first --update-cache operation.
if [ -x /sbin/update-kernel ]; then
    cp /sbin/update-kernel "$WORK/update-kernel.orig"
    sed -i '/^[[:space:]]*ROOT=\$TMPDIR\/root[[:space:]]*$/a\    mkdir -p "$ROOT/etc/apk/cache" "$ROOT/etc/apk"' /sbin/update-kernel
fi

if [ ! -d "$APORTS/.git" ]; then
    git clone --depth=1 https://gitlab.alpinelinux.org/alpine/aports.git "$APORTS"
fi
mkdir -p "$APORTS/scripts"
cp "$ROOT/scripts/mkimg.feather.sh" "$APORTS/scripts/mkimg.feather.sh"
cp "$ROOT/scripts/genapkovl-feather.sh" "$APORTS/scripts/genapkovl-feather.sh"
chmod +x "$ROOT/scripts/genapkovl-feather.sh" "$APORTS/scripts/mkimg.feather.sh"

# apk-tools v3 treats --no-chown as an alias for --usermode, which is rejected
# when mkimage is running as root. Remove both legacy flags from the actual
# checked-out mkimage scripts before invoking the builder.
find "$APORTS/scripts" -type f -name '*.sh' -exec sed -i \
  -e 's/--no-chown//g' \
  -e 's/--usermode//g' {} +

if grep -R -n -E -- '--no-chown|--usermode' "$APORTS/scripts/mkimage.sh" "$APORTS/scripts/mkimg"*.sh 2>/dev/null; then
    echo "ERROR: incompatible apk v3 usermode flags remain in mkimage scripts" >&2
    exit 1
fi

mkdir -p /root/.abuild
if [ ! -f /root/.abuild/abuild.conf ]; then
    abuild-keygen -a -n >/dev/null 2>&1 || true
fi

# Verify the exact helper that mkimage will use has the cache initialization.
if ! grep -q 'mkdir -p "$ROOT/etc/apk/cache"' /sbin/update-kernel 2>/dev/null; then
    echo "ERROR: update-kernel cache initialization patch was not applied" >&2
    exit 1
fi

sh "$APORTS/scripts/mkimage.sh" \
  --tag "$TAG" \
  --outdir "$OUT" \
  --workdir "$ROOT/$WORK/mkimage" \
  --arch "$ARCH" \
  --repository "https://dl-cdn.alpinelinux.org/alpine/edge/main" \
  --repository "https://dl-cdn.alpinelinux.org/alpine/edge/community" \
  --profile feather

ISO="$OUT/feather-light-os-v2-cosmic-x86_64.iso"
GENERATED=$(find "$OUT" -maxdepth 1 -type f -name '*.iso' -print -quit)
[ -n "$GENERATED" ] || { echo "No ISO was generated" >&2; exit 1; }
[ "$GENERATED" = "$ISO" ] || mv "$GENERATED" "$ISO"
sha256sum "$ISO" > "$OUT/SHA256SUMS"
printf '%s\n' "Feather Light OS V2 COSMIC ISO: $ISO"
