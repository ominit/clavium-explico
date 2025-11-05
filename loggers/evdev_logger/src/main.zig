const std = @import("std");
const evdev_logger = @import("evdev_logger");
const xkb = @cImport({
    @cInclude("xkbcommon/xkbcommon.h");
});
const input = @cImport({
    @cInclude("linux/input.h");
});
const LONG_BIT = @sizeOf(c_ulong) * 8;

const Keyboard = struct { path: *c_char, fd: c_int, state: *xkb.xkb_state, next: *Keyboard };

fn is_keyboard(fd: c_int) bool {
    var errno = undefined;
    const evbits = [(((input.EV_CNT) + LONG_BIT - 1) / LONG_BIT)]c_ulong{0};
    const keybits = [(((input.KEY_CNT) + LONG_BIT - 1) / LONG_BIT)]c_ulong{0};

    errno = input.ioctl(fd, input.EVIOCGBIT(0, evbits.len), evbits);
    if (errno) return false;

    if (!evdev_bit_is_set(evbits, input.EV_KEY))
        return false;

    errno = input.ioctl(fd, input.EVIOCGBIT(input.EV_KEY, @sizeOf(keybits)), keybits);
    if (errno) return false;

    for (input.KEY_RESERVED..input.KEY_MIN_INTERESTING + 1) |i| if (evdev_bit_is_set(keybits, i)) return true;

    return false;
}

fn evdev_bit_is_set(array: *const []c_ulong, bit: c_int) bool {
    const oneULL: c_ulonglong = comptime 1;
    return array[bit / LONG_BIT] & (oneULL << (bit % LONG_BIT));
}

fn keyboard_new(entry: *input.dirent, keymap: *xkb.xkb_keymap, state: *xkb.xkb_state, out: **Keyboard) c_int {
    _ = entry;
    _ = keymap;
    _ = state;
    _ = out;
}

fn get_keyboards(keymap: *xkb.xkb_keymap, state: *xkb.xkb_state) !?*Keyboard {
    _ = keymap;
    _ = state;
    const keyboards: *Keyboard = undefined;
    const keyboard: *Keyboard = undefined;
    var dir = try std.fs.openDirAbsolute("/dev/input", .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        _ = entry;
    }
    _ = keyboard;

    return keyboards;
}

pub fn main() !void {
    const context = xkb.xkb_context_new(xkb.XKB_CONTEXT_NO_FLAGS);
    if (context == null) {
        std.log.err("Failed to create xkbcommon context", .{});
        return error.XkbContextCreationFailed;
    }
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
    defer xkb.xkb_keymap_unref(keymap);

    const state = xkb.xkb_state_new(keymap);
    if (state == null) {
        std.log.err("Failed to create xkbcommon state.", .{});
        return error.XkbStateCreationFailed;
    }
    defer xkb.xkb_state_unref(state);

    const keyboards = try get_keyboards(keymap.?, state.?);
    _ = keyboards;
}
