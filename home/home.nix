{ config, pkgs, ... }:

let
  # 1. Define your custom Python environment here
  datalogger = pkgs.python312.withPackages (ps: [
    # List all python packages you need
    ps.requests
    ps.paho-mqtt
    ps.pymodbus
  ]);
in
{
  # 2. Add your other packages...
  home.packages = with pkgs; [
    htop
    curl
    wget
    git
    vim
    util-linux
    gptfdisk
    fastfetch
    sops
    cloudflared

    # 3. ...and add your *single* custom Python environment
    datalogger
  ];

  # Let Home Manager manage itself
  programs.home-manager.enable = true;
}