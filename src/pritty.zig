const std = @import("std");
const Dom = @import("dom.zig");

var depth: usize = 0;

pub fn print(writer: anytype, node: Dom.Node) !void {
    depth += 2;
    switch (node.node_type) {
        .Text => |txt| {
            for (0..depth) |_| {
                _ = try writer.write(" ");
            }
            _ = try writer.write("txt: ");
            _ = try writer.write(txt);
            _ = try writer.write("\n");
        },
        .Element => |elm| {
            for (0..depth) |_| {
                _ = try writer.write(" ");
            }
            _ = try writer.write("tag: ");
            _ = try writer.write(elm.tag_name);
            _ = try writer.write("\n");
            for (0..depth) |_| {
                _ = try writer.write(" ");
            }
            _ = try writer.write("attrs: ");
            var it = elm.attrs.iterator();
            while (it.next()) |entry| {
                _ = try writer.write(entry.key_ptr.*);
                _ = try writer.write("=");
                _ = try writer.write(entry.value_ptr.*);
                _ = try writer.write(" ");
            }
            _ = try writer.write("\n");
        },
    }

    for (node.children.items) |chl| {
        try print(writer, chl);
    }

    depth -= 2;
}
