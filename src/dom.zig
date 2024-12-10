const std = @import("std");

// pub const AttrMap = std.AutoHashMap([]const u8, []const u8);
pub const AttrMap = std.StringHashMap([]const u8);
pub const ElementData = struct {
    tag_name: []const u8,
    attrs: AttrMap,

    pub fn id(self: *@This()) ?[]const u8 {
        return self.attrs.get("id");
    }

    pub fn classes(self: *@This(), alloc: std.mem.Allocator) !std.ArrayList([]const u8) {
        var hash_set = std.ArrayList([]const u8).init(alloc);

        if (self.attrs.get("class")) |classlist| {
            var it = std.mem.splitAny(u8, classlist, " ");
            while (it.next()) |cls| {
                try hash_set.append(cls);
            }
        }

        return hash_set;
    }
};

pub const NodeType = union(enum) {
    Text: []const u8,
    Element: ElementData,

    pub fn print(self: @This()) void {
        switch (self) {
            .Element => |elm| std.debug.print("{s}\n", .{elm.tag_name}),
            .Text => |txt| std.debug.print("{s}\n", .{txt}),
        }
    }
};

pub const Node = struct {
    children: std.ArrayList(Node),
    node_type: NodeType,
};

//-- helper functions

pub fn text(data: []const u8, alloc: std.mem.Allocator) Node {
    return Node{
        .children = std.ArrayList(Node).init(alloc),
        .node_type = NodeType{ .Text = data },
    };
}

pub fn elem(tag_name: []const u8, attrs: AttrMap, children: std.ArrayList(Node)) Node {
    return Node{
        .children = children,
        .node_type = NodeType{
            .Element = .{
                .tag_name = tag_name,
                .attrs = attrs,
            },
        },
    };
}
