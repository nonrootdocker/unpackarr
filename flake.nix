{
  description = "minimalbase-ng + bazarr service";

  inputs = {
    nixpkgs.follows = "minimalbase/nixpkgs";
    minimalbase.url = "github:nonrootdocker/minimalbase-ng";
    bazarr-src = {
      url = "github:morpheusaso/bazarr";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, minimalbase, bazarr-src }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
      };
    };

    # ----------------------------
    # Bazarr Python environment
    # ----------------------------
    bazarrPython = pkgs.python3.withPackages (ps: [
      ps.gevent
      ps.gevent-websocket
      ps.cryptography
      ps.pyopenssl
      ps.lxml
      ps.psutil
      ps.numpy
      ps.pillow
      ps.pysubs2
      ps.webrtcvad
      ps.requests
      ps.apscheduler
      ps.beautifulsoup4
      ps.setuptools
    ]);

    bazarr = pkgs.stdenv.mkDerivation {
      pname = "bazarr";
      version = "latest";
      src = bazarr-src;

      buildInputs = [ bazarrPython ];

      installPhase = ''
        mkdir -p $out/app/bazarr
        cp -r . $out/app/bazarr
      '';
    };

    # ----------------------------
    # User database configuration (/etc/passwd)
    # ----------------------------
    passwdFile = pkgs.writeTextDir "etc/passwd" ''
      root:x:0:0:root:/root:/bin/sh
      bazarr:x:1000:1000:bazarr:/data:/bin/sh
    '';

    # ----------------------------
    # ABI generator (Points directly to Nix Store)
    # ----------------------------
    bazAbi = pkgs.writeTextFile {
      name = "bazarr-abi.json";
      text = builtins.toJSON {
        version = 2;
        process = {
          # Point directly to the secure, immutable Nix store Python binary:
          exec = "${bazarrPython}/bin/python"; 
          args = [
            "/app/bazarr/bazarr.py"
            "--no-update"
            "--config"
            "/data/"
          ];
        };
      };
      destination = "/app/main"; 
    };

  in {
    packages.${system} = {
      default = self.packages.${system}.bazarr-image;
      bazarr-image = pkgs.dockerTools.buildImage {
        name = "minimalbase-ng";
        tag = "latest";
        fromImage = minimalbase.packages.${system}.base-image;

        copyToRoot = pkgs.buildEnv {
          name = "root";
          paths = [
            pkgs.coreutils
            pkgs.tzdata
            pkgs.cacert
            pkgs.ffmpeg-headless
            pkgs.unrar
            pkgs.p7zip

            bazarr
            bazAbi
            passwdFile
          ];
        };

        config = {
          Entrypoint = [ "${minimalbase.packages.${system}.container-init}/bin/container-init" ];

          User = "1000:1000";

          Env = [
            "PATH=/bin"
            "TZ=UTC"
            "LANG=en_US.UTF-8"
          ];
        };
      };
    };
  };
}
