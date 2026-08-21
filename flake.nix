{
  description = "Minimal bootstrap toolbox image published to ghcr.io";

  inputs = {
    nixpkgs.url = "https://nixos.org/channels/nixpkgs-unstable/nixexprs.tar.xz";

    flake-parts.url = "github:hercules-ci/flake-parts";

    import-tree.url = "github:vic/import-tree";

    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    helm-vendor = {
      url = "git+https://git.shine.town/infra/helm-vendor";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.import-tree.follows = "import-tree";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.devshell.follows = "devshell";
    };

    hk-nix = {
      url = "github:nix-tools/hk-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.import-tree.follows = "import-tree";
    };
  };

  outputs =
    { flake-parts, import-tree, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } (import-tree ./nix);
}
