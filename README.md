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

A pod's root filesystem is writable but ephemeral — anything outside `/nix` and
`/workspace` is lost when the pod restarts or reschedules. Keep persistent work
in `/workspace`.

```sh
just service-deploy                 # or: just service-deploy <tag>
kubectl exec -it deploy/bootstrap-toolbox -- bash
```

`service-deploy` pins the image tag through a generated overlay and server-side
applies the result, so the tag you just pushed does not have to be committed
first. `kubectl apply -k deploy` deploys whatever tag `deploy/` names.

Two things are parameterized in `deploy/kustomization.yaml`:

- **Image** — defaults to `ghcr.io/sshine/bootstrap-toolbox:latest`. Edit the
  `images:` block, or `kustomize edit set image ghcr.io/sshine/bootstrap-toolbox=<ref>`.
- **PVC size** — defaults to `20Gi`. Uncomment the `patches:` block and set the value.

## Contents

Network probes (`netcat`, `curl`, `nmap`, `openssh`), cluster tooling
(`kubectl`, `helm`, `helm-vendor`, `skopeo`), `nix` itself, plus `git`,
`ripgrep`, `eza`, `atuin`, standard shell utilities, compression tools, and CA
certificates. Add tools in `nix/image.nix`.

`helm-vendor` is not in nixpkgs; its flake carries an overlay, applied in
`nix/pkgs.nix`, which is why `nix/image.nix` can list it like any other package.

The baked store also stands in for the binary cache helm-vendor has nowhere to
publish to. A pod that clones [k8s-infra](../k8s-infra) and enters its devshell
asks for the same store path this image already carries, so nothing compiles
Rust in-cluster — but only while both flakes resolve helm-vendor's own inputs
identically. Both pin it with the same `follows`; drop one and the path diverges
and the pod builds a whole Rust toolchain to get a binary it already has.

`nix` runs rootless (no daemon, no `nixbld` users, no sandbox — a restricted-PSA
pod cannot create the namespaces one needs, since `RuntimeDefault` seccomp denies
`CLONE_NEWUSER`). `nix run nixpkgs#<pkg>` and `nix build` work as UID 1000.

The store keeps its real location at `/nix`, mounted from the PVC, and the
`seed-nix` init container copies the image's baked store onto it — that copy is
why the first start is slow; later starts skip it and reuse everything already
built. The baked closure is registered in the image's Nix DB (`includeNixDB`),
so after seeding those paths are valid rather than re-fetched.

Changing the image re-seeds, since `/bin`'s symlinks come from the image layer
while their targets come from the PVC. Store paths already there are kept, so
the copy is incremental; the Nix DB is replaced, which costs a rebuild of
whatever was built in-pod before the bump.

The store cannot simply be pointed elsewhere. Any `store = <path>` outside
`/nix` is a *diverted* store, and nix forces a chroot for those regardless of
the `sandbox` setting, to map the real directory onto `/nix/store`. This pod
cannot create that chroot, and `sandbox-fallback` (on by default) then drops it
silently, leaving builds to run against whatever `/nix/store` the container
happens to have — which fails on the first build-only input with a bare
`No such file or directory`. Hence `sandbox-fallback = false`, so the same
mistake fails loudly next time.

Two `subPath`s of the one RWO PVC back `/nix` and `/workspace`. `min-free`/
`max-free` auto-GC the store once the PVC runs low.

`nix/bashrc.bash` is installed as `/etc/bashrc`, so an interactive shell comes
with a prompt showing the kubectl context, bash completion (including for `k`),
git aliases, and a history that survives pod restarts because `$HOME` is the
PVC. Completions are read from `/share/bash-completion` — the image has no
`/usr/share`.

Colour is on where the terminal admits to it. `kubectl exec` forwards the
client's `TERM` verbatim, and a bare `xterm` is upgraded to `xterm-256color`
when ncurses' terminfo has the entry; `dircolors` then supplies the palette
`eza` and `ls` share, and the empty `LS_COLORS` it yields for a terminal it
doesn't recognise is what leaves the prompt uncoloured too. `^R` searches
everything atuin has recorded, across sessions and pods, while up-arrow stays
bash's own history.
