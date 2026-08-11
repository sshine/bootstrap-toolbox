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

# Run every flake check
check:
    nix flake check -L
