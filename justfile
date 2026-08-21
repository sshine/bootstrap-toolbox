devops_root := justfile_directory()

# Show available just commands
_list:
    @just --list --unsorted

# Format all code
fmt:
    treefmt

# Check formatting
fmt-check:
    treefmt --fail-on-change --no-cache

# Build the image (docker-archive tarball) into target/image.tar.gz
image:
    @mkdir -p target
    nix build .#image -o target/image.tar.gz

# Push the image to ghcr (SKOPEO_DEST_CREDS="user:token"); default tag latest
push tag='latest': image
    nix run nixpkgs#skopeo -- copy \
        ${SKOPEO_DEST_CREDS:+--dest-creds "$SKOPEO_DEST_CREDS"} \
        docker-archive:target/image.tar.gz \
        docker://ghcr.io/sshine/bootstrap-toolbox:{{tag}}

# Render deploy/ to target/deploy.yaml; an overlay pins <tag>, leaving deploy/ alone
service-build tag='latest':
    @mkdir -p target/overlay
    @printf '%s\n' \
        'apiVersion: kustomize.config.k8s.io/v1beta1' \
        'kind: Kustomization' \
        'resources:' \
        '  - ../../deploy' \
        'images:' \
        '  - name: ghcr.io/sshine/bootstrap-toolbox' \
        '    newTag: {{tag}}' > target/overlay/kustomization.yaml
    kubectl kustomize target/overlay > target/deploy.yaml

# Apply the toolbox at <tag>; server-side, so field ownership stays with us
service-deploy tag='latest': (service-build tag)
    kubectl apply --server-side --force-conflicts \
        --field-manager=bootstrap-toolbox -f target/deploy.yaml

# Run every flake check
check:
    nix flake check -L
