#!/bin/sh -e

HOSTNAME="$1"
[ -n "$HOSTNAME" ] || { echo "usage: $0 hostname" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

makefile() {
    owner="$1"; perms="$2"; file="$3"
    mkdir -p "$(dirname "$file")"
    cat > "$file"
    chown "$owner" "$file"
    chmod "$perms" "$file"
}

rc_add() {
    mkdir -p "$tmp/etc/runlevels/$2"
    ln -sf "/etc/init.d/$1" "$tmp/etc/runlevels/$2/$1"
}

mkdir -p "$tmp/etc" "$tmp/etc/network" "$tmp/etc/flatpak/remotes.d" "$tmp/var/lib/flatpak"
makefile root:root 0644 "$tmp/etc/hostname" <<EOF
$HOSTNAME
EOF

makefile root:root 0644 "$tmp/etc/network/interfaces" <<'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

# Install the official Flathub repository definition for Alpine.
FLATHUB_REPO_URL="https://dl.flathub.org/repo/flathub.flatpakrepo"
FLATHUB_FILE="$tmp/etc/flatpak/remotes.d/flathub.flatpakrepo"
curl -fsSL --retry 3 "$FLATHUB_REPO_URL" -o "$FLATHUB_FILE"
chmod 0644 "$FLATHUB_FILE"
# Validate the downloaded metadata, but do not require the download URL to
# appear verbatim in the file. Flatpak repo metadata uses a base repository URL.
grep -Fq '[Flatpak Repo]' "$FLATHUB_FILE" || {
    echo "ERROR: downloaded Flathub repository definition is invalid" >&2
    exit 1
}
grep -Eq '^Url=https://(dl\.)?flathub.org/repo/?$' "$FLATHUB_FILE" || {
    echo "ERROR: downloaded Flathub repository definition has an invalid Url" >&2
    exit 1
}

# Fetch the current official Helium Linux x86_64 AppImage during image creation.
mkdir -p "$tmp/usr/local/lib/helium" "$tmp/usr/share/applications"
HELIUM_DIR="$tmp/usr/local/lib/helium"
API_JSON="$tmp/helium-release.json"
curl -fsSL --retry 3 https://api.github.com/repos/imputnet/helium-linux/releases/latest -o "$API_JSON"
ASSET_URL="$(jq -r '.assets[] | select(.name | test("(x86_64|amd64).*[.]AppImage$"; "i")) | .browser_download_url' "$API_JSON" | head -n 1)"
[ -n "$ASSET_URL" ] && [ "$ASSET_URL" != "null" ] || { echo "Unable to locate Helium x86_64 AppImage" >&2; exit 1; }
curl -fL --retry 3 "$ASSET_URL" -o "$HELIUM_DIR/helium.AppImage"
chmod 0755 "$HELIUM_DIR/helium.AppImage"

makefile root:root 0755 "$tmp/usr/local/bin/helium" <<'EOF'
#!/bin/sh
exec /usr/local/lib/helium/helium.AppImage "$@"
EOF

makefile root:root 0644 "$tmp/usr/share/applications/helium.desktop" <<'EOF'
[Desktop Entry]
Name=Helium
Comment=Helium Browser
Exec=/usr/local/bin/helium %U
Terminal=false
Type=Application
Categories=Network;WebBrowser;
StartupNotify=true
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
EOF

rc_add devfs sysinit
rc_add dmesg sysinit
rc_add mdev sysinit
rc_add hwdrivers sysinit
rc_add modloop sysinit
rc_add hwclock boot
rc_add modules boot
rc_add sysctl boot
rc_add hostname boot
rc_add bootmisc boot
rc_add networking boot
rc_add dbus boot
rc_add elogind boot
rc_add NetworkManager default
rc_add cosmic-greeter default
rc_add cosmic-greeter-daemon default
rc_add zram-init boot
rc_add mount-ro shutdown
rc_add killprocs shutdown
rc_add savecache shutdown

tar -c -C "$tmp" etc usr | gzip -9n > "$HOSTNAME.apkovl.tar.gz"
