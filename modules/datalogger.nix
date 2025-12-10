{ config, pkgs, lib, ... }:

let
  # --- Configuration ---
  
  # 1. Target Directory for Binaries
  targetDir = "${config.home.homeDirectory}/datalogger-bin";

  # 2. Release URL (datalog-bin v0.0.1)
  repoOwner = "sudhanshunitinatalkar";
  repoName = "datalog-bin"; 
  releaseTag = "v0.0.1";
  zipName = "release.zip";
  releaseUrl = "https://github.com/${repoOwner}/${repoName}/releases/download/${releaseTag}/${zipName}";

  # 3. Service Names
  # These match the binary names inside the zip file
  serviceNames = [ 
    "configure" 
    "cpcb" 
    "data" 
    "datalogger" 
    "diag"
    "display" 
    "network" 
    "saicloud" 
  ];

  # --- Service Generator ---
  # Creates a simple systemd service for each binary
  mkDataloggerService = name: {
    Unit = {
      Description = "Datalogger Service: ${name}";
      # Wait for network and the updater to finish before starting
      After = [ "network-online.target" "datalogger-updater.service" ];
      Wants = [ "network-online.target" ];
    };

    Service = {
      # Path to the binary
      ExecStart = "${targetDir}/bin/${name}";
      
      # Restart automatically if it crashes
      Restart = "always";
      RestartSec = "5s";

      # [CRITICAL] Use a persistent temp folder in Home so binaries can unpack themselves
      Environment = "TMPDIR=%h/datalogger-tmp";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/datalogger-tmp";

      # Logging
      StandardOutput = "journal";
      StandardError = "journal";
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };

in
{
  # --- 1. Updater Service ---
  # This runs ONCE at boot to download/update the binaries
  systemd.user.services.datalogger-updater = {
    Unit = {
      Description = "Fetch datalogger binaries";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Service = {
      Type = "oneshot";
      # Script to download zip, extract, and copy binaries
      ExecStart = pkgs.writeShellScript "update-datalogger" ''
        export PATH=${lib.makeBinPath [ pkgs.curl pkgs.unzip pkgs.systemd pkgs.coreutils ]}:$PATH
        
        TARGET_BIN="${targetDir}/bin"
        mkdir -p "$TARGET_BIN"
        
        # Use a temp folder in HOME for downloading
        mkdir -p "$HOME/datalogger-update-tmp"
        TEMP_DIR=$(mktemp -d -p "$HOME/datalogger-update-tmp")
        ZIP_FILE="$TEMP_DIR/${zipName}"
        
        echo "--- Starting Update ---"
        echo "Downloading from: ${releaseUrl}"
        
        if curl -L -f -o "$ZIP_FILE" "${releaseUrl}"; then
          echo "Download successful. Extracting..."
          unzip -o "$ZIP_FILE" -d "$TEMP_DIR/extracted"

          # Install binaries
          # Finds the files matching serviceNames anywhere in the zip and copies them
          SERVICES="${lib.concatStringsSep " " serviceNames}"
          for svc in $SERVICES; do
            FOUND_FILE=$(find "$TEMP_DIR/extracted" -name "$svc" -type f | head -n 1)
            if [ -n "$FOUND_FILE" ]; then
              echo "Installing $svc..."
              cp -f "$FOUND_FILE" "$TARGET_BIN/$svc"
              chmod +x "$TARGET_BIN/$svc"
            else
              echo "Warning: $svc not found in zip."
            fi
          done
          
          rm -rf "$TEMP_DIR"
          
          # Restart the services to pick up the new binaries
          echo "Restarting services..."
          systemctl --user restart $SERVICES
          echo "Done."
        else
          echo "Download failed."
          rm -rf "$TEMP_DIR"
          exit 1
        fi
      '';
    };
  };

  # --- 2. Timer (Auto-Update) ---
  systemd.user.timers.datalogger-updater = {
    Unit = { Description = "Check for updates periodically"; };
    Timer = {
      OnBootSec = "1m";
      OnUnitActiveSec = "5m";
    };
    Install = { WantedBy = [ "timers.target" ]; };
  };

  # --- 3. Merge Generated Services ---
  # This merges the manually defined updater with the auto-generated services
  systemd.user.services = lib.genAttrs serviceNames mkDataloggerService;
}