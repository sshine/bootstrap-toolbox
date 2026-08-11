# bootstrap-toolbox

A minimal OCI image published to `ghcr.io/sshine/bootstrap-toolbox` while the
on-prem registry for the [k8s-infra](../k8s-infra) cluster is being stood up. It
carries just enough network tooling — `netcat`, `curl`, `nmap` — to probe
connectivity from inside the cluster during bootstrap.

The flake is [dendritic](https://flake.parts): every `.nix` file under `nix/` is
a flake-parts module, imported by `import-tree`.

## Build locally

```sh
nix build .#image -o target/image.tar.gz   # or: just image
```

The result is a docker-archive tarball. Load it with `docker load < target/image.tar.gz`
or push it with skopeo.

## Push

CI (`.github/workflows/build-image.yml`) builds and pushes on every push to
`main`, tagging the short commit SHA plus `latest`. `GITHUB_TOKEN` provides the
`packages:write` scope, so no extra secret is required.

To push by hand:

```sh
SKOPEO_DEST_CREDS="<user>:<token>" just push latest
```

## Deploy

`deploy/` is a kustomize bundle: a single-replica Deployment plus a
`ReadWriteOnce` PVC mounted at `/workspace` (the image's working directory).

A pod's root filesystem is writable but ephemeral — anything outside `/workspace`
is lost when the pod restarts or reschedules. Keep persistent work in `/workspace`.

```sh
kubectl apply -k deploy
kubectl exec -it deploy/bootstrap-toolbox -- bash
```

Two things are parameterized in `deploy/kustomization.yaml`:

- **Image** — defaults to `ghcr.io/sshine/bootstrap-toolbox:latest`. Edit the
  `images:` block, or `kustomize edit set image ghcr.io/sshine/bootstrap-toolbox=<ref>`.
- **PVC size** — defaults to `1Gi`. Uncomment the `patches:` block and set the value.

## Contents

Network probes (`netcat`, `curl`, `nmap`, `openssh`), cluster tooling
(`kubectl`, `helm`, `skopeo`), `nix` itself, plus `git`, `ripgrep`, standard
shell utilities, compression tools, and CA certificates. Add tools in
`nix/image.nix`.

`nix` runs rootless (no daemon, no `nixbld` users, no sandbox — none are
available to a restricted-PSA pod). The baked `/nix/store` is root-owned and
read-only, so `NIX_CONFIG` sets `store = /workspace/nix`: a chroot store on the
PVC whose logical paths are still `/nix/store`, so `cache.nixos.org` substitution
works and realised paths survive pod restarts. `nix run nixpkgs#<pkg>` and
`nix build` work out of the box as UID 1000.

`nix/bashrc.bash` is installed as `/etc/bashrc`, so an interactive shell comes
with a prompt showing the kubectl context, bash completion (including for `k`),
git aliases, and a history that survives pod restarts because `$HOME` is the
PVC. Completions are read from `/share/bash-completion` — the image has no
`/usr/share`.
