{ config, pkgs, lib, ... }:

let
  version = "0.0.1";

  # 1. Package Definition
  # Downloads the release zip and patches the binaries to run on NixOS
  dataloggerBin = pkgs.stdenv.mkDerivation {
    pname = "datalogger-services";
    inherit version;

    src = pkgs.fetchzip {
      url = "https://github.com/sudhanshunitinatalkar/datalog-bin/releases/download/v${version}/release.zip";
      
      # [ACTION REQUIRED] PASTE YOUR HASH BELOW
      sha256 = "16xifrxdxan4sf558s22d5ki96440xvn9q6xwh7ci3yyan18qbl7";
      
      stripRoot = false;
    };

    # Tools to fix binary compatibility
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];

    # Runtime libraries required by the binaries
    buildInputs = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      openssl
    ];

    installPhase = ''
      mkdir -p $out/bin
      # Move binaries from the nested zip folder to /bin
      cp -r release/datalogger-${version}/* $out/bin/
      chmod +x $out/bin/*
    '';
  };

  # 2. Service Logic
  # We list the binaries we want to run (ignoring 'diag' as requested)
  binaryNames = [ 
    "configure" 
    "cpcb" 
    "data" 
    "datalogger" 
    "display" 
    "network" 
    "saicloud" 
  ];

  # Helper function to create a systemd service for each binary
  mkService = name: {
    name = "datalogger-${name}";
    value = {
      description = "Datalogger Service: ${name}";
      wantedBy = [ "multi-user.target" ]; # Start on boot
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      
      serviceConfig = {
        ExecStart = "${dataloggerBin}/bin/${name}";
        
        # Auto-restart logic
        Restart = "always";
        RestartSec = "5s";
        
        # Run as root
        User = "root";

        # [FIX] Move temp files to Home Directory instead of RAM/System Tmp
        Environment = "TMPDIR=/root/datalogger_tmp";
      };

      # Ensure the custom temp directory exists before starting
      preStart = "mkdir -p /root/datalogger_tmp";
    };
  };

in
{
  # [FIX] Critical for Pi Zero 2: Use SD Card for /tmp instead of RAM
  # This prevents "No space left on device" errors during builds/downloads.
  boot.tmp.useTmpfs = false;

  # Generate the services
  systemd.services = builtins.listToAttrs (map mkService binaryNames);
}