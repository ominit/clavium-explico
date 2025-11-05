const std = @import("std");
const evdev_logger = @import("evdev_logger");
const xkb = @cImport({
    @cInclude("xkbcommon/xkbcommon.h");
    @cInclude("stdio.h");
});
const input = @cImport({
    @cInclude("linux/input.h");
});

fn open_keyboard() []std.os.linux.pollfd {
    const fd = std.os.linux.open("/dev/input/event3", .{ .ACCMODE = .RDONLY, .NONBLOCK = true }, 0);
    const pollfd: std.os.linux.pollfd = .{
        .fd = @intCast(fd),
        .events = std.os.linux.POLL.IN,
        .revents = 0,
    };
    defer _ = std.os.linux.close(pollfd.fd);

    var pollfds = [_]std.os.linux.pollfd{pollfd};
    return pollfds[0..];
    // var pollfd: std.os.linux.pollfd = undefined;
    // pollfd.fd = std.math.cast(i32, std.os.linux.open("/dev/input/event3", .{ .NONBLOCK = true, .ACCMODE = .RDONLY }, 0)).?;
    // defer _ = std.os.linux.close(pollfd[0].fd);
    // const pollfds = [*]std.os.linux.pollfd{pollfd};
    // return pollfds;
}

fn read_keycode(allocator: std.mem.Allocator, keycode: u32) !void {
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
    std.debug.print("`{s}`\n", .{buffer});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const pollfd = open_keyboard();

    var i: usize = 0;
    while (true) {
        const ret = std.os.linux.poll(pollfd.ptr, pollfd.len, -1);
        if (ret <= 0) continue;
        const buf: []u8 align(@alignOf(input.input_event)) = try allocator.alloc(u8, @sizeOf(input.input_event));
        defer allocator.free(buf);
        std.debug.print("hi - {any}\n", .{input.KEY_T});
        const r = std.os.linux.read(pollfd[0].fd, buf.ptr, @sizeOf(input.input_event));
        if (r < 0) {
            std.log.debug("error, r is less than 0, r = {d}", .{r});
            break;
        }
        const input_event: *input.input_event = @ptrCast(@alignCast(buf));
        std.debug.print("{any}\n", .{input_event});

        try read_keycode(allocator, input_event.code);
        i += 1;
    }
}
