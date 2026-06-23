{
  description = "minimalbase + unpackerr service";
  inputs = {
    nixpkgs.follows = "minimalbase/nixpkgs";
    minimalbase.url = "github:nonrootdocker/minimalbase";
    unpackerr-src = {
      type = "file";
      url = "https://github.com/unpackerr/unpackerr/releases/latest/download/unpackerr.amd64.linux.gz";
      flake = false;
    };
  };
  outputs = { self, nixpkgs, minimalbase, unpackerr-src }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

    # ----------------------------
    # Unpackerr package (prebuilt release binary, gzip-compressed)
    # ----------------------------
    unpackerr = pkgs.stdenv.mkDerivation {
      pname = "unpackerr";
      version = "release";
      src = unpackerr-src;
      dontUnpack = true;
      nativeBuildInputs = [ pkgs.autoPatchelfHook pkgs.gzip ];
      buildInputs = [ pkgs.stdenv.cc.cc.lib ];
      installPhase = ''
        mkdir -p $out/bin
        gunzip -c $src > $out/bin/unpackerr
        chmod +x $out/bin/unpackerr
      '';
    };
    # ----------------------------
    # Unpackerr version: read from the binary's own `--version` output.
    # Exposed as the `version` output for CI tagging.
    # ----------------------------
    unpackerrVersion = pkgs.runCommand "unpackerr-version" { } ''
      ${unpackerr}/bin/unpackerr --version 2>/dev/null \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | tr -d '\n' > $out
    '';

    # ----------------------------
    # User database configuration (/etc/passwd)
    # ----------------------------
    passwdFile = pkgs.writeTextDir "etc/passwd" ''
      root:x:0:0:root:/root:/bin/sh
      unpackerr:x:1000:1000:unpackerr:/data:/bin/sh
    '';

    # ----------------------------
    # ABI descriptor for container-init
    # ----------------------------
    unpackerrAbi = pkgs.writeTextFile {
      name = "unpackerr-abi.json";
      text = builtins.toJSON {
        version = 2;
        process = {
          exec = "${unpackerr}/bin/unpackerr";
          args = [ "-c" "/data/unpackerr.conf" ];
        };
      };
      destination = "/app/main";
    };

  in {
    packages.${system} = {
      default = self.packages.${system}.unpackerr-image;
      version = unpackerrVersion;
      unpackerr-image = pkgs.dockerTools.buildImage {
        name = "unpackerr";
        tag = "latest";
        fromImage = minimalbase.packages.${system}.base-image;
        copyToRoot = pkgs.buildEnv {
          name = "root";
          paths = [
            pkgs.coreutils
            pkgs.tzdata
            pkgs.cacert
            unpackerr
            unpackerrAbi
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
