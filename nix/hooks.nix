# Git hooks via hk-nix. The generated config is baked into the hk wrapper as
# HK_FILE (via hk-nix's overlay, see pkgs.nix); no hk.pkl is written to the repo.
{ inputs, ... }:
{
  imports = [ inputs.hk-nix.flakeModules.default ];

  perSystem =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      # Reference tools by absolute store path: the `nix flake check` hk-check
      # sandbox runs hooks without the devshell PATH, so a bare name is not found.
      treefmt = lib.getExe config.treefmt.build.wrapper;
      deadnix = lib.getExe pkgs.deadnix;
      shellcheck = lib.getExe pkgs.shellcheck;
    in
    {
      hk-nix.settings.hooks = {
        "pre-commit" = {
          fix = true;
          stash = "git";
          steps.treefmt = {
            check = "${treefmt} --fail-on-change --no-cache {{files}}";
            fix = "${treefmt} {{files}}";
          };
        };

        "pre-push".steps = {
          deadnix = {
            glob = "*.nix";
            check = "${deadnix} --fail {{files}}";
          };

          # treefmt runs shfmt; shellcheck is the linting half of the same story.
          shellcheck = {
            glob = [
              "*.bash"
              "*.sh"
            ];
            check = "${shellcheck} {{files}}";
          };
        };

        "commit-msg".steps.conventional.builtin = config.hk-nix.builtins.check_conventional_commit;
      };
    };
}
