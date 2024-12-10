const std = @import("std");
const Dom = @import("dom.zig");

const Self = @This();

pos: usize,
input: []const u8,
alloc: std.mem.Allocator,

//-- read the current carecter without consuming it
pub fn next_char(self: Self) u8 {
    return self.input[self.pos];
}

pub fn starts_with(self: Self, s: []const u8) bool {
    return std.mem.startsWith(u8, self.input[self.pos..], s);
}

pub fn expect(self: *Self, s: []const u8) !void {
    if (self.starts_with(s)) {
        self.pos += s.len;
    } else {
        var buf: [128]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "Expected {{ {s} }} at byte {d} but not found", .{ s, self.pos });
        std.debug.print("{s}\n", .{self.input[self.pos - 100 .. self.pos]});
        @panic(msg);
    }
}

pub fn eof(self: Self) bool {
    return self.pos >= self.input.len;
}

//----

pub fn consume_char(self: *Self) u8 {
    const c = self.next_char();
    self.pos += 1;
    return c;
}

pub fn consume_chars(self: *Self, count: usize) void {
    self.pos += count;
}

pub fn consume_while(self: *Self, testFn: fn (u8) bool) ![]const u8 {
    var result = std.ArrayList(u8).init(self.alloc);
    while (!self.eof() and testFn(self.next_char())) {
        try result.append(self.consume_char());
    }
    return try result.toOwnedSlice();
}

pub fn consume_whitespace(self: *Self) !void {
    _ = try self.consume_while(std.ascii.isWhitespace);
}

//----

pub fn parse_name(self: *Self) ![]const u8 {
    return self.consume_while(std.ascii.isAlphanumeric);
}

pub fn parse_identifer(self: *Self) ![]const u8 {
    return self.consume_while(valid_identifier_char);
}

pub fn valid_identifier_char(c: u8) bool {
    return switch (c) {
        '0'...'9', 'A'...'Z', 'a'...'z', '-', '_' => true,
        else => false,
    };
}
