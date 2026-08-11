{ inputs, ... }:
{
  imports = [ inputs.devshell.flakeModule ];

  perSystem =
    {
      config,
      pkgs,
      ...
    }:
    {
      devshells.default = {
        packages = [
          config.treefmt.build.wrapper
          # wrappedPackage (not package): the overlaid hk with HK_FILE baked in,
          # so hk reads its config from the store and writes no repo-root hk.pkl.
          config.hk-nix.wrappedPackage
          pkgs.just
          pkgs.skopeo
        ];

        devshell.motd = "";
        devshell.startup.hk.text = config.hk-nix.shellHook;
      };
    };
}
