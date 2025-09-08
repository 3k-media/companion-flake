{
  description = "CasparCG Server";
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (top@{ config, withSystem, moduleWithSystem, ... }: {
      imports = [
        flake-parts.flakeModules.easyOverlay
      ];
      systems = ["x86_64-linux" "aarch64 "];
      perSystem = { system, config, pkgs, lib, ... }:
      {
        overlayAttrs = {
            inherit (config.packages) companion;
        };
        packages.default = config.packages.companion;
        packages.companion = pkgs.stdenv.mkDerivation (finalAttrs:
          let
            patched_node_modules = pkgs.stdenv.mkDerivation {
              inherit (finalAttrs) version src patches;
              pname = "companion-node-modules";
              installPhase = ''
                runHook preInstall
                mkdir -p $out
                cp -r node_modules companion shared-lib webui $out
                echo "${finalAttrs.version}" > $out/BUILD
                echo > $out/SENTRY
                runHook postInstall
              '';

              nativeBuildInputs = with pkgs; [
                gitMinimal
                python3
                yarn-berry_4
                yarn-berry_4.yarnBerryConfigHook
                autoPatchelfHook
              ];

              autoPatchelfIgnoreMissingDeps = [ "*" ];

              buildInputs = with pkgs; [
                systemdLibs
                libusb1
              ];

              missingHashes = ./missing-hashes.json;
              offlineCache = pkgs.yarn-berry_4.fetchYarnBerryDeps {
                inherit (finalAttrs) src patches;
                missingHashes = ./missing-hashes.json;
                hash = "sha256-gvZYdZbk/aUli+1Fn1Axsj0bCIyMh5l7TPFdGttpxSc=";
              };
            };
          in
          {
          pname = "companion";
          version = "4.0.3";
          src = pkgs.fetchFromGitHub {
            owner = "bitfocus";
            repo = "companion";
            rev = "v${finalAttrs.version}";
            hash = "sha256-qe5PfiPgRuvua7FqM7rvmmPruHxbpHCR3iJ+NeXfr5Q=";
          };

          patches = [
            ./workspace.patch
          ];

          nativeBuildInputs = with pkgs; [
            rsync
            makeBinaryWrapper
            yarn-berry_4
            gitMinimal
            zip
          ];

          buildInputs = with pkgs; [
            python3
            sqlite
            systemdLibs
            libusb1
          ];

          configurePhase = ''
            runHook preConfigure
            cp -r ${patched_node_modules}/{node_modules,SENTRY,BUILD} .
            runHook postConfigure
          '';

          buildPhase = ''
            runHook preBuild
            yarn workspace @companion-app/shared build:ts
            yarn workspace companion build
            yarn workspace @companion-app/webui build

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out/share/companion/dist
            cp nodejs-versions.json BUILD SENTRY package.json $out/share/companion
            pushd webui/build && zip -r $out/share/companion/webui.zip ./ && popd
            pushd docs && zip -r $out/share/companion/docs.zip ./ && popd
            cp -r companion/dist $out/share/companion/dist/companion
            cp -r shared-lib/dist $out/share/companion/dist/shared-lib

            cp package.json $out/share/companion/dist
            rsync -av node_modules $out/share/companion/dist --exclude @companion-app/webui --exclude companion
            makeWrapper ${pkgs.nodejs}/bin/node $out/bin/companion \
              --add-flags $out/share/companion/dist/companion/main.js \
              --set NODE_ENV production \
              --set NODE_PATH  $out/share/companion/dist/node_modules
            runHook postInstall
          '';
        });
      };
    });
}
