{
  description = "RPi Home Manager Config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = 
    {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = 
  { self, nixpkgs, home-manager, ... }@inputs:
    let
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      
      # Define the username in one place
      username = "datalogger";
    in
    {
      # Use the username variable as the attribute key for the configuration
      homeConfigurations.${username} = home-manager.lib.homeManagerConfiguration 
      {
        inherit pkgs;
        
        extraSpecialArgs = { inherit inputs; };

        modules = 
        [
          ./home/home.nix
          {
            home = 
            {
              # Use the username variable for the mandatory option
              # This 'inherit' is shorthand for 'username = username;'
              inherit username; 
              
              stateVersion = "25.05"; 
            };

            programs.home-manager.enable = true;
          }
        ];
      };
    };
}