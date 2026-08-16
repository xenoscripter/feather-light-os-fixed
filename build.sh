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

# apk-tools v3 requires an APK cache for alternate roots. mkimage invokes
# update-kernel to build the kernel in a temporary alternate root, so patch the
# actual update-kernel executable used by mkimage. The cache must be created
# before the first `apk -p ROOT ... --update-cache` call.
if [ -x /sbin/update-kernel ]; then
    cp /sbin/update-kernel "$WORK/update-kernel.orig"
    awk '
      { print }
      $0 ~ /^[[:space:]]*ROOT=[^ ]*$/ && !done {
        print "mkdir -p \"$ROOT/etc/apk/cache\" \"$ROOT/etc/apk\""
        print "mkdir -p \"$ROOT/var/lib/apk\""
        done=1
      }
    ' "$WORK/update-kernel.orig" > "$WORK/update-kernel.patched"
    install -m 0755 "$WORK/update-kernel.patched" /sbin/update-kernel
fi

# Some Alpine releases define ROOT with additional quoting/assignments. If the
# exact insertion point was not found, patch the APK helper itself so every
# alternate-root transaction initializes its database/cache first.
if ! grep -q 'mkdir -p "$ROOT/etc/apk/cache"' /sbin/update-kernel 2>/dev/null; then
    awk '
      { print }
      $0 ~ /^[[:space:]]*_apk\(\)[[:space:]]*\{/ && !done {
        print "    mkdir -p \"$ROOT/etc/apk/cache\" \"$ROOT/etc/apk\" \"$ROOT/var/lib/apk\""
        done=1
      }
    ' /sbin/update-kernel > "$WORK/update-kernel.patched2"
    install -m 0755 "$WORK/update-kernel.patched2" /sbin/update-kernel
fi

# Final sanity check: the helper actually used by mkimage must initialize the
# alternate APK root before apk is called.
grep -q 'mkdir -p "$ROOT/etc/apk/cache"' /sbin/update-kernel || {
    echo "ERROR: failed to patch update-kernel APK cache initialization" >&2
    exit 1
}

if [ ! -d "$APORTS/.git" ]; then
    git clone --depth=1 https://gitlab.alpinelinux.org/alpine/aports.git "$APORTS"
fi
mkdir -p "$APORTS/scripts"
cp "$ROOT/scripts/mkimg.feather.sh" "$APORTS/scripts/mkimg.feather.sh"
cp "$ROOT/scripts/genapkovl-feather.sh" "$APORTS/scripts/genapkovl-feather.sh"
chmod +x "$ROOT/scripts/genapkovl-feather.sh" "$APORTS/scripts/mkimg.feather.sh"

# apk-tools v3 treats --no-chown as an alias for --usermode, which is rejected
# when mkimage is running as root. Remove both legacy flags from the checked-out
# mkimage scripts before invoking the builder.
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

# mkimage needs an absolute workdir because update-kernel uses a separate
# temporary alternate root during kernel generation.
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
