#!/bin/bash

# This script is designed to set up a Raspberry Pi for production datalogger use.
# It MUST be run with root privileges (e.g., "sudo ./raspberry_pi_setup.sh")
#
# set -e : Exit immediately if a command exits with a non-zero status.
# set -u : Treat unset variables as an error when substituting.
# set -o pipefail : The return value of a pipeline is the status of
#                   the last command to exit with a non-zero status,
#                   or zero if no command exited with a non-zero status.
set -euo pipefail

# --- [Step 0/11] Root User Check ---
if [ "$(id -u)" -ne 0 ]; then
  echo "!!! This script must be run as root (with sudo). Exiting. !!!"
  exit 1
fi

echo "--- [Step 1/11] Starting Full System Update & Upgrade ---"
# This updates the package lists and upgrades all installed packages.
apt update
apt upgrade -y
echo "--- System update complete. ---"
echo ""

echo "--- [Step 2/11] Applying Raspberry Pi EEPROM Firmware Updates ---"
# This attempts to apply any pending bootloader/EEPROM firmware updates.
if command -v rpi-eeprom-update >/dev/null 2>&1; then
  echo "Found rpi-eeprom-update. Applying any pending firmware updates..."
  rpi-eeprom-update -a
else
  echo "rpi-eeprom-update tool not found. Skipping (this is normal for older Pi models)."
fi
echo "--- EEPROM update check complete. ---"
echo ""

echo "--- [Step 3/11] Cleaning up previous Nix install artifacts ---"
rm -f /etc/bashrc.backup-before-nix
rm -f /etc/profile.d/nix.sh.backup-before-nix
rm -f /etc/zshrc.backup-before-nix
rm -f /etc/bash.bashrc.backup-before-nix
echo "--- Old artifact cleanup complete. ---"
echo ""

echo "--- [Step 4/11] Installing Nix Package Manager (Daemon) ---"
if [ -d "/nix" ]; then
    echo "The /nix directory already exists."
    echo "--- Nix appears to be already installed. Skipping installation. ---"
else
    echo "No existing /nix directory found. Starting new installation..."
    curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install | sh -s -- --daemon
    echo "--- Nix installation complete. ---"
fi
echo ""

echo "--- [Step 5/11] Configuring Nix for Flakes ---"
NIX_CONF_FILE="/etc/nix/nix.conf"
NIX_CONF_LINE="experimental-features = nix-command flakes"
mkdir -p /etc/nix
touch "$NIX_CONF_FILE"

if ! grep -qF "$NIX_CONF_LINE" "$NIX_CONF_FILE"; then
    echo "Adding '$NIX_CONF_LINE' to $NIX_CONF_FILE..."
    echo "$NIX_CONF_LINE" >> "$NIX_CONF_FILE"
    echo "--- Nix configuration updated. ---"
else
    echo "--- Nix configuration already set for flakes. Skipping. ---"
fi
echo ""

echo "--- [Step 6/11] Enabling Automatic Security Updates ---"
apt install unattended-upgrades -y
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -plow unattended-upgrades
echo "--- Automatic updates enabled. ---"
echo ""

echo "--- [Step 7/11] Enabling User Services on Boot (Linger) ---"
if [ -z "${SUDO_USER:-}" ]; then
    echo "!!! Could not find \$SUDO_USER. Skipping linger step. !!!"
elif [ "$SUDO_USER" = "root" ]; then
    echo "!!! Script was run by root directly. Skipping linger step. !!!"
elif id -u "$SUDO_USER" >/dev/null 2>&1; then
    echo "--- Automatically enabling linger for user '$SUDO_USER'... ---"
    loginctl enable-linger "$SUDO_USER"
    echo "--- User services (linger) enabled for '$SUDO_USER'. ---"
else
    echo "!!! User '$SUDO_USER' does not seem to exist. Skipping linger step. !!!"
fi
echo ""

echo "--- [Step 8/11] Enabling Hardware Datalogger Interfaces ---"
if command -v raspi-config >/dev/null 2>&1; then
  echo "Enabling I2C..."
  raspi-config nonint do_i2c 0
  echo "Enabling SPI..."
  raspi-config nonint do_spi 0
  echo "Enabling Serial Hardware (disabling serial console)..."
  raspi-config nonint do_serial_hw 0
  echo "--- Hardware interfaces enabled. ---"
else
  echo "--- raspi-config not found. Skipping hardware interface setup. ---"
fi
echo ""

echo "--- [Step 9/11] Configuring /boot/firmware/config.txt ---"
# This step handles hardware watchdog, UART enablement, and Bluetooth disabling.
CONFIG_FILE="/boot/firmware/config.txt"

# List of settings to apply
SETTINGS=(
    "dtparam=watchdog=on"
    "enable_uart=1"
    "dtoverlay=disable-bt"
)

if [ -f "$CONFIG_FILE" ]; then
    echo "Backing up config.txt to config.txt.bak..."
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

    # Ensure there is a newline at the end of the file before we start appending
    # This prevents appending to the end of an existing line
    sed -i -e '$a\' "$CONFIG_FILE"

    for setting in "${SETTINGS[@]}"; do
        if ! grep -qF "$setting" "$CONFIG_FILE"; then
            echo "Adding '$setting' to $CONFIG_FILE..."
            echo "$setting" >> "$CONFIG_FILE"
        else
            echo "--- '$setting' already exists. Skipping. ---"
        fi
    done
    echo "--- Hardware configuration updated. ---"
else
    echo "--- $CONFIG_FILE not found. Skipping config.txt setup. ---"
fi
echo ""

echo "--- [Step 10/11] Creating Datalogger Data Directory ---"
DATALOGGER_DIR="/var/lib/datalogger"

if [ -z "${SUDO_USER:-}" ] || [ "$SUDO_USER" = "root" ]; then
    echo "!!! Cannot determine correct user. Skipping data directory creation. !!!"
elif id -u "$SUDO_USER" >/dev/null 2>&1; then
    echo "--- Creating directory '$DATALOGGER_DIR' for user '$SUDO_USER'... ---"
    mkdir -p "$DATALOGGER_DIR"
    chown "$SUDO_USER":"$SUDO_USER" "$DATALOGGER_DIR"
    echo "--- Datalogger data directory created and permissions set. ---"
else
    echo "!!! User '$SUDO_USER' does not exist. Skipping. !!!"
fi
echo ""

echo "--- [Step 11/11] Setup Complete. Rebooting... ---"
echo "The system will reboot in 10 seconds. Press Ctrl+C to cancel."
sleep 10
reboot
