const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const io = init.io;

    if (args.len > 1 and std.mem.eql(u8, args[1], "--help")) {
        try printHelp(io);
        return;
    }

    const package_json_path = try findPackageJson(arena, io) orelse {
        std.debug.print("package.json not found\n", .{});
        std.process.exit(1);
    };

    const url_template = try getUrlFromPackageJson(arena, io, package_json_path) orelse {
        std.debug.print("makepr.url not defined in package.json\n", .{});
        std.process.exit(1);
    };

    const branch = try getGitBranch(arena, io) orelse {
        std.debug.print("Could not determine git branch\n", .{});
        std.process.exit(1);
    };

    const url = try replaceBranch(arena, url_template, branch);
    std.debug.print("{s}\n", .{url});

    try openBrowser(io, url);
}

fn printHelp(io: Io) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try stdout_writer.print(
        \\Usage: makepr [options]
        \\
        \\Quickly open url for PR or something else using url template in package.json.
        \\
        \\Options:
        \\  --help    Show this help message
        \\
    , .{});
    try stdout_writer.flush();
}

fn findPackageJson(allocator: std.mem.Allocator, io: Io) !?[]const u8 {
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_dir = std.Io.Dir.cwd();
    const len = try std.Io.Dir.realPath(cwd_dir, io, &path_buffer);
    const cwd = path_buffer[0..len];

    var current_dir_path = try allocator.dupe(u8, cwd);
    defer allocator.free(current_dir_path);

    while (true) {
        const file_path = try std.fs.path.join(allocator, &.{ current_dir_path, "package.json" });
        errdefer allocator.free(file_path);

        if (std.Io.Dir.accessAbsolute(io, file_path, .{})) |_| {
            return file_path;
        } else |err| switch (err) {
            error.FileNotFound => {
                allocator.free(file_path);
                const parent = std.fs.path.dirname(current_dir_path) orelse break;
                if (std.mem.eql(u8, parent, current_dir_path)) break;
                const next_dir = try allocator.dupe(u8, parent);
                allocator.free(current_dir_path);
                current_dir_path = next_dir;
                continue;
            },
            else => return err,
        }
    }
    return null;
}

fn getUrlFromPackageJson(allocator: std.mem.Allocator, io: Io, path: []const u8) !?[]const u8 {
    const limit = 1024 * 1024; // 1MB
    const content = std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), io, path, allocator, @enumFromInt(limit)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(content);

    // Remove BOM if present
    var json_content = content;
    if (json_content.len >= 3 and json_content[0] == 0xEF and json_content[1] == 0xBB and json_content[2] == 0xBF) {
        json_content = json_content[3..];
    }

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_content, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const makepr_val = if (parsed.value == .object) parsed.value.object.get("makepr") else null;
    if (makepr_val == null or makepr_val.? != .object) return null;

    const url_val = makepr_val.?.object.get("url") orelse return null;
    if (url_val != .string) return null;

    return try allocator.dupe(u8, url_val.string);
}

fn getGitBranch(allocator: std.mem.Allocator, io: Io) !?[]const u8 {
    const result = try std.process.run(allocator, io, .{
        .argv = &.{ "git", "branch", "--show-current" },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0) return null;

    const branch = std.mem.trim(u8, result.stdout, " \n\r\t");
    if (branch.len == 0) return null;

    return try allocator.dupe(u8, branch);
}

fn replaceBranch(allocator: std.mem.Allocator, template: []const u8, branch: []const u8) ![]const u8 {
    return try std.mem.replaceOwned(u8, allocator, template, "{BRANCH}", branch);
}

fn openBrowser(io: Io, url: []const u8) !void {
    const builtin = @import("builtin");
    const cmd: []const u8 = switch (builtin.target.os.tag) {
        .windows => "start",
        .macos => "open",
        else => "xdg-open",
    };

    // On Windows, 'start' is often a shell builtin, so we must run through cmd.exe
    if (builtin.target.os.tag == .windows) {
        _ = try std.process.spawn(io, .{
            .argv = &.{ "cmd.exe", "/c", "start", url },
        });
    } else {
        _ = try std.process.spawn(io, .{
            .argv = &.{ cmd, url },
        });
    }
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    try std.testing.fuzz({}, testOne, .{});
}

fn testOne(context: void, smith: *std.testing.Smith) !void {
    _ = context;
    // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!

    const gpa = std.testing.allocator;
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(gpa);
    while (!smith.eos()) switch (smith.value(enum { add_data, dup_data })) {
        .add_data => {
            const slice = try list.addManyAsSlice(gpa, smith.value(u4));
            smith.bytes(slice);
        },
        .dup_data => {
            if (list.items.len == 0) continue;
            if (list.items.len > std.math.maxInt(u32)) return error.SkipZigTest;
            const len = smith.valueRangeAtMost(u32, 1, @min(32, list.items.len));
            const off = smith.valueRangeAtMost(u32, 0, @intCast(list.items.len - len));
            try list.appendSlice(gpa, list.items[off..][0..len]);
            try std.testing.expectEqualSlices(
                u8,
                list.items[off..][0..len],
                list.items[list.items.len - len ..],
            );
        },
    };
}
