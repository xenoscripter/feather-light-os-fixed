#!/bin/sh
set -eu

ALPINE_VERSION="3.22"
ARCH="x86_64"
ISO_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ARCH}/alpine-standard-${ALPINE_VERSION}.0-${ARCH}.iso"
WORK="${1:-work}"
OUT="${2:-out}"

rm -rf "$WORK" "$OUT"
mkdir -p "$WORK/iso" "$OUT"
curl -fL "$ISO_URL" -o "$WORK/alpine.iso"
7z x -y "$WORK/alpine.iso" -o"$WORK/iso" >/dev/null

# Replace the BIOS ISOLINUX menu while preserving Alpine's known-good kernel/initramfs.
mkdir -p "$WORK/iso/isolinux"
cat > "$WORK/iso/isolinux/isolinux.cfg" <<'EOF'
DEFAULT normal
PROMPT 1
TIMEOUT 80
UI menu.c32
MENU TITLE FEATHER LIGHT OS

LABEL normal
  MENU LABEL ^Normal Boot
  KERNEL /boot/vmlinuz-lts
  INITRD /boot/initramfs-lts
  APPEND alpine_repo=http://dl-cdn.alpinelinux.org/alpine/v3.22/main modloop=/boot/modloop-lts

LABEL safe
  MENU LABEL ^Safe Hardware Mode
  KERNEL /boot/vmlinuz-lts
  INITRD /boot/initramfs-lts
  APPEND alpine_repo=http://dl-cdn.alpinelinux.org/alpine/v3.22/main modloop=/boot/modloop-lts nomodeset pci=nomsi

LABEL graphics
  MENU LABEL Safe Graphics Mode
  KERNEL /boot/vmlinuz-lts
  INITRD /boot/initramfs-lts
  APPEND alpine_repo=http://dl-cdn.alpinelinux.org/alpine/v3.22/main modloop=/boot/modloop-lts nomodeset

LABEL recovery
  MENU LABEL Recovery Shell
  KERNEL /boot/vmlinuz-lts
  INITRD /boot/initramfs-lts
  APPEND alpine_repo=http://dl-cdn.alpinelinux.org/alpine/v3.22/main modloop=/boot/modloop-lts init=/bin/sh
EOF

# Rebuild a hybrid BIOS/UEFI bootable ISO using xorriso and Alpine's existing boot images.
xorriso -as mkisofs -o "$OUT/feather-light-os-fixed-x86_64.iso" \
  -isohybrid-mbr "$WORK/iso/isolinux/isohdpfx.bin" \
  -c isolinux/isolinux.bin -b isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot -e boot/efiboot.img -no-emul-boot \
  -isohybrid-gpt-basdat "$WORK/iso"

sha256sum "$OUT/feather-light-os-fixed-x86_64.iso" > "$OUT/SHA256SUMS"
