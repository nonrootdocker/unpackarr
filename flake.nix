{
  description = "minimalbase + unpackerr service";
  inputs = {
    nixpkgs.follows = "minimalbase/nixpkgs";
    minimalbase.url = "github:nonrootdocker/minimalbase";
    unpackerr-src = {
      url = "github:unpackerr/unpackerr";
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
    # Unpackerr package
    # ----------------------------
    unpackerr = pkgs.buildGoModule {
      pname = "unpackerr";
      version = "1.0.4";
      src = unpackerr-src;
      vendorHash = "sha256-T1/QeT+JbS5qjEIMj/iaalPrcq25dv9spIOJlmhehgw=";
    };

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
      unpackerr-image = pkgs.dockerTools.buildImage {
        name = "minimalbase";
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
