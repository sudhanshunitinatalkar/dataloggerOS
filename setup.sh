#!/bin/bash

# This script is designed to set up a Raspberry Pi.
# It should be run with root privileges (e.g., "sudo ./raspberry_pi_setup.sh")
# Using "set -e" to exit immediately if any command fails.
set -e

echo "--- [Step 1/5] Starting Full System Update & Upgrade ---"
# This updates the package lists and upgrades all installed packages.
# This also updates the Raspberry Pi firmware to the latest stable version.
apt update
apt upgrade -y
echo "--- System update complete. ---"
echo ""

echo "--- [Step 2/5] Installing Nix Package Manager (Daemon) ---"
# This runs the official installer script for Nix in daemon (multi-user) mode.
# The installer may ask you for input or confirmation.
sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --daemon
echo "--- Nix installation complete. ---"
echo "NOTE: You may need to source the nix script (e.g., . /home/$USER/.nix-profile/etc/profile.d/nix.sh) or restart your shell after this script."
echo ""

echo "--- [Step 3/5] Enabling Automatic Security Updates ---"
# This installs and configures 'unattended-upgrades' to automatically
# apply security updates in the background.
apt install unattended-upgrades -y
dpkg-reconfigure -plow unattended-upgrades
echo "--- Automatic updates enabled. ---"
echo ""

echo "--- [Step 4/5] Enabling User Services on Boot (Linger) ---"
# This allows systemd user services (like those Nix may create)
# to start at boot, even before a user logs in.

# We need to know WHICH user to enable this for.
read -p "Please enter the username to enable boot services for (e.g., 'pi' or 'admin'): " linger_user

if [ -z "$linger_user" ]; then
    echo "No username provided. Skipping this step."
    echo "You can run 'sudo loginctl enable-linger <username>' manually later."
else
    loginctl enable-linger "$linger_user"
    echo "--- User services (linger) enabled for '$linger_user'. ---"
fi
echo ""

echo "--- [Step 5/5] Setup Complete. Rebooting... ---"
echo "The system will reboot in 10 seconds. Press Ctrl+C to cancel."
sleep 10
reboot