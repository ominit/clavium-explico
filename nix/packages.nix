{...}: {
  perSystem = {pkgs, ...}: let
    ce-evdev-logger = pkgs.stdenv.mkDerivation {
      pname = "ce-evdev-logger";
      version = "0.0.1";
      src = ./../loggers/evdev_logger;

      nativeBuildInputs = with pkgs; [zig.hook sqlite libxkbcommon libinput];

      postPatch = ''
        ln -s ${pkgs.callPackage ./evdev-logger-deps.nix {}} $ZIG_GLOBAL_CACHE_DIR/p
      '';

      dontUseZigInstall = true;
      installPhase = ''
        mkdir -p $out/bin
        ls
        cp zig-out/bin/evdev_logger $out/bin/ce-evdev-logger
      '';
    };
  in {
    packages = {
      inherit ce-evdev-logger;
    };
  };
}
