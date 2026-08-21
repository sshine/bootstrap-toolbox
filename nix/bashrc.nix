# The interactive shell setup: prompt, completion and aliases, kept in .bash
# files so they are shell scripts rather than Nix strings. Exposed as a package
# so `nix build .#bashrc` shows what image.nix drops into the image's /etc.
{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.bashrc = pkgs.runCommandLocal "toolbox-bashrc" { } ''
        install -Dm444 ${./bashrc.bash} $out/etc/bashrc
        install -Dm444 ${./profile.bash} $out/etc/profile
      '';
    };
}
