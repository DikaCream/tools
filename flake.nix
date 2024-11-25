{
  description = "Union Labs Development Tools";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";

    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    crane = {
      url = "github:ipetkov/crane";
      inputs = {
        flake-utils.follows = "flake-utils";
        nixpkgs.follows = "nixpkgs";
      };
    };

    flake-parts.url = "github:hercules-ci/flake-parts";

    flake-utils.url = "github:numtide/flake-utils";

    advisory-db.url = "github:rustsec/advisory-db";
    advisory-db.flake = false;
  };

  outputs =
    {
      self,
      crane,
      fenix,
      devenv,
      nixpkgs,
      flake-utils,
      advisory-db,
      rust-overlay,
      ...
    }@inputs:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        inherit (pkgs) lib;
        /**
          crane setup start
          this follows crane's official "workspace" guide
          https://crane.dev/examples/quick-start-workspace.html
        */
        craneLib = (crane.mkLib pkgs).overrideToolchain fenix.packages.${system}.minimal.toolchain;

        src = craneLib.cleanCargoSource ./.;

        # Common arguments can be set here to avoid repeating them later
        commonArgs = {
          inherit src;
          strictDeps = true;

          buildInputs =
            [
              # Add additional build inputs here
            ]
            ++ lib.optionals pkgs.stdenv.isDarwin [
              # Additional darwin specific inputs can be set here
              pkgs.libiconv
            ];

          # Additional environment variables can be set directly
          # MY_CUSTOM_VAR = "some value";
        };

        # in order to use rust nightly, we use fenix to override the toolchain
        # https://github.com/nix-community/fenix#examples
        craneLibLLvmTools = craneLib.overrideToolchain (
          fenix.packages.${system}.complete.withComponents [
            "cargo"
            "llvm-tools"
            "rustc"
          ]
        );

        cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        individualCrateArgs = commonArgs // {
          inherit cargoArtifacts;
          inherit (craneLib.crateNameFromCargoToml { inherit src; }) version;
          # NB: we disable tests since we'll run them all via cargo-nextest
          doCheck = false;
        };

        fileSetForCrate =
          crate:
          lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              ./Cargo.toml
              ./Cargo.lock
              (craneLib.fileset.commonCargoSources crate)
            ];
          };

        # Build the top-level crates of the workspace as individual derivations.
        # This allows consumers to only depend on (and build) only what they need.
        # Though it is possible to build the entire workspace as a single derivation,
        # so this is left up to you on how to organize things
        #
        # Note that the cargo workspace must define `workspace.members` using wildcards,
        # otherwise, omitting a crate (like we do below) will result in errors since
        # cargo won't be able to find the sources for all members.
        launcher = craneLib.buildPackage (
          individualCrateArgs
          // {
            pname = (lib.importTOML ./launcher/Cargo.toml).package.name;
            cargoExtraArgs = "--workspace";
            src = fileSetForCrate ./launcher;
          }
        );
      in
      {
        checks = {
          # Build the crates as part of `nix flake check` for convenience
          inherit launcher;
          my-workspace-clippy = craneLib.cargoClippy (
            commonArgs
            // {
              inherit cargoArtifacts;
              cargoClippyExtraArgs = "--all-targets -- --deny warnings";
            }
          );

          my-workspace-doc = craneLib.cargoDoc (
            commonArgs
            // {
              inherit cargoArtifacts;
            }
          );

          my-workspace-fmt = craneLib.cargoFmt {
            inherit src;
          };

          my-workspace-toml-fmt = craneLib.taploFmt {
            src = pkgs.lib.sources.sourceFilesBySuffices src [ ".toml" ];
            # taplo arguments can be further customized below as needed
            # taploExtraArgs = "--config ./taplo.toml";
          };

          # TODO: add cargo-hakari and cargo-nextest
        };

        packages =
          {
            inherit launcher;
          }
          // lib.optionalAttrs (!pkgs.stdenv.isDarwin) {
            my-workspace-llvm-coverage = craneLibLLvmTools.cargoLlvmCov (
              commonArgs
              // {
                inherit cargoArtifacts;
              }
            );
          };
        apps = {
          launcher = flake-utils.lib.mkApp {
            drv = launcher;
          };
        };

        ucode = pkgs.writeShellApplication {
          name = "ucode";
          runtimeInputs = [ pkgs.openvscode-server ];
          text = ''
            openvscode-server --update-extensions --disable-telemetry --disable-telemetry --accept-server-license-terms --start-server "$@"
          '';
        };
        devenv-test = self.devShells.${system}.default.config.test;
        devenv-up = self.devShells.${system}.default.config.procfileScript;
        devShells.default = devenv.lib.mkShell {
          inherit inputs pkgs;
          modules = [
            (import ./devenv-shell.nix)
          ];
        };
      }
    )
    // {
      # any system-independent outputs should go here, if needed
    };

  nixConfig = {
    extra-substituters = "https://devenv.cachix.org";
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
  };
}
