{ config, pkgs, lib, ... }:

let
  # --- 1. RELEASE CONFIGURATION ---
  releaseVersion = "v0.0.1";
  githubUser = "sudhanshunitinatalkar";
  githubRepo = "datalog-bin"; 

  # --- 2. THE PACKAGE BUILDER ---
  # This downloads the binary and runs 'nuke-refs' to remove "foreign" 
  # store paths (fixing the 'fixed output derivation' error).
  fetchAndNuke = name: hash: pkgs.runCommand name {
    outputHashMode = "flat";
    outputHashAlgo = "sha256";
    outputHash = hash;
    
    nativeBuildInputs = [ pkgs.curl pkgs.nukeReferences ];
  } ''
    # 1. Download the binary
    curl -L -k "https://github.com/${githubUser}/${githubRepo}/releases/download/${releaseVersion}/${name}" -o $out
    
    # 2. Nuke References (Scrub foreign paths so Nix accepts the file)
    nuke-refs $out
  '';

  # --- 3. BINARY DEFINITIONS ---
  # [UPDATED] Using the nuked hashes you just generated
  binaries = {
    configure  = fetchAndNuke "configure"  "0avbaayd0a3aidp465ngl0xnb1x473ylspx09j6c5xwx10wqf163";
    cpcb       = fetchAndNuke "cpcb"       "1k3xb4cww3hlilwvgljcba9d05n31x9qi8m04vh89l6p8pypbpay";
    data       = fetchAndNuke "data"       "1gzijag2sihwp104hczjsc3p900yy564shm9bjws89cxn982h3ym";
    datalogger = fetchAndNuke "datalogger" "0hlv1rlm5clr8j93jmrbwvlshz9iw8knfva49b7l3m8cb2a2yq73";
    display    = fetchAndNuke "display"    "0m82xhj0aw7p2m8sjdhdcwwxmy7z9ina6zak9d10mmkiwi2s5hf3";
    network    = fetchAndNuke "network"    "0ycnkgqi5ik2xr3gjvik7cxaxfbvykz997h2a4ma5w011vlbkb49";
    saicloud   = fetchAndNuke "saicloud"   "0wwjpfp7cc56l71cxzmb8mjbky9k21gd4vajw56khypzmswiv9ss";
  };

  # --- 4. DIRECTORY SETUP ---
  baseDir = "${config.home.homeDirectory}/datalogger-bin";
  binDir  = "${baseDir}/bin";
  tmpDir  = "${baseDir}/tmp";

  # --- 5. SERVICE GENERATOR ---
  mkService = name: _: {
    Unit = {
      Description = "Datalogger Service: ${name}";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Service = {
      ExecStart = "${binDir}/${name}";
      
      # Use our custom temp dir so we don't fill up RAM (/tmp)
      Environment = "TMPDIR=${tmpDir}";

      Restart = "always";
      RestartSec = "5s";
      StartLimitIntervalSec = "60";
      StartLimitBurst = "5";
      
      StandardOutput = "journal";
      StandardError = "journal";
    };

    Install = { WantedBy = [ "default.target" ]; };
  };

in
{
  # --- 6. ACTIVATION SCRIPT ---
  home.activation.installDataloggerBinaries = lib.hm.dag.entryAfter ["writeBoundary"] ''
    echo "--- [Datalogger] Installing Binaries ---"
    
    mkdir -p "${binDir}"
    mkdir -p "${tmpDir}"

    # Get the dynamic loader path for THIS specific Pi
    INTERPRETER="$(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker)"
    echo "Using System Loader: $INTERPRETER"

    install_and_patch() {
      NAME=$1
      SRC=$2
      DEST="${binDir}/$NAME"

      # Only update if file is missing or changed
      if [ ! -f "$DEST" ] || [ "$(sha256sum $DEST | cut -d' ' -f1)" != "$(sha256sum $SRC | cut -d' ' -f1)" ]; then
        echo "--> Updating $NAME..."
        cp "$SRC" "$DEST"
        chmod +x "$DEST"
        
        # Patch the binary to run on this system
        ${pkgs.patchelf}/bin/patchelf --set-interpreter "$INTERPRETER" "$DEST"
        echo "    (Patched successfully)"
      else
        echo "--> $NAME is up to date."
      fi
    }

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: src: "install_and_patch ${name} ${src}") binaries)}
  '';

  # --- 7. REGISTER SERVICES ---
  systemd.user.services = lib.mapAttrs mkService binaries;
}