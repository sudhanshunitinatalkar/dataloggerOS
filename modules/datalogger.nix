{ config, pkgs, lib, ... }:

let
  # Configuration
  repoUrl = "https://github.com/sudhanshunitinatalkar/datalogger-bin.git";
  targetDir = "${config.home.homeDirectory}/datalogger-bin";
  
  # List of all binaries to run as services
  # Added 'configure' and 'data' as requested.
  serviceNames = [ 
    "configure" 
    "cpcb" 
    "data" 
    "datalogger" 
    "display" 
    "network" 
    "saicloud" 
  ];

  # Helper function to define a standard robust service
  mkDataloggerService = name: {
    Unit = {
      Description = "Datalogger Service: ${name}";
      # Start after network and the updater
      After = [ "network-online.target" "datalogger-updater.service" ];
      Wants = [ "network-online.target" ];
    };

    Service = {
      # Points to the mutable binary in the home directory
      ExecStart = "${targetDir}/bin/${name}";
      
      # Robustness settings: Always restart on crash/exit
      Restart = "always";
      RestartSec = "5s";
      StartLimitIntervalSec = "60";
      StartLimitBurst = "5";
      
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
  # 1. THE UPDATER SERVICE (runs git pull)
  systemd.user.services.datalogger-updater = {
    Unit = {
      Description = "Fetch datalogger binaries from Git and update if changed";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Service = {
      Type = "oneshot";
      # Script to handle cloning, updating, and restarting services
      ExecStart = pkgs.writeShellScript "update-datalogger" ''
        export PATH=${lib.makeBinPath [ pkgs.git pkgs.openssh pkgs.systemd ]}:$PATH
        
        TARGET="${targetDir}"
        SERVICES="${lib.concatStringsSep " " serviceNames}"
        
        # Ensure the directory exists
        if [ ! -d "$TARGET/.git" ]; then
          echo "Cloning repository..."
          rm -rf "$TARGET" # Clean up if partial
          git clone ${repoUrl} "$TARGET"
          chmod +x "$TARGET/bin/"*
        else
          cd "$TARGET"
          
          # Fetch changes without merging yet
          git remote update
          
          # Check if local is behind remote
          UPSTREAM='@{u}'
          LOCAL=$(git rev-parse @)
          REMOTE=$(git rev-parse "$UPSTREAM")
          
          if [ "$LOCAL" != "$REMOTE" ]; then
            echo "Updates detected. Pulling changes..."
            git pull
            
            echo "Ensuring binaries are executable..."
            chmod +x bin/*
            
            echo "Restarting application services..."
            # Restart all services to apply the new binaries
            systemctl --user restart $SERVICES
          else
            echo "No updates found. System is up to date."
          fi
        fi
      '';
    };
  };

  # 2. THE TIMER (Triggers the updater every 5 minutes)
  systemd.user.timers.datalogger-updater = {
    Unit = {
      Description = "Run datalogger updater every 5 minutes";
    };
    Timer = {
      OnBootSec = "1m";      # Run 1 min after boot
      OnUnitActiveSec = "5m"; # Run every 5 mins thereafter
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };

  # 3. THE APPLICATION SERVICES
  # We generate a service for every item in the serviceNames list
  systemd.user.services = lib.genAttrs serviceNames mkDataloggerService;
}