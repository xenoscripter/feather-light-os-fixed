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

# Alpine has moved update-kernel between package releases. Never assume it is
# /sbin/update-kernel: resolve the installed helper first. The previous build
# failed before mkimage even started because that hard-coded path did not exist.
UPDATE_KERNEL="$(command -v update-kernel 2>/dev/null || true)"
if [ -z "$UPDATE_KERNEL" ]; then
    UPDATE_KERNEL="$(find /sbin /usr/sbin /usr/bin /usr/libexec -type f -name update-kernel -print -quit 2>/dev/null || true)"
fi

if [ -n "$UPDATE_KERNEL" ] && [ -f "$UPDATE_KERNEL" ]; then
    cp "$UPDATE_KERNEL" "$WORK/update-kernel.orig"
    # Only patch when the helper actually contains the alternate-root ROOT
    # assignment. This avoids corrupting newer Alpine implementations.
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
else
    echo "INFO: update-kernel is not installed in the host container; mkimage will provide/use its own helper."
fi

# Alpine apk-tools v3 treats --no-chown as an alias for --usermode, which is
# rejected when mkimage runs as root. Remove those legacy flags from the actual
# mkimage scripts after aports is cloned.
if [ ! -d "$APORTS/.git" ]; then
    git clone --depth=1 https://gitlab.alpinelinux.org/alpine/aports.git "$APORTS"
fi
mkdir -p "$APORTS/scripts"
cp "$ROOT/scripts/mkimg.feather.sh" "$APORTS/scripts/mkimg.feather.sh"
cp "$ROOT/scripts/genapkovl-feather.sh" "$APORTS/scripts/genapkovl-feather.sh"
chmod +x "$ROOT/scripts/genapkovl-feather.sh" "$APORTS/scripts/mkimg.feather.sh"

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
