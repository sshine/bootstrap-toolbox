# An OCI image published to ghcr while the on-prem registry is stood up.
# dockerTools.buildImage needs no KVM, so it builds in GitHub Actions.
{ ... }:
{
  perSystem =
    { config, pkgs, ... }:
    let
      tools = with pkgs; [
        # Network probes.
        netcat
        curl
        nmap
        openssh

        # Cluster tooling.
        kubectl
        kubectx
        kubernetes-helm
        helm-vendor
        vault
        jq
        betterleaks

        # Nix itself, for bootstrap builds from inside the cluster. Runs rootless
        # (see NIX_CONFIG below), so it needs no daemon and no nixbld users.
        nix

        # Shell.
        git
        just
        skopeo
        ripgrep
        gnugrep
        gnused
        gawk
        findutils
        coreutils
        bashInteractive
        bash-completion
        atuin
        eza
        neovim
        less
        ncurses

        # Compression.
        gnutar
        gzip
        bzip2
        xz
        zstd

        cacert
      ];

      scripts = pkgs.runCommandLocal "toolbox-scripts" { } ''
        install -Dm555 ${../tools/toolbox-apply} $out/bin/toolbox-apply
        install -Dm555 ${../tools/toolbox-connectivity-test} $out/bin/toolbox-connectivity-test
        install -Dm555 ${../tools/toolbox-gc} $out/bin/toolbox-gc
      '';

      # filter-syscalls is off because fsGroup sets the setgid bit on every
      # directory of the PVC at each mount, the store included, and the filter
      # refuses any chmod that keeps it: a build copying a store directory fails
      # with EPERM. The filter keeps builders from making setuid files that other
      # users could run, and with no build users there are no other users.
      nixConf = ''
        experimental-features = nix-command flakes
        accept-flake-config = true
        build-users-group =
        filter-syscalls = false
        sandbox = false
        sandbox-fallback = false
        auto-optimise-store = true
        keep-outputs = false
        keep-derivations = false
        min-free = 2147483648
        max-free = 5368709120
      '';

      # binSh/usrBinEnv satisfy `#!/bin/sh` and `#!/usr/bin/env` shebangs; NSS
      # files are written in extraCommands rather than pulled from fakeNss.
      rootEnv = pkgs.buildEnv {
        name = "toolbox-root-env";
        paths = tools ++ [
          pkgs.dockerTools.binSh
          pkgs.dockerTools.usrBinEnv
          scripts
          config.packages.bashrc
          config.packages.seed-nix
        ];
        pathsToLink = [
          "/bin"
          "/etc"
          "/share"
          "/usr"
        ];
      };

      image = pkgs.dockerTools.buildImage {
        name = "bootstrap-toolbox";
        tag = "latest";
        copyToRoot = rootEnv;

        # Register the baked closure in /nix/var/nix/db, so once the store is
        # seeded onto the PVC nix treats those paths as valid instead of
        # re-fetching the whole closure from cache.
        includeNixDB = true;

        # /workspace is the WorkingDir and a PVC mount point (see deploy/).
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
          # /bin's symlinks resolve into the store the PVC provides, so the init
          # container has to be able to tell which store this image expects.
          # Written outside /nix, where the PVC mount cannot shadow it.
          printf '%s\n' ${rootEnv} > .nix-store-stamp
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
            "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
            "NIX_CONFIG=${nixConf}"
          ];
        };
      };
    in
    {
      packages.image = image;
      packages.default = image;
    };
}
