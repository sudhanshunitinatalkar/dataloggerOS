{ config, pkgs, ... }:

{
  news.display = "silent";
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
  ];

  # Let Home Manager manage itself
  programs.home-manager.enable = true;
}