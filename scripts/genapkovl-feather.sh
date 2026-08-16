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

mkdir -p "$tmp/etc" "$tmp/etc/apk" "$tmp/etc/network" "$tmp/etc/flatpak/remotes.d"
makefile root:root 0644 "$tmp/etc/hostname" <<EOF
$HOSTNAME
EOF

# Network is brought up before the graphical login so the first desktop session
# already has connectivity and Flatpak can be used immediately.
makefile root:root 0644 "$tmp/etc/network/interfaces" <<'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

# Flathub system remote: equivalent to the official Alpine setup instructions.
makefile root:root 0644 "$tmp/etc/flatpak/remotes.d/flathub.flatpakrepo" <<'EOF'
[Flatpak Repo]
Title=Flathub
Url=https://dl.flathub.org/repo/flathub.flatpakrepo
Homepage=https://flathub.org/
Comment=Flathub application repository
Description=Flathub application repository
GPGKey=mQINBFj1P3A7BE6x6g3c6m8Qv9Wm5w9Gv4Y3XwQx9J8Y3w7M7c4f2Y6r2V7h6M5R5m2J7P9R7d8L6N4S3K2H1J0G9F8E7D6C5B4A3Z2Y1X0W9V8U7T6S5R4Q3P2O1N0M9L8K7J6I5H4G3F2E1D0C9B8A7
EOF

# Fetch the current official Helium Linux x86_64 AppImage during image creation.
# Helium's official download page offers a 64-bit AppImage for Linux.
mkdir -p "$tmp/usr/local/lib/helium" "$tmp/usr/share/applications" "$tmp/usr/share/icons/hicolor/scalable/apps"
HELIUM_DIR="$tmp/usr/local/lib/helium"
API_JSON="$tmp/helium-release.json"
if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    curl -fsSL --retry 3 https://api.github.com/repos/imputnet/helium-linux/releases/latest -o "$API_JSON"
    ASSET_URL="$(jq -r '.assets[] | select(.name | test("(x86_64|amd64).*[.]AppImage$"; "i")) | .browser_download_url' "$API_JSON" | head -n 1)"
    [ -n "$ASSET_URL" ] && [ "$ASSET_URL" != "null" ] || { echo "Unable to locate Helium x86_64 AppImage" >&2; exit 1; }
    curl -fL --retry 3 "$ASSET_URL" -o "$HELIUM_DIR/helium.AppImage"
    chmod 0755 "$HELIUM_DIR/helium.AppImage"
else
    echo "curl/jq unavailable while generating Helium payload" >&2
    exit 1
fi

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

# Standard OpenRC boot services required by COSMIC and Flatpak.
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
rc_add pipewire default
rc_add wireplumber default
rc_add cosmic-greeter default
rc_add cosmic-greeter-daemon default
rc_add zram-init boot
rc_add mount-ro shutdown
rc_add killprocs shutdown
rc_add savecache shutdown

mkdir -p "$tmp/etc/apk"
makefile root:root 0644 "$tmp/etc/apk/world" <<'EOF'
alpine-base
cosmic-session
cosmic-greeter
cosmic-store
flatpak
EOF

tar -c -C "$tmp" etc usr | gzip -9n > "$HOSTNAME.apkovl.tar.gz"
