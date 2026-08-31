{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      # hk-nix's overlay bakes the generated hook config into the hk wrapper as
      # HK_FILE (see hooks.nix); without it hk writes a repo-root hk.pkl.
      #
      # helm-vendor comes from its published release, not from its overlay, which
      # builds from source. The release is a statically linked musl binary, so a
      # rust toolchain and a derivation per crate stay out of every closure here.
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [
          inputs.hk-nix.overlays.default
          (_final: _prev: {
            helm-vendor = inputs.helm-vendor.packages.${system}.helm-vendor-bin;
          })
        ];
        config.allowUnfreePredicate = pkg: builtins.elem (inputs.nixpkgs.lib.getName pkg) [ "vault" ];
      };
    };
}
