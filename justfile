help:
    @just --list

clean:
    rm -r loggers/wayland/.zig-cache loggers/wayland/zig-out

build-zig:
    cd loggers/wayland && zig build

build-all: build-zig

run-logger-wayland:
    cd loggers/wayland && zig build run

# Get the current system (e.g., "x86_64-linux", "aarch64-linux")

[private]
_system := `nix eval --raw --impure --expr 'builtins.currentSystem'`

localCI:
    nix flake check
    nix build .#devShells.{{ _system }}.default --no-link
