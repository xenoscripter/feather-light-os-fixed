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

UPDATE_KERNEL="$(command -v update-kernel 2>/dev/null || true)"
if [ -z "$UPDATE_KERNEL" ]; then
    UPDATE_KERNEL="$(find /sbin /usr/sbin /usr/bin /usr/libexec -type f -name update-kernel -print -quit 2>/dev/null || true)"
fi
if [ -n "$UPDATE_KERNEL" ] && [ -f "$UPDATE_KERNEL" ]; then
    cp "$UPDATE_KERNEL" "$WORK/update-kernel.orig"
    if grep -q 'ROOT=' "$UPDATE_KERNEL"; then
        awk '
          { print }
          $0 ~ /^[[:space:]]*ROOT=/ && !done {
            print "mkdir -p \"$ROOT/etc/apk/cache\" \"$ROOT/etc/apk\" \"$ROOT/lib/apk/db\""
            done=1
          }
        ' "$WORK/update-kernel.orig" > "$WORK/update-kernel.patched"
        install -m 0755 "$WORK/update-kernel.patched" "$UPDATE_KERNEL"
    fi
fi

if [ ! -d "$APORTS/.git" ]; then
    git clone --depth=1 https://gitlab.alpinelinux.org/alpine/aports.git "$APORTS"
fi
mkdir -p "$APORTS/scripts"
cp "$ROOT/scripts/mkimg.feather.sh" "$APORTS/scripts/mkimg.feather.sh"
cp "$ROOT/scripts/genapkovl-feather.sh" "$APORTS/scripts/genapkovl-feather.sh"
# mkimage invokes the overlay helper through fakeroot from the aports scripts
# directory. Ensure it is executable there, not only in the source tree.
chmod 0755 "$APORTS/scripts/genapkovl-feather.sh" "$APORTS/scripts/mkimg.feather.sh"
# Make the helper explicitly usable through the exact relative name expected by
# mkimage.sh and verify the interpreter is present.
[ -x "$APORTS/scripts/genapkovl-feather.sh" ] || { echo "ERROR: genapkovl-feather.sh is not executable" >&2; exit 1; }
head -n 1 "$APORTS/scripts/genapkovl-feather.sh" | grep -q '^#!/bin/sh' || { echo "ERROR: invalid genapkovl-feather.sh interpreter" >&2; exit 1; }

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
