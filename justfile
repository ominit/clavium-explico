help:
    @just --list

clean:
    rm -rf loggers/evdev_logger/.zig-cache loggers/evdev_logger/zig-out

test-zig:
    cd loggers/evdev_logger && zig build test

test: test-zig

build-zig:
    cd loggers/evdev_logger && zig build

build-all: build-zig

run-evdev-logger: build-zig
    sudo ./loggers/evdev_logger/zig-out/bin/evdev_logger

# Get the current system (e.g., "x86_64-linux", "aarch64-linux")

[private]
_system := `nix eval --raw --impure --expr 'builtins.currentSystem'`

localCI:
    nix flake check
    nix build .#devShells.{{ _system }}.default --no-link
