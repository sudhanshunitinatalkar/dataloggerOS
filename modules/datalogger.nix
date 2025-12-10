{ config, pkgs, lib, ... }:

let
  # --- Configuration ---
  repoUrl = "https://github.com/sudhanshunitinatalkar/datalogger.git";
  repoDir = "${config.home.homeDirectory}/datalogger";
  
  # List of Python scripts to run as services
  # (Maps service name to source file)
  scripts = {
    configure = "src/configure.py";
    cpcb      = "src/cpcb.py";
    data      = "src/data.py";
    datalogger = "src/datalogger.py"; # Main logic
    display   = "src/display.py";
    network   = "src/network.py";
    saicloud  = "src/saicloud.py";
  };

  # Helper function to generate a standard Python service
  mkDataloggerService = name: scriptPath: {
    Unit = {
      Description = "Datalogger Service: ${name}";
      After = [ "network-online.target" "datalogger-repo-sync.service" ];
      Wants = [ "network-online.target" ];
      StartLimitIntervalSec = 0; # Disable rate limiting for infinite retries
    };

    Service = {
      Type = "simple";
      WorkingDirectory = repoDir;
      
      # Use 'nix develop' to run within the Flake's environment defined in the repo
      # We use --command to execute the script using the flake's python environment
      ExecStart = "${pkgs.nix}/bin/nix develop ${repoDir} --command python3 ${scriptPath}";
      
      Restart = "always";
      RestartSec = "5s";
      
      # Environment variables if needed
      Environment = "HOME=${config.home.homeDirectory}";
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };

in
{
  # 1. ensure git is available
  home.packages = [ pkgs.git ];

  # 2. Define the Services
  systemd.user.services = 
    # Generate all python services from the list
    (lib.mapAttrs (name: path: mkDataloggerService name path) scripts) 
    
    # Add the Special Sync Service (Manually defined)
    // {
      datalogger-repo-sync = {
        Unit = {
          Description = "Datalogger Repository Auto-Sync";
          After = [ "network-online.target" ];
          Wants = [ "network-online.target" ];
        };

        Service = {
          Type = "oneshot";
          
          # The Sync Script
          # 1. Clones if missing
          # 2. Fetches updates
          # 3. If updates found -> Pulls & Restarts all python services
          ExecStart = pkgs.writeShellScript "datalogger-sync" ''
            export PATH=${pkgs.git}/bin:${pkgs.systemd}/bin:$PATH
            
            TARGET="${repoDir}"
            REPO="${repoUrl}"
            SERVICES="configure cpcb data datalogger display network saicloud"

            # 1. Ensure Repo Exists
            if [ ! -d "$TARGET/.git" ]; then
              echo "Cloning datalogger repo..."
              mkdir -p "$TARGET"
              git clone "$REPO" "$TARGET"
            fi

            cd "$TARGET"

            # 2. Fetch & Check for Updates
            echo "Checking for updates..."
            git remote update

            LOCAL=$(git rev-parse @)
            REMOTE=$(git rev-parse @{u})

            if [ "$LOCAL" != "$REMOTE" ]; then
              echo "Updates found! Pulling changes..."
              git pull
              
              echo "Restarting Datalogger Services..."
              # Loop through services and restart them
              for svc in $SERVICES; do
                systemctl --user restart "$svc"
              done
              
              echo "Update Complete."
            else
              echo "Repo is up to date."
            fi
          '';
        };
      };
    };

  # 3. Define the Timer (Runs the Sync Service every 5 minutes)
  systemd.user.timers.datalogger-repo-sync = {
    Unit = {
      Description = "Run Datalogger Sync every 5 minutes";
    };
    Timer = {
      OnBootSec = "2m";
      OnUnitActiveSec = "5m";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}