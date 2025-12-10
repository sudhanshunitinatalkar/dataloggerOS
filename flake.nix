{
  description = "RPi Home Manager Config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
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
      
      username = "datalog";
    in
    {
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
              inherit username; 
              # Explicitly set the home directory to resolve the error.
              homeDirectory = "/home/${username}";
              stateVersion = "25.05"; 
            };

            programs.home-manager.enable = true;
          }
        ];
      };
    };
}
