const std = @import("std");
const DisplayList = @import("display.zig").DisplayList;

const Self = @This();

path: []const u8,
dir: std.fs.Dir,
file_list: std.ArrayList(std.fs.File),
file_stat: std.ArrayList(std.fs.File.Stat),
alloc: std.mem.Allocator,

call_back: ?*const fn ([]const u8, std.mem.Allocator) anyerror!DisplayList = null,

pub fn init(path: []const u8, alloc: std.mem.Allocator) !Self {
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });

    var file_list = std.ArrayList(std.fs.File).init(alloc);
    var file_stat = std.ArrayList(std.fs.File.Stat).init(alloc);

    try Self.setup(&dir, &file_list, &file_stat);

    return Self{
        .dir = dir,
        .path = path,
        .file_list = file_list,
        .file_stat = file_stat,
        .alloc = alloc,
    };
}

fn setup(dir: *std.fs.Dir, file_list: *std.ArrayList(std.fs.File), file_stat: *std.ArrayList(std.fs.File.Stat)) !void {
    var it = dir.iterate();
    while (try it.next()) |entry| {
        const file = try dir.openFile(entry.name, .{});
        try file_list.append(file);
        try file_stat.append(try file.stat());
    }
}

pub fn deinit(self: *Self) void {
    self.file_list.deinit();
    self.file_stat.deinit();
}

fn clear(self: *Self) void {
    self.file_list.clearRetainingCapacity();
    self.file_stat.clearRetainingCapacity();
}

pub fn watch(self: *Self) !?DisplayList {
    for (0..self.file_list.items.len) |ind| {
        const file = self.file_list.items[ind];
        const stat = self.file_stat.items[ind];

        if (try self.cmp(file, stat)) {
            self.clear();
            try Self.setup(&self.dir, &self.file_list, &self.file_stat);
            return try self.call_back.?(self.path, self.alloc);
        }
    }

    return null;
}

fn cmp(_: *Self, file: std.fs.File, stat: std.fs.File.Stat) !bool {
    const f_stat = try file.stat();

    if (f_stat.mtime > stat.mtime) return true;

    return false;
}
