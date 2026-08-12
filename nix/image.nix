# A minimal OCI image published to ghcr while the on-prem registry is stood up.
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
        kubernetes-helm

        # Nix itself, for bootstrap builds from inside the cluster. Runs rootless
        # (see NIX_CONFIG below), so it needs no daemon and no nixbld users.
        nix

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
        bash-completion
        less

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
          config.packages.bashrc
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

        # Register the baked closure in /nix/var/nix/db so the read-only root
        # store below is a usable substituter — without it nix treats the store
        # as empty and re-fetches everything from cache.
        includeNixDB = true;

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
            "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
            # Rootless nix under the restricted PSA: no daemon, no nixbld users,
            # and no user-namespace sandbox (unavailable to an unprivileged pod).
            # The baked /nix/store is root-owned and read-only, so realise into a
            # chroot store on the writable PVC — logical paths stay /nix/store, so
            # cache.nixos.org substitution still works, and it persists restarts.
            # The baked store is listed first as a read-only substituter (needs
            # the read-only-local-store feature), so its paths are copied locally
            # instead of re-downloaded; cache.nixos.org covers everything else.
            # require-sigs is off because includeNixDB registers the baked closure
            # without signatures, so a signed import from the local store is
            # impossible; the baked store is first-party and cache.nixos.org is
            # reached over TLS, so the residual exposure is acceptable here.
            "NIX_CONFIG=experimental-features = nix-command flakes read-only-local-store\naccept-flake-config = true\nbuild-users-group = \nsandbox = false\nrequire-sigs = false\nstore = /workspace/nix\nsubstituters = local?read-only=true https://cache.nixos.org"
          ];
        };
      };
    in
    {
      packages.image = image;
      packages.default = image;
    };
}
