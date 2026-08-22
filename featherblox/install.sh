#!/bin/sh
set -eu

APP_DIR="$HOME/.local/share/featherblox"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"

mkdir -p "$APP_DIR" "$BIN_DIR" "$DESKTOP_DIR"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cp "$SCRIPT_DIR/featherblox" "$APP_DIR/featherblox"
chmod +x "$APP_DIR/featherblox"
ln -sf "$APP_DIR/featherblox" "$BIN_DIR/featherblox"

cat > "$DESKTOP_DIR/FeatherBlox.desktop" <<EOF
[Desktop Entry]
Name=FeatherBlox
Comment=Lightweight Roblox launcher for MX Linux
Exec=$BIN_DIR/featherblox
Icon=application-x-executable
Terminal=false
Type=Application
Categories=Game;
EOF

if ! command -v flatpak >/dev/null 2>&1; then
  printf '%s\n' 'Flatpak is required. Install it with:'
  printf '%s\n' 'sudo apt update && sudo apt install flatpak'
  exit 1
fi

if ! flatpak remotes --columns=name 2>/dev/null | grep -qx flathub; then
  printf '%s\n' 'Adding Flathub...'
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
fi

printf '%s\n' 'Installing the Roblox runtime used by FeatherBlox (Sober)...'
flatpak install -y flathub org.vinegarhq.Sober

printf '\n%s\n' 'FeatherBlox installed.'
printf '%s\n' 'Run it from the menu or with: featherblox'
printf '%s\n' 'If the command is not found, log out/in or run: export PATH="$HOME/.local/bin:$PATH"'
