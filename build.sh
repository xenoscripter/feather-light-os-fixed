#!/bin/sh
set -eu
ALPINE_VERSION="3.22"; ARCH="x86_64"
ISO_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ARCH}/alpine-standard-${ALPINE_VERSION}.0-${ARCH}.iso"
WORK="${1:-work}"; OUT="${2:-out}"
rm -rf "$WORK" "$OUT"; mkdir -p "$WORK/iso" "$OUT"
curl -fL "$ISO_URL" -o "$WORK/alpine.iso"
7z x -y "$WORK/alpine.iso" -o"$WORK/iso" >/dev/null
ISODIR="$(cd "$WORK/iso" && pwd)"
BOOTDIR=$(dirname "$(find "$ISODIR" -type f -name isolinux.bin -print -quit)")
[ -n "$BOOTDIR" ]
KERNEL=$(find "$ISODIR" -type f -name vmlinuz-lts -print -quit)
INITRD=$(find "$ISODIR" -type f -name initramfs-lts -print -quit)
[ -f "$KERNEL" ] && [ -f "$INITRD" ]
KERNEL_REL=${KERNEL#"$ISODIR/"}
INITRD_REL=${INITRD#"$ISODIR/"}
MENU=$(find "$ISODIR" -type f -name menu.c32 -print -quit || true)
MENU_LINE=""
[ -n "$MENU" ] && MENU_LINE="UI menu.c32"
cat > "$BOOTDIR/isolinux.cfg" <<EOF
DEFAULT normal
PROMPT 0
TIMEOUT 100
$MENU_LINE
MENU TITLE FEATHER LIGHT OS

LABEL normal
  MENU LABEL Normal Boot
  KERNEL /$KERNEL_REL
  INITRD /$INITRD_REL
  APPEND alpine_repo=http://dl-cdn.alpinelinux.org/alpine/v3.22/main console=ttyS0,115200n8 edd=off

LABEL safe
  MENU LABEL Safe Hardware Mode
  KERNEL /$KERNEL_REL
  INITRD /$INITRD_REL
  APPEND alpine_repo=http://dl-cdn.alpinelinux.org/alpine/v3.22/main nomodeset pci=nomsi console=ttyS0,115200n8 edd=off

LABEL graphics
  MENU LABEL Safe Graphics Mode
  KERNEL /$KERNEL_REL
  INITRD /$INITRD_REL
  APPEND alpine_repo=http://dl-cdn.alpinelinux.org/alpine/v3.22/main nomodeset console=ttyS0,115200n8 edd=off

LABEL recovery
  MENU LABEL Recovery Shell
  KERNEL /$KERNEL_REL
  INITRD /$INITRD_REL
  APPEND alpine_repo=http://dl-cdn.alpinelinux.org/alpine/v3.22/main init=/bin/sh console=ttyS0,115200n8 edd=off
EOF
ISOLINUX_REL=${BOOTDIR#"$ISODIR/"}
ISODHPFX=$(find "$ISODIR" -type f -name isohdpfx.bin -print -quit || true)
EFIBOOT=$(find "$ISODIR" -type f -name efiboot.img -print -quit || true)
ARGS="-as mkisofs -o $OUT/feather-light-os-fixed-x86_64.iso -b $ISOLINUX_REL/isolinux.bin -c $ISOLINUX_REL/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table"
[ -n "$ISODHPFX" ] && ARGS="$ARGS -isohybrid-mbr $ISODHPFX"
[ -n "$EFIBOOT" ] && ARGS="$ARGS -eltorito-alt-boot -e ${EFIBOOT#"$ISODIR/"} -no-emul-boot -isohybrid-gpt-basdat"
# shellcheck disable=SC2086
xorriso $ARGS "$ISODIR"
sha256sum "$OUT/feather-light-os-fixed-x86_64.iso" > "$OUT/SHA256SUMS"
