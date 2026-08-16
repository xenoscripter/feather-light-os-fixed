profile_feather() {
    profile_standard
    profile_abbrev="feather"
    title="Feather Light OS V2 COSMIC"
    desc="COSMIC desktop optimized for 3 GB RAM systems."
    arch="x86_64"
    image_ext="iso"
    output_format="iso"
    kernel_flavors="lts"

    apks="$apks
        linux-lts linux-firmware
        dbus dbus-openrc elogind elogind-openrc
        networkmanager networkmanager-openrc
        pipewire pipewire-pulse wireplumber
        mesa-dri-gallium mesa-egl mesa-gbm
        xwayland
        cosmic-session cosmic-comp cosmic-panel cosmic-launcher
        cosmic-files cosmic-settings cosmic-workspaces
        cosmic-notifications cosmic-osd cosmic-screenshot
        cosmic-edit cosmic-term
        flatpak
        xdg-desktop-portal xdg-desktop-portal-cosmic
        curl ca-certificates wget
        zram-init
        font-noto font-noto-cjk
        polkit-elogind polkit
        greetd greetd-openrc
        
        # Hardware/network essentials
        pciutils usbutils util-linux
        
        # Avoid the standard desktop file manager/browser; COSMIC Files is the shell-integrated file manager,
        # while Helium is installed by the overlay before graphical login.
        "

    initfs_features="$initfs_features kms"
    boot_addons="amd-ucode intel-ucode"
    initrd_ucode="/boot/amd-ucode.img /boot/intel-ucode.img"
    apkovl="genapkovl-feather.sh"
}
