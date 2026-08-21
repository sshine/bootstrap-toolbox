{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      # hk-nix's overlay bakes the generated hook config into the hk wrapper as
      # HK_FILE (see hooks.nix); without it hk writes a repo-root hk.pkl.
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [
          inputs.hk-nix.overlays.default
          inputs.helm-vendor.overlays.default
        ];
      };
    };
}
