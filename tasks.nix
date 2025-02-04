{
  fmt.exec = ''
    taplo fmt *.tomil
    nixfmt *.nix --width=100
    biome format . --write
    cargo fmt --all -- --config-path=rustfmt.toml
  '';
  lint.exec = ''
    taplo lint *.toml
    biome lint . --write
    cargo clippy --all-targets --all-features -- -A clippy::pedantic
    deadnix --no-lambda-pattern-names && statix check .
  '';
  spellcheck.exec = ''
    typos
  '';
  precommit.exec = ''
    fmt
    lint
    spellcheck
    build-all
  '';
  build-crane.exec = ''
    nix build .#launcher --accept-flake-config
  '';
  ucode.exec = ''
    nix run .#ucode -- "$@"
  '';
  # options:
  # $WORKSPACE
  build.exec = ''
    cargo build --release "$@"
  '';
  build-all.exec = ''
    cargo build --release --all
  '';
  # options:
  # $WORKSPACE
  dev.exec = ''
    cargo run --package "$@"
  '';
  rustdoc.exec = ''
    cargo rustdoc -- --default-theme='ayu'
  '';
  clean.exec = ''
    rm -rf build
    rm -rf target
  '';
}
