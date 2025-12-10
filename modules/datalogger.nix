{ config, pkgs, lib, ... }:

let
  # --- 1. RELEASE CONFIGURATION ---
  releaseVersion = "v0.0.1";
  githubUser = "sudhanshunitinatalkar";
  githubRepo = "datalog-bin"; 

  # [FIX] We use 'pkgs.runCommand' instead of 'fetchurl'.
  # This gives us full control to set 'unsafeDiscardReferences = true',
  # which forces Nix to ignore the Python paths inside your compiled binaries.
  fetchServiceBin = name: hash: pkgs.runCommand name {
    # Fixed Output Derivation settings (allows network access during build)
    outputHashMode = "flat";
    outputHashAlgo = "sha256";
    outputHash = hash;
    
    # CRITICAL: Tell Nix to ignore any /nix/store paths inside the binary
    unsafeDiscardReferences = true;
    
    # We need curl to download the file
    nativeBuildInputs = [ pkgs.curl ];
  } ''
    # Download the file (-L follows redirects, -k skips SSL cert check since we check the hash)
    curl -L -k "https://github.com/${githubUser}/${githubRepo}/releases/download/${releaseVersion}/${name}" -o $out
  '';

  # --- 2. BINARY DEFINITIONS ---
  # (Hashes from your GitHub release)
  binaries = {
    configure  = fetchServiceBin "configure"  "cf8fe1fdfde3c70ef430cbeba6d4217d83279184586235489d813470c2269a9b";
    cpcb       = fetchServiceBin "cpcb"       "2674172bcbe42ae23511bb41c49b646c8792271871216503c80631310185975d";
    data       = fetchServiceBin "data"       "b0658b2ab95ee734fe415f2b8e4e937746199583487056093847990177786851";
    datalogger = fetchServiceBin "datalogger" "c8353df20f366d84017fc49f6a7385da418430f9a2d677894d0149023472719d";
    display    = fetchServiceBin "display"    "b3b2c44663a7304335908d487e076632427e1b99793132715003c2718e000494";
    network    = fetchServiceBin "network"    "2e3c5a652005134039f83e23e3e264663c46d328906649779d71783863486333";
    saicloud   = fetchServiceBin "saicloud"   "856e23fb78502f9e7c554fa010f38b005391694f277123985798993883a88626";
  };

  # --- 3. DIRECTORY SETUP ---
  baseDir = "${config.home.homeDirectory}/datalogger-bin";
  binDir  = "${baseDir}/bin";
  tmpDir  = "${baseDir}/tmp";

  # --- 4. SERVICE GENERATOR ---
  mkService = name: _: {
    Unit = {
      Description = "Datalogger Service: ${name}";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Service = {
      ExecStart = "${binDir}/${name}";
      Environment = "TMPDIR=${tmpDir}";

      Restart = "always";
      RestartSec = "5s";
      StartLimitIntervalSec = "60";
      StartLimitBurst = "5";
      
      StandardOutput = "journal";
      StandardError = "journal";
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };

in
{
  # --- 5. ACTIVATION SCRIPT ---
  home.activation.installDataloggerBinaries = lib.hm.dag.entryAfter ["writeBoundary"] ''
    echo "--- [Datalogger] Installing Binaries ---"
    
    mkdir -p "${binDir}"
    mkdir -p "${tmpDir}"

    INTERPRETER="$(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker)"
    echo "Using System Loader: $INTERPRETER"

    install_and_patch() {
      NAME=$1
      SRC=$2
      DEST="${binDir}/$NAME"

      if [ ! -f "$DEST" ] || [ "$(sha256sum $DEST | cut -d' ' -f1)" != "$(sha256sum $SRC | cut -d' ' -f1)" ]; then
        echo "--> Updating $NAME..."
        cp "$SRC" "$DEST"
        chmod +x "$DEST"
        
        ${pkgs.patchelf}/bin/patchelf --set-interpreter "$INTERPRETER" "$DEST"
        echo "    (Patched successfully)"
      else
        echo "--> $NAME is up to date."
      fi
    }

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: src: "install_and_patch ${name} ${src}") binaries)}
  '';

  # --- 6. SYSTEMD SERVICE REGISTRATION ---
  systemd.user.services = lib.mapAttrs mkService binaries;
}