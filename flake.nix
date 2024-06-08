{
  description = "Hello World in .NET";
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pname = "dotnet-blazor-webassembly";
        projectFile = "./BlazorSample.csproj";
        version = "0.0.1";

        pkgs = import nixpkgs {inherit system;};
        dotnet-runtime = pkgs.dotnetCorePackages.aspnetcore_8_0;
        dotnet-sdk =
          (with pkgs.dotnetCorePackages;
            combinePackages [
              sdk_8_0
            ])
          .overrideAttrs (finalAttrs: previousAttrs: {
            # This is needed to install workload in $HOME
            # https://discourse.nixos.org/t/dotnet-maui-workload/20370/2

            postBuild =
              (previousAttrs.postBuild or '''')
              + ''
                 for i in $out/sdk/*
                 do
                   i=$(basename $i)
                   length=$(printf "%s" "$i" | wc -c)
                   substring=$(printf "%s" "$i" | cut -c 1-$(expr $length - 2))
                   i="$substring""00"
                   mkdir -p $out/metadata/workloads/''${i/-*}
                   touch $out/metadata/workloads/''${i/-*}/userlocal
                done
              '';
            preInstall = ''
              if [ ! -w "$HOME" ]; then
                export HOME=$(mktemp -d) # Dotnet expects a writable home directory for its configuration files
              fi
              $out/dotnet workload install wasm-tools
            '';
          });

        # dotnet tools installer utility method
        dotnetEightTool = toolName: toolVersion: sha256:
          pkgs.stdenvNoCC.mkDerivation rec {
            name = toolName;
            version = toolVersion;
            nativeBuildInputs = [pkgs.makeWrapper];
            src = pkgs.fetchNuGet {
              pname = name;
              version = version;
              sha256 = sha256;
              installPhase = ''mkdir -p $out/bin && cp -r tools/net8.0/any/* $out/bin'';
            };
            installPhase = ''
              runHook preInstall
              mkdir -p "$out/lib"
              cp -r ./bin/* "$out/lib"
              makeWrapper "${dotnet-runtime}/bin/dotnet" "$out/bin/${name}" --add-flags "$out/lib/${name}.dll"
              runHook postInstall
            '';
          };
        nuget-to-nix = pkgs.nuget-to-nix.override {inherit dotnet-sdk;};
        binPkgs = [
          pkgs.coreutils
          dotnet-sdk
          nuget-to-nix
          pkgs.jq
          pkgs.yq
          pkgs.curl
          pkgs.gnugrep
          pkgs.gawk
        ];
        shellPkgs =
          binPkgs
          ++ [
            pkgs.git
            pkgs.alejandra
            pkgs.nodePackages.markdown-link-check
          ];
      in {
        packages = {
          # To install dotnet tools
          # fantomas = dotnetEightTool "fantomas" "5.1.5" "sha256-qzIs6JiZV9uHUS0asrgWLAbaKJsNtr5h01fJxmOR2Mc=";
          fetchDeps = let
            flags = [];
            runtimeIds =
              map (system: pkgs.dotnetCorePackages.systemToDotnetRid system) dotnet-sdk.meta.platforms;
          in
            pkgs.writeShellScriptBin "fetch-${pname}-deps" (builtins.readFile (pkgs.substituteAll {
              src = ./nix/fetchDeps.sh;
              pname = pname;
              binPath = pkgs.lib.makeBinPath binPkgs;
              projectFiles = toString (pkgs.lib.toList projectFile);
              rids = pkgs.lib.concatStringsSep "\" \"" (runtimeIds ++ ["browser-wasm"]);
              packages = dotnet-sdk.packages;
              storeSrc = pkgs.srcOnly {
                src = ./.;
                pname = pname;
                version = version;
              };
              n2n = "${nuget-to-nix}/bin/nuget-to-nix";
            }));
          default = pkgs.buildDotnetModule {
            pname = "BlazorSample";
            version = version;
            src = ./.;
            projectFile = projectFile;
            nugetDeps = ./nix/deps.nix;
            doCheck = true;
            dotnet-sdk = dotnet-sdk;
            dotnet-runtime = dotnet-runtime;
            buildPhase = ''
              runHook preBuild

              ${dotnet-sdk}/bin/dotnet build ${projectFile} \
                -maxcpucount:$NIX_BUILD_CORES \
                -p:BuildInParallel="true" \
                -p:ContinuousIntegrationBuild=true \
                -p:Deterministic=true \
                --configuration Release \
                --no-restore \
                "/p:Platform=Any CPU" \
                /p:Version=${version}

              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall

              ${dotnet-sdk}/bin/dotnet publish ${projectFile} \
                -p:ContinuousIntegrationBuild=true \
                -p:Deterministic=true \
                --configuration Release \
                "/p:Platform=Any CPU" \
                /p:Version=${version} \
                --output $out/lib/$pname \
                --no-build

              runHook postInstall
            '';
          };
        };
        devShells = {
          default = pkgs.mkShell {
            buildInputs = shellPkgs;
          };
        };
      }
    );
}
