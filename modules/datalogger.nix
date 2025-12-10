{ config, pkgs, lib, ... }:

let
  # --- 1. RELEASE CONFIGURATION ---
  # These match your new GitHub Release URL
  releaseVersion = "v0.0.1";
  githubUser = "sudhanshunitinatalkar";
  githubRepo = "datalog-bin"; 

  # Helper to fetch binaries securely
  fetchServiceBin = name: hash: pkgs.fetchurl {
    url = "https://github.com/${githubUser}/${githubRepo}/releases/download/${releaseVersion}/${name}";
    sha256 = hash;
  };

  # --- 2. BINARY DEFINITIONS ---
  # [IMPORTANT] Paste the SHA256 hashes from your GitHub Release page below.
  binaries = {
    configure  = fetchServiceBin "configure"  "INSERT_CONFIGURE_HASH_HERE";
    cpcb       = fetchServiceBin "cpcb"       "INSERT_CPCB_HASH_HERE";
    data       = fetchServiceBin "data"       "INSERT_DATA_HASH_HERE";
    datalogger = fetchServiceBin "datalogger" "INSERT_DATALOGGER_HASH_HERE";
    display    = fetchServiceBin "display"    "INSERT_DISPLAY_HASH_HERE";
    network    = fetchServiceBin "network"    "INSERT_NETWORK_HASH_HERE";
    saicloud   = fetchServiceBin "saicloud"   "INSERT_SAICLOUD_HASH_HERE";
  };

  # --- 3. DIRECTORY SETUP ---
  # We create a specific folder for binaries and a specific 'tmp' folder
  # so PyInstaller does not fill up the system RAM.
  baseDir = "${config.home.homeDirectory}/datalogger-bin";
  binDir  = "${baseDir}/bin";
  tmpDir  = "${baseDir}/tmp";

  # --- 4. SERVICE GENERATOR ---
  mkService = name: {
    Unit = {
      Description = "Datalogger Service: ${name}";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Service = {
      # Point to the patched binary in the home directory
      ExecStart = "${binDir}/${name}";

      # [CRITICAL FIX] Tell PyInstaller to unpack in our directory, not /tmp (RAM)
      Environment = "TMPDIR=${tmpDir}";

      # Restart policy: Always restart, but wait 5s between attempts
      Restart = "always";
      RestartSec = "5s";
      
      # Stop restart loop if it crashes 5 times in 60 seconds
      StartLimitIntervalSec = "60";
      StartLimitBurst = "5";
      
      # Logging to system journal
      StandardOutput = "journal";
      StandardError = "journal";
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };

in
{
  # --- 5. ACTIVATION SCRIPT (Installs & Patches Binaries) ---
  # This runs every time you deploy/switch Home Manager.
  home.activation.installDataloggerBinaries = lib.hm.dag.entryAfter ["writeBoundary"] ''
    echo "--- [Datalogger] Installing Binaries ---"
    
    # Ensure directories exist
    mkdir -p "${binDir}"
    mkdir -p "${tmpDir}"

    # Get the dynamic loader (interpreter) for THIS specific Raspberry Pi OS
    INTERPRETER="$(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker)"
    echo "Using System Loader: $INTERPRETER"

    install_and_patch() {
      NAME=$1
      SRC=$2
      DEST="${binDir}/$NAME"

      # Only update if the file is missing or the hash has changed
      if [ ! -f "$DEST" ] || [ "$(sha256sum $DEST | cut -d' ' -f1)" != "$(sha256sum $SRC | cut -d' ' -f1)" ]; then
        echo "--> Updating $NAME..."
        cp "$SRC" "$DEST"
        chmod +x "$DEST"
        
        # [MAGIC STEP] Patch the binary header to use the local system loader.
        # This fixes the "No such file or directory" error.
        ${pkgs.patchelf}/bin/patchelf --set-interpreter "$INTERPRETER" "$DEST"
        echo "    (Patched successfully)"
      else
        echo "--> $NAME is up to date."
      fi
    }

    # Loop through all binaries defined above
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: src: "install_and_patch ${name} ${src}") binaries)}
  '';

  # --- 6. SYSTEMD SERVICE REGISTRATION ---
  # Automatically generate a service for every binary defined in the list
  systemd.user.services = lib.mapAttrs mkService binaries;
}