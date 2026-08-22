# FeatherBlox

FeatherBlox is a very small MX Linux launcher for Roblox. It is designed for low-resource machines and avoids a Wine prefix or a full Android emulator.

## Important

FeatherBlox is a launcher/integration layer, not a reimplementation of Roblox. It installs and starts the upstream Sober runtime from Flathub. Sober is experimental and is not supported by Roblox.

## Install on MX Linux

```sh
sudo apt update
sudo apt install -y git flatpak
mkdir -p "$HOME/featherblox"
git clone https://github.com/xenoscripter/feather-light-os-fixed.git "$HOME/featherblox-repo"
cd "$HOME/featherblox-repo/featherblox"
sh install.sh
```

Then launch **FeatherBlox** from the application menu or run:

```sh
export PATH="$HOME/.local/bin:$PATH"
featherblox
```

## Low-end philosophy

- X11-friendly
- No forced Vulkan settings
- No VM
- No Wine prefix
- Uses the existing MX Linux graphics stack
- Keeps the launcher itself extremely small

Compatibility with very old Intel integrated graphics is not guaranteed. The T4400-era Intel GPU should be tested before expecting Roblox to run well.
