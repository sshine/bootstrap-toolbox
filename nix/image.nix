# The bootstrap toolbox: a minimal OCI image published to ghcr.io while the
# on-prem registry is still being stood up. It carries just enough network
# tooling to probe connectivity during cluster bootstrap. Built with dockerTools
# (no KVM step, so it builds in GitHub Actions) and pushed to ghcr with skopeo.
{ ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      # Everything on PATH once exec'd in. cacert + SSL_CERT_FILE below let curl
      # reach TLS endpoints. This is a connectivity-probe toolbox, not a build
      # image — deliberately no nix/nodejs/make; add those only if it grows into
      # building things in-cluster.
      tools = with pkgs; [
        # Network probes — the reason this image exists during bootstrap.
        netcat
        curl
        nmap
        openssh

        # Cluster tooling for poking at the bootstrap from inside a pod.
        kubectl
        kubernetes-helm

        # System programs for a usable pod shell.
        git
        skopeo
        ripgrep
        gnugrep
        gnused
        gawk
        findutils
        coreutils
        bashInteractive

        # Compression / archives.
        gnutar
        gzip
        bzip2
        xz
        zstd

        cacert
      ];

      # Populate /bin from a single merged environment so PATH=/bin is all the
      # image config needs. fakeNss gives root a passwd entry; binSh/usrBinEnv
      # satisfy `#!/bin/sh` and `#!/usr/bin/env` shebangs.
      rootEnv = pkgs.buildEnv {
        name = "bootstrap-toolbox-root-env";
        paths = tools ++ [
          pkgs.dockerTools.fakeNss
          pkgs.dockerTools.binSh
          pkgs.dockerTools.usrBinEnv
        ];
        pathsToLink = [
          "/bin"
          "/etc"
          "/share"
        ];
      };

      image = pkgs.dockerTools.buildImage {
        name = "bootstrap-toolbox";
        tag = "latest";
        copyToRoot = rootEnv;

        # /workspace exists so it is a valid WorkingDir with no volume attached,
        # and is the natural mount point for the persistent PVC (see deploy/).
        extraCommands = ''
          mkdir -p root tmp workspace
          chmod 1777 tmp
        '';

        config = {
          Cmd = [
            "/bin/sleep"
            "infinity"
          ];
          WorkingDir = "/workspace";
          Env = [
            "PATH=/bin"
            "HOME=/root"
            "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
          ];
        };
      };
    in
    {
      packages.image = image;
      packages.default = image;
    };
}
