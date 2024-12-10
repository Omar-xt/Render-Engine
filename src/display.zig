const std = @import("std");
const Layout = @import("layout.zig");
const Css = @import("css.zig");

const LayoutBox = Layout.LayoutBox;
const Rect = Layout.Rect;
const Value = Css.Value;
const Color = Css.Color;

const Self = @This();

pub const DisplayList = std.ArrayList(DisplayCommand);

const DisplayCommand = union(enum) {
    SolidColor: struct { color: Color, rect: Rect },
    Text: struct { text: []const u8, font_size: i32, font_weight: FontWeight, color: Color, rect: Rect },
    Img: struct { src: []const u8, rect: Rect },
};

const FontWeight = enum { Bold, Normal };

pub fn build_display_list(layout_root: *LayoutBox, alloc: std.mem.Allocator) !DisplayList {
    var list = DisplayList.init(alloc);

    try render_layout_box(&list, layout_root);

    return list;
}

fn render_layout_box(list: *DisplayList, layout_box: *LayoutBox) !void {
    try render_background(list, layout_box);
    try render_borders(list, layout_box);
    try render_text(list, layout_box);
    try render_img(list, layout_box);

    for (layout_box.children.items) |*child| {
        try render_layout_box(list, child);
    }
}

fn render_img(list: *DisplayList, layout_box: *LayoutBox) !void {
    if (layout_box.img) |src| {
        try list.append(DisplayCommand{ .Img = .{ .src = src, .rect = layout_box.dimension.border_box() } });
    }
}

const default_font_size: i32 = 16;
fn render_text(list: *DisplayList, layout_box: *LayoutBox) !void {
    if (layout_box.text) |txt| {
        // var it = layout_box.box_type.BlockNode.specified_values.iterator();
        // while (it.next()) |entry| {
        //     std.debug.print("{s} : {any}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        // }

        const font_size = if (try layout_box.box_type.get("font-size")) |value| value.to_px() else default_font_size;
        try list.append(DisplayCommand{ .Text = .{
            .text = txt,
            .font_size = @intFromFloat(font_size),
            .font_weight = get_font_weight(layout_box),
            .color = get_color(layout_box, "color").?,
            .rect = layout_box.dimension.border_box(),
        } });
    }
}

fn get_font_weight(layout_box: *LayoutBox) FontWeight {
    return switch (layout_box.box_type) {
        .BlockNode, .InlineNode => |style| blk: {
            if (style.value("font-weight")) |val| {
                if (std.mem.eql(u8, val.Keyword, "bold")) {
                    break :blk .Bold;
                } else if (std.mem.eql(u8, val.Keyword, "normal")) {
                    break :blk .Normal;
                } else @panic("Only supported values for font-weight { bold, normal }");
            } else break :blk .Normal;
        },
        .AnonymouseBlock => .Normal,
    };
}

fn render_background(list: *DisplayList, layout_box: *LayoutBox) !void {
    if (get_color(layout_box, "background")) |color| {
        // std.debug.print("{any}\n", .{layout_box.box_type.BlockNode.node.node_type});
        try list.append(DisplayCommand{ .SolidColor = .{ .color = color, .rect = layout_box.dimension.border_box() } });
    }
}

//--  Return the specified color for CSS property `name`, or None if no color was specified.
fn get_color(layout_box: *LayoutBox, name: []const u8) ?Color {
    return switch (layout_box.box_type) {
        .BlockNode, .InlineNode => |style| if (style.value(name)) |val| val.ColorValue else null,
        .AnonymouseBlock => null,
    };
}

fn render_borders(list: *DisplayList, layout_box: *LayoutBox) !void {
    const color = if (get_color(layout_box, "border-color")) |color| color else return;

    const d = &layout_box.dimension;
    const border_box = d.border_box();

    // Left border
    try list.append(DisplayCommand{ .SolidColor = .{ .color = color, .rect = Rect{
        .x = border_box.x,
        .y = border_box.y,
        .width = d.border.left,
        .height = border_box.height,
    } } });

    // Right border
    try list.append(DisplayCommand{ .SolidColor = .{ .color = color, .rect = Rect{
        .x = border_box.x + border_box.width - d.border.right,
        .y = border_box.y,
        .width = d.border.right,
        .height = border_box.height,
    } } });

    // Top border
    try list.append(DisplayCommand{ .SolidColor = .{ .color = color, .rect = Rect{
        .x = border_box.x,
        .y = border_box.y,
        .width = border_box.width,
        .height = d.border.top,
    } } });

    // Bottom border
    try list.append(DisplayCommand{ .SolidColor = .{ .color = color, .rect = Rect{
        .x = border_box.x,
        .y = border_box.y + border_box.height - d.border.bottom,
        .width = border_box.width,
        .height = d.border.bottom,
    } } });
}
