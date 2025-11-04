const std = @import("std");
const evdev_logger = @import("evdev_logger");
const xkb = @cImport({
    @cInclude("xkbcommon/xkbcommon.h");
    @cInclude("stdio.h");
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit(); // Clean up GPA on exit
    const allocator = gpa.allocator();

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

    const keycode = 23;
    const keysym = xkb.xkb_state_key_get_one_sym(state, keycode);
    const keysym_name_size = std.math.cast(usize, xkb.xkb_keysym_get_name(keysym, null, 0) + 1).?;
    const keysym_name = try allocator.alloc(u8, keysym_name_size);
    defer allocator.free(keysym_name);
    _ = std.math.cast(usize, xkb.xkb_keysym_get_name(keysym, keysym_name.ptr, keysym_name.len) + 1).?;
    std.debug.print("{s}", .{keysym_name});
    const utf8_size = std.math.cast(usize, xkb.xkb_state_key_get_utf8(state, keycode, null, 0) + 1).?;
    const buffer = try allocator.alloc(u8, utf8_size);
    defer allocator.free(buffer);
    _ = xkb.xkb_state_key_get_utf8(state, keycode, buffer.ptr, buffer.len);
    std.debug.print("{s}", .{buffer});
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
