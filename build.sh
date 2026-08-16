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

if [ ! -d "$APORTS/.git" ]; then
    git clone --depth=1 https://gitlab.alpinelinux.org/alpine/aports.git "$APORTS"
fi
mkdir -p "$APORTS/scripts"
cp "$ROOT/scripts/mkimg.feather.sh" "$APORTS/scripts/mkimg.feather.sh"
cp "$ROOT/scripts/genapkovl-feather.sh" "$APORTS/scripts/genapkovl-feather.sh"
chmod +x "$ROOT/scripts/genapkovl-feather.sh" "$APORTS/scripts/mkimg.feather.sh"

# Alpine apk 3.x removed the old --no-chown spelling used by older mkimage
# scripts. apk reports this as the misleading "--usermode not allowed as root".
# Remove both legacy spellings from every mkimage helper before the build.
find "$APORTS/scripts" -type f \( -name 'mkimage*.sh' -o -name 'mkimg*.sh' \) -exec sed -i \
  -e 's/[[:space:]]--no-chown\([[:space:]]\|$\)/ /g' \
  -e 's/[[:space:]]--usermode\([[:space:]]\|$\)/ /g' {} +

mkdir -p /root/.abuild
if [ ! -f /root/.abuild/abuild.conf ]; then
    abuild-keygen -a -n >/dev/null 2>&1 || true
fi

sh "$APORTS/scripts/mkimage.sh" \
  --tag "$TAG" \
  --outdir "$OUT" \
  --workdir "$WORK/mkimage" \
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
