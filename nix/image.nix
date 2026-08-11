# A minimal OCI image published to ghcr while the on-prem registry is stood up.
# dockerTools.buildImage needs no KVM, so it builds in GitHub Actions.
{ ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      tools = with pkgs; [
        # Network probes.
        netcat
        curl
        nmap
        openssh

        # Cluster tooling.
        kubectl
        kubernetes-helm

        # Shell.
        git
        skopeo
        ripgrep
        gnugrep
        gnused
        gawk
        findutils
        coreutils
        bashInteractive

        # Compression.
        gnutar
        gzip
        bzip2
        xz
        zstd

        cacert
      ];

      # binSh/usrBinEnv satisfy `#!/bin/sh` and `#!/usr/bin/env` shebangs; NSS
      # files are written in extraCommands rather than pulled from fakeNss.
      rootEnv = pkgs.buildEnv {
        name = "bootstrap-toolbox-root-env";
        paths = tools ++ [
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

        # /workspace is the WorkingDir and the PVC mount point (see deploy/).
        # NSS files must be regular files, not fakeNss's store symlinks, or
        # containerd's create-time user lookup rejects them; toolbox=1000 matches
        # the uid deploy/ runs as. /etc arrives read-only, so make it writable.
        extraCommands = ''
          mkdir -p root tmp workspace etc
          chmod 1777 tmp
          chmod u+w etc
          printf '%s\n' \
            'root:x:0:0:root:/root:/bin/sh' \
            'toolbox:x:1000:1000:toolbox:/workspace:/bin/sh' \
            'nobody:x:65534:65534:nobody:/:/bin/sh' > etc/passwd
          printf '%s\n' \
            'root:x:0:' \
            'toolbox:x:1000:' \
            'nogroup:x:65534:' > etc/group
          printf 'hosts: files dns\n' > etc/nsswitch.conf
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
