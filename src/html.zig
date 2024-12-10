const std = @import("std");
const Dom = @import("dom.zig");
const Parser = @import("Parser.zig");
const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;

const Self = @This();

parser: Parser,
alloc: std.mem.Allocator,

pub fn parse_node(self: *Self) anyerror!Dom.Node {
    if (self.parser.starts_with("<")) {
        return try self.parse_element();
    } else return self.parse_text();
}

//-----
fn fndOpeningTag(c: u8) bool {
    return c != '<';
}

pub fn parse_text(self: *Self) !Dom.Node {
    return Dom.text(try self.parser.consume_while(fndOpeningTag), self.parser.alloc);
}
//----

pub fn parse_element(self: *Self) !Dom.Node {
    try self.parser.expect("<");
    const tag_name = try self.parser.parse_name();
    const attrs = try self.parse_attributes();

    if (self.parser.starts_with("/>")) {
        self.parser.consume_chars(2);
        return Dom.elem(tag_name, attrs, std.ArrayList(Dom.Node).init(self.alloc));
    } else if (std.mem.eql(u8, tag_name, "img")) {
        try self.parser.expect(">");
        return Dom.elem(tag_name, attrs, std.ArrayList(Dom.Node).init(self.alloc));
    }

    try self.parser.expect(">");

    const children = try self.parse_nodes();

    try self.parser.expect("</");
    try self.parser.expect(tag_name);
    try self.parser.expect(">");

    return Dom.elem(tag_name, attrs, children);
}

fn ckalp(c: u8) bool {
    return switch (c) {
        'A'...'Z', 'a'...'z', '-', '_' => true,
        else => false,
    };
}

pub fn parse_attr(self: *Self) ![2][]const u8 {
    const name = try self.parser.parse_name();
    // const name = try self.parser.consume_while(ckalp);
    try self.parser.expect("=");
    const value = try self.parse_attr_value();
    return .{ name, value };
}

fn findQuote(c: u8) bool {
    return c != '"' and c != '\'';
}
pub fn parse_attr_value(self: *Self) ![]const u8 {
    const open_quote = self.parser.consume_char();

    assert(open_quote == '"' or open_quote == '\'');
    const value = try self.parser.consume_while(findQuote);
    const close_quote = self.parser.consume_char();
    try expectEqual(open_quote, close_quote);
    return value;
}

fn parse_attributes(self: *Self) !Dom.AttrMap {
    var attributes = Dom.AttrMap.init(self.parser.alloc);
    while (true) {
        try self.parser.consume_whitespace();
        if (self.parser.next_char() == '>') break;

        const pair = try self.parse_attr();
        try attributes.put(pair[0], pair[1]);
    }

    return attributes;
}

pub fn parse_nodes(self: *Self) !std.ArrayList(Dom.Node) {
    var nodes = std.ArrayList(Dom.Node).init(self.parser.alloc);
    while (true) {
        try self.parser.consume_whitespace();
        if (self.parser.eof() or self.parser.starts_with("</")) break;

        var node = try self.parse_node();
        switch (node.node_type) {
            .Element => |elm| if (std.mem.eql(u8, elm.tag_name, "ol") or std.mem.eql(u8, elm.tag_name, "ul")) {
                try add_bullets(&node, self.alloc);
            },
            else => {},
        }

        try nodes.append(node);
    }

    return nodes;
}

pub fn parse(source: []const u8, alloc: std.mem.Allocator) !Dom.Node {
    var h = Self{ .parser = Parser{ .pos = 0, .input = source, .alloc = alloc }, .alloc = alloc };
    var nodes = try h.parse_nodes();

    if (nodes.items.len == 1) {
        return nodes.swapRemove(0);
    } else {
        return Dom.elem("html", Dom.AttrMap.init(alloc), nodes);
    }
}

//--
var count: usize = 0;
fn add_bullets(node: *Dom.Node, alloc: std.mem.Allocator) !void {
    for (node.children.items) |*child| {
        switch (child.node_type) {
            .Text => |txt| {
                // std.debug.print("{s}\n", .{txt});
                count += 1;
                child.node_type.Text = try std.fmt.allocPrint(alloc, "     {d}. {s}", .{ count, txt });
            },
            else => {},
        }

        try add_bullets(child, alloc);
    }
}
