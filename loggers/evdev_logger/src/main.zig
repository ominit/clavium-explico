const std = @import("std");
const evdev_logger = @import("evdev_logger");
const xkb = @cImport({
    @cInclude("xkbcommon/xkbcommon.h");
});
const input = @cImport({
    @cInclude("linux/input.h");
});
const LONG_BIT = @sizeOf(c_ulong) * 8;

const Keyboard = struct { path: []u8, fd: c_int, state: *xkb.xkb_state, next: ?*Keyboard };

fn is_keyboard(fd: c_int) bool {
    var err: c_int = undefined;
    const num_evbits = (((input.EV_CNT) + LONG_BIT - 1) / LONG_BIT);
    const num_keybits = (((input.KEY_CNT) + LONG_BIT - 1) / LONG_BIT);
    const evbits: [num_evbits]c_ulong = undefined;
    const keybits: [num_keybits]c_ulong = undefined;

    err = input.ioctl(fd, input.EVIOCGBIT(0, @sizeOf([num_evbits]c_ulong)), &evbits);
    if (err < 0) return false;

    if (!evdev_bit_is_set(&evbits, input.EV_KEY))
        return false;

    err = input.ioctl(fd, input.EVIOCGBIT(input.EV_KEY, @sizeOf([num_keybits]c_ulong)), &keybits);
    if (err < 0) return false;

    for (input.KEY_RESERVED..input.KEY_MIN_INTERESTING + 1) |i| if (evdev_bit_is_set(&keybits, i)) return true;

    return false;
}

fn evdev_bit_is_set(array: []const c_ulong, bit: usize) bool {
    const index = bit / LONG_BIT;
    const offset = @as(u6, @intCast(bit % LONG_BIT));
    const val = array[index];
    const mask: c_ulong = @as(c_ulong, 1) << offset;

    return (val & mask) != 0;
}

fn keyboard_new(allocator: std.mem.Allocator, entry: []const u8, keymap: *xkb.xkb_keymap, out: *?*Keyboard) !c_int {
    const path = try std.mem.concat(allocator, u8, &[_][]const u8{ "/dev/input/", entry });
    // defer allocator.free(path);
    const pathz = try std.mem.Allocator.dupeZ(allocator, u8, path);
    defer allocator.free(pathz);

    const fd = std.c.open(pathz, .{ .ACCMODE = .RDONLY, .NONBLOCK = true, .CLOEXEC = true });
    if (fd < 0) {
        allocator.free(path);
        return -1;
    }
    if (!is_keyboard(fd)) {
        allocator.free(path);
        return -1;
    }

    const state = xkb.xkb_state_new(keymap);
    if (state == null) {
        std.log.err("Failed to create xkbcommon state.", .{});
        allocator.free(path);
        return error.XkbStateCreationFailed;
    }
    std.debug.assert(state != null);

    var keyboard = try allocator.create(Keyboard);
    keyboard.fd = fd;
    keyboard.path = path;
    keyboard.state = state.?;
    out.* = keyboard;
    return 0;
}

fn get_keyboards(allocator: std.mem.Allocator, keymap: *xkb.xkb_keymap) !?*Keyboard {
    var keyboards: ?*Keyboard = null;
    var keyboard: ?*Keyboard = null;
    var dir = try std.fs.openDirAbsolute("/dev/input", .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (!std.mem.startsWith(u8, entry.name, "event")) continue;
        const ret = try keyboard_new(allocator, entry.name, keymap, &keyboard);
        if (ret != 0) {
            continue;
        }
        std.debug.assert(keyboard != null);
        keyboard.?.next = keyboards;
        keyboards = keyboard;
    }

    if (keyboards == null) {
        std.log.err("Couldn't find any keyboards.\n", .{});
        return null;
    }

    std.debug.assert(keyboards != null);

    return keyboards;
}

fn free_keyboards(allocator: std.mem.Allocator, keyboards: ?*Keyboard) void {
    var current = keyboards;
    while (current) |keyboard| {
        xkb.xkb_state_unref(keyboard.state);
        _ = std.c.close(keyboard.fd);
        allocator.free(keyboard.path);
        const next = keyboard.next;
        allocator.destroy(keyboard);
        current = next;
    }
}

fn loop(keyboards: ?*Keyboard) !void {
    const fds: *std.c.pollfd = undefined;
    var nfds: c_int = 0;
    var keyboard = keyboards;
    while (keyboard != null) {
        nfds += 1;
        keyboard = keyboard.?.next;
    }
    std.debug.print("nfds - {d}", .{nfds});
    _ = fds;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const context = xkb.xkb_context_new(xkb.XKB_CONTEXT_NO_FLAGS);
    if (context == null) {
        std.log.err("Failed to create xkbcommon context", .{});
        return error.XkbContextCreationFailed;
    }
    std.debug.assert(context != null);
    defer xkb.xkb_context_unref(context);

    // 2. Try to load a keymap (e.g., the default 'evdev' keymap)
    const keymap = xkb.xkb_keymap_new_from_names(
        context,
        null,
        xkb.XKB_KEYMAP_COMPILE_NO_FLAGS,
    );

    if (keymap == null) {
        std.log.err("Failed to create xkbcommon keymap. Do you have XKB data files installed (e.g., xkeyboard-config)?", .{});
        return error.XkbKeymapCreationFailed;
    }
    std.debug.assert(keymap != null);
    defer xkb.xkb_keymap_unref(keymap);

    const keyboards = try get_keyboards(allocator, keymap.?);
    if (keyboards == null) {
        return;
    }
    defer free_keyboards(allocator, keyboards);

    try loop(keyboards);
}
