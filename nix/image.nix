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
        helm-vendor

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

      # binSh/usrBinEnv satisfy `#!/bin/sh` and `#!/usr/bin/env` shebangs; NSS
      # files are written in extraCommands rather than pulled from fakeNss.
      rootEnv = pkgs.buildEnv {
        name = "bootstrap-toolbox-root-env";
        paths = tools ++ [
          pkgs.dockerTools.binSh
          pkgs.dockerTools.usrBinEnv
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
            # Rootless nix under the restricted PSA: no daemon, no nixbld users,
            # and no sandbox — RuntimeDefault seccomp denies CLONE_NEWUSER, so the
            # namespaces a sandboxed build needs cannot be created.
            #
            # The store must stay at its real location. A store elsewhere (`store
            # = /workspace/nix`) is a *diverted* store, and nix forces a chroot for
            # those regardless of `sandbox`, to map the real directory onto
            # /nix/store. That chroot cannot be created here, and sandbox-fallback
            # then drops it silently: the builder runs against the image's baked
            # /nix/store instead, which holds the runtime closure but none of the
            # build-only inputs. So sandbox-fallback is off — a diverted store
            # reintroduced later fails loudly rather than a build input away.
            #
            # /nix is therefore a PVC seeded from the baked store by the init
            # container (see deploy/), which also makes realised paths survive
            # restarts. min-free/max-free let nix auto-GC once the PVC runs low.
            "NIX_CONFIG=experimental-features = nix-command flakes\naccept-flake-config = true\nbuild-users-group = \nsandbox = false\nsandbox-fallback = false\nauto-optimise-store = true\nmin-free = 2147483648\nmax-free = 5368709120"
          ];
        };
      };
    in
    {
      packages.image = image;
      packages.default = image;
    };
}
