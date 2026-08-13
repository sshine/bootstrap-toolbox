# The init container's entrypoint, kept in a .bash file so it is a shell script
# rather than a Nix string. Exposed as a package so `nix build .#seed-nix` shows
# what image.nix drops into the image's /bin.
{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.seed-nix = pkgs.runCommandLocal "bootstrap-toolbox-seed-nix" { } ''
        install -Dm555 ${./seed-nix.bash} $out/bin/seed-nix
      '';
    };
}
