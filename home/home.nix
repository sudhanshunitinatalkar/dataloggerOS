{ config, pkgs, ... }:

{
  # Essential Packages for an IoT Device
  home.packages = with pkgs; 
  [
    # System Utilities
    htop      # Interactive process viewer
    ripgrep   # Fast grep alternative
    fd        # Simple find alternative
    jq        # JSON processor (great for API debugging)
    curl      # Data transfer tool
    wget      # File retrieval

    # Development/Debugging
    git       # Version control
    python3   # Python runtime
  ];

  # Let Home Manager manage itself
  programs.home-manager.enable = true;

}