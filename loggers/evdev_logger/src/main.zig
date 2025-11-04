const std = @import("std");
const evdev_logger = @import("evdev_logger");
const xkb = @cImport({
    @cInclude("xkbcommon/xkbcommon.h");
    @cInclude("stdio.h");
});
const evdev = @cImport({
    @cInclude("linux/input.h");
});

fn open_keyboard() !void {
    const dir = try std.fs.openDirAbsolute("/dev/input", .{ .iterate = true });

    var entry_it = dir.iterate();
    while (try entry_it.next()) |entry| {
        if (!std.mem.startsWith(u8, entry.name, "event")) {
            continue; // Skip non-event files
        }

        const buf: []u8 = undefined;
        const device_path_fmt_buf = try std.fmt.bufPrint(buf, "/dev/input/{s}", .{entry.name});
        const device_path_buf: [*:0]const u8 = @ptrCast(device_path_fmt_buf.ptr);

        // Try to open the device in read-only and non-blocking mode.
        // O_RDWR might be needed for some ioctls or if you wanted to send events.
        const fd = std.math.cast(i32, std.os.linux.open(device_path_buf, .{}, 0)).?;

        // Check if it's an input device (EVIOCGNAME) and supports EV_KEY events.
        var name_buf: [256]u8 = undefined;
        const res_name_len = std.os.linux.ioctl(fd, evdev.EVIOCGNAME(256), name_buf.len);
        if (res_name_len == -1) {
            // Not a device with a name, or error.
            std.os.close(fd);
            continue;
        }
        const device_name_slice = name_buf[0..@intCast(res_name_len)];

        // Check if it supports EV_KEY events
        // evdev.NBITS(evdev.EV_MAX) is a macro, need to figure out its value or a safe upper bound
        // A common way to get capability bits is to query for EV_MAX bits.
        // `BIT_WORD(EV_MAX)` from C's `input.h`
        // var ev_bits_storage: [evdev.NBITS(evdev.EV_MAX)]u8 = undefined;
        // const res_evbits = std.os.linux.ioctl(fd, evdev.EVIOCGBIT(0, evdev.EV_MAX), @ptrCast(&ev_bits_storage));
        // if (res_evbits == -1) {
        //     std.os.close(fd);
        //     continue;
        // }

        // Check if EV_KEY bit is set, indicating it generates key events
        // if (!test_bit(evdev.EV_KEY, &ev_bits_storage)) {
        //     std.os.close(fd);
        //     continue;
        // }

        std.debug.print("Found keyboard device: {s} ('{s}')\n", .{ device_path_buf, device_name_slice });
        // return fd;
    }

    return error.NoKeyboardDeviceFound;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit(); // Clean up GPA on exit
    const allocator = gpa.allocator();

    try open_keyboard();

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

    const keycode = 200;
    const keysym = xkb.xkb_state_key_get_one_sym(state, keycode);
    const keysym_name_size = std.math.cast(usize, xkb.xkb_keysym_get_name(keysym, null, 0) + 1).?;
    const keysym_name = try allocator.alloc(u8, keysym_name_size);
    defer allocator.free(keysym_name);
    _ = std.math.cast(usize, xkb.xkb_keysym_get_name(keysym, keysym_name.ptr, keysym_name.len) + 1).?;
    std.debug.print("`{s}`\n", .{keysym_name});
    const utf8_size = std.math.cast(usize, xkb.xkb_state_key_get_utf8(state, keycode, null, 0) + 1).?;
    const buffer = try allocator.alloc(u8, utf8_size);
    defer allocator.free(buffer);
    _ = xkb.xkb_state_key_get_utf8(state, keycode, buffer.ptr, buffer.len);
    std.debug.print("`{s}`", .{buffer});
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
