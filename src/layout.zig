const std = @import("std");
const Dom = @import("dom.zig");
const CSS = @import("css.zig");
const Style = @import("style.zig");
const StyledNode = Style.StyledNode;
const Value = CSS.Value;

const allocator = std.heap.page_allocator;

pub const Dimension = struct {
    content: Rect,
    padding: EdgeSizes,
    border: EdgeSizes,
    margin: EdgeSizes,

    const Dm = @This();

    pub fn default() Dimension {
        return Dimension{
            .content = Rect.default(),
            .padding = EdgeSizes.default(),
            .border = EdgeSizes.default(),
            .margin = EdgeSizes.default(),
        };
    }

    pub fn padding_box(self: Dm) Rect {
        return self.content.expanded_by(self.padding);
    }

    pub fn border_box(self: Dm) Rect {
        return self.padding_box().expanded_by(self.border);
    }

    pub fn margin_box(self: Dm) Rect {
        return self.border_box().expanded_by(self.margin);
    }
};

pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    fn default() Rect {
        return Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    }

    fn expanded_by(self: Rect, edge: EdgeSizes) Rect {
        return Rect{
            .x = self.x - edge.left,
            .y = self.y - edge.top,
            .width = self.width + edge.left + edge.right,
            .height = self.height + edge.top + edge.bottom,
        };
    }
};
const EdgeSizes = struct {
    left: f32,
    right: f32,
    top: f32,
    bottom: f32,

    fn default() EdgeSizes {
        return EdgeSizes{ .left = 0, .right = 0, .top = 0, .bottom = 0 };
    }
};

pub const BoxType = union(enum) {
    BlockNode: *StyledNode,
    InlineNode: *StyledNode,
    AnonymouseBlock,

    pub fn get_node_type(self: @This()) ?Dom.NodeType {
        return switch (self) {
            .AnonymouseBlock => null,
            inline else => |style_node| style_node.node.node_type,
        };
    }

    pub fn get(self: @This(), value: []const u8) !?CSS.Value {
        return switch (self) {
            .AnonymouseBlock => {
                var buf: [256]u8 = undefined;
                const msg = try std.fmt.bufPrint(&buf, "AnnonymouseBlock dont have {s} property", .{value});
                @panic(msg);
            },
            inline else => |style_node| style_node.specified_values.get("font-size"),
        };
    }

    pub fn print(self: @This()) void {
        switch (self) {
            .AnonymouseBlock => std.debug.print("ann_block\n", .{}),
            inline else => |style_node| style_node.node.node_type.print(),
        }
    }
};

// var prev: ?LayoutBox = null;
pub const LayoutBox = struct {
    dimension: Dimension,
    box_type: BoxType,
    children: std.ArrayList(LayoutBox),

    text: ?[]const u8 = null,
    img: ?[]const u8 = null,

    const Lb = @This();

    fn new(box_type: BoxType, text: ?[]const u8, img: ?[]const u8, alloc: std.mem.Allocator) LayoutBox {
        return LayoutBox{
            .box_type = box_type,
            .dimension = Dimension.default(),
            .children = std.ArrayList(LayoutBox).init(alloc),
            .text = text,
            .img = img,
        };
    }

    fn get_inline_container(self: *Lb, alloc: std.mem.Allocator) !*LayoutBox {
        return switch (self.box_type) {
            BoxType.InlineNode, BoxType.AnonymouseBlock => self,
            BoxType.BlockNode => blk: {
                if (self.children.getLastOrNull()) |last_children| {
                    switch (last_children.box_type) {
                        BoxType.AnonymouseBlock => {},
                        else => try self.children.append(LayoutBox.new(BoxType.AnonymouseBlock, self.text, null, alloc)),
                    }

                    break :blk &self.children.items[self.children.items.len - 1];
                } else {
                    try self.children.append(LayoutBox.new(BoxType.AnonymouseBlock, self.text, null, alloc));
                    break :blk &self.children.items[self.children.items.len - 1];
                }
            },
        };
    }

    //--------

    fn layout(self: *Lb, containing_block: Dimension) void {
        switch (self.box_type) {
            BoxType.BlockNode => |style_node| {
                switch (style_node.display()) {
                    .Flex => self.layout_flex(containing_block),
                    else => self.layout_block(containing_block),
                }
            },
            BoxType.InlineNode, BoxType.AnonymouseBlock => {},
        }
    }

    fn layout_flex(self: *Lb, containing_block: Dimension) void {
        self.dimension.content.width = containing_block.content.width;
        self.dimension.content.y = containing_block.content.y + containing_block.content.height;
        self.dimension.content.x = containing_block.content.x;

        // std.debug.print("wd: {d}\n", .{containing_block.content.width});

        var dims = self.calculate_flex_width2(containing_block);
        defer dims.deinit();

        for (self.children.items, dims.items) |*child, *dim| {
            dim.content.y = self.dimension.content.y;
            dim.content.x += containing_block.content.x;
            // dim.content.x += self.dimension.content.x;
            child.layout(dim.*);
        }

        // for (self.children.items) |*child| {
        //     child.layout(self.dimension);
        // }

        self.calculate_flex_width(containing_block);
        // self.calculate_block_height();

        // self.calculate_flex_position(containing_block);
        self.calculate_flex_height();
        // self.calculate_block_position(containing_block);

        // for (self.children.items) |*child| {
        //     switch (child.box_type) {
        //         BoxType.BlockNode => |style_node| switch (style_node.display()) {
        //             .Flex => self.layout_flex(containing_block),
        //             else => {},
        //         },
        //         else => {},
        //     }
        // }
    }

    fn calculate_flex_position(self: *Lb, containing_block: Dimension) void {
        const zero = Value{ .Length = .{ .value = 0, .unit = .px } };

        for (self.children.items) |*child| {
            const style = child.get_style_node();
            var d = &child.dimension;

            d.margin.top = style.lookup("margin-top", "margin", zero).to_px();
            d.margin.bottom = style.lookup("margin-bottom", "margin", zero).to_px();

            // d.content.y = containing_block.content.height + containing_block.content.y + d.margin.top + d.border.top + d.padding.top;
            d.content.y = containing_block.content.height + containing_block.content.y;

            child.calculate_flex_position(self.dimension);
        }
    }

    fn calculate_flex_height(self: *Lb) void {
        const d = &self.dimension;

        for (self.children.items) |*child| {
            child.calculate_block_height();

            // std.debug.print("{d}\n", .{child.dimension.margin_box().height});

            if (child.dimension.margin_box().height > d.content.height) {
                d.content.height = child.dimension.margin_box().height;
            }

            if (child.dimension.margin_box().height == 0) {
                child.dimension.content.height = d.content.height;
            }

            child.calculate_flex_height();
        }

        if (self.get_style_node().value("height")) |height| {
            d.content.height = height.to_px();
        }

        // var llh: f32 = 0;

        // for (self.children.items) |*child| {
        //     var lh: f32 = 0;
        //     child.findL(&lh, "height");

        //     var lm: f32 = 0;
        //     child.findL(&lm, "margin");

        //     var lmt: f32 = 0;
        //     child.findL(&lmt, "margin-top");

        //     lh += lm + lmt;

        //     if (lh > llh) llh = lh;

        //     // if (lh >= self.dimension.content.height) {
        //     //     self.dimension.content.height = lh;
        //     // child.dimension.content.height = llh;
        //     // }
        // }

        // self.dimension.content.height = llh;
    }

    fn calculate_flex_children(self: *Lb) void {
        const d = self.dimension;

        for (self.children.items) |*child| {
            child.layout(d);
        }
    }

    fn calculate_flex_width2(self: *Lb, containing_block: Dimension) std.ArrayList(Dimension) {
        var remaining_width = containing_block.content.width;
        var count: f32 = @floatFromInt(self.children.items.len);

        var reserv_inds = std.ArrayList(usize).init(allocator);
        var dimensions = std.ArrayList(Dimension).init(allocator);

        for (self.children.items, 0..) |*child, ind| {
            var lw: f32 = 0;
            child.findL(&lw, "width");

            if (lw > 0) {
                child.dimension.content.width = lw;
                count -= 1;
                remaining_width -= lw;
                reserv_inds.append(ind) catch unreachable;
            }

            var dim = Dimension.default();
            dim.content.width = lw;
            dim.content.height = containing_block.content.height;
            dimensions.append(dim) catch unreachable;
        }

        const child_width = remaining_width / count;
        var x: f32 = 0;

        for (self.children.items, 0..) |*child, ind| {
            var found = false;
            for (reserv_inds.items) |ri| {
                if (ri == ind) {
                    // child.dimension.content.x = x;
                    var dim = &dimensions.items[ind];
                    dim.content.x = x;
                    x += child.dimension.content.width;
                    found = true;
                    break;
                }
            }

            if (found) continue;

            var dim = &dimensions.items[ind];
            dim.content.width = child_width;
            dim.content.x = x;

            // child.dimension.content.width = child_width;
            // child.dimension.content.x = x;

            // for (child.children.items) |*ci| {
            //     ci.dimension.content.x = x;
            // }

            x += child_width;
        }

        return dimensions;
    }

    fn calculate_flex_width(self: *Lb, containing_block: Dimension) void {
        var remaining_width = containing_block.content.width;
        var count: f32 = @floatFromInt(self.children.items.len);

        var reserv_inds = std.ArrayList(usize).init(allocator);

        for (self.children.items, 0..) |*child, ind| {
            var lw: f32 = 0;
            child.findL(&lw, "width");

            if (lw > 0) {
                child.dimension.content.width = lw;
                count -= 1;
                remaining_width -= lw;
                reserv_inds.append(ind) catch unreachable;
            }
        }

        const child_width = remaining_width / count;
        var x: f32 = containing_block.content.x;

        for (self.children.items, 0..) |*child, ind| {
            var found = false;
            for (reserv_inds.items) |ri| {
                if (ri == ind) {
                    child.dimension.content.x = x;
                    x += child.dimension.content.width;
                    found = true;
                    break;
                }
            }

            if (found) continue;

            child.dimension.content.width = child_width;
            child.dimension.content.x = x;

            for (child.children.items) |*ci| {
                ci.dimension.content.x = x;
            }

            x += child_width;
        }
    }

    fn findL(self: *Lb, value: *f32, to_find: []const u8) void {
        if (self.get_style_node().value(to_find)) |v| {
            if (v.to_px() > value.*) value.* = v.to_px();
        }

        for (self.children.items) |*child| {
            if (child.get_style_node().value(to_find)) |v| {
                if (v.to_px() > value.*) value.* = v.to_px();
            }

            child.findL(value, to_find);
        }
    }

    fn layout_block(self: *Lb, containing_block: Dimension) void {
        self.calculate_block_width(containing_block);
        self.calculate_block_position(containing_block);
        self.layout_block_children();
        self.calculate_block_height();
    }

    fn calculate_block_width_flex(self: *Lb, containing_block: Dimension) void {
        const style = self.get_style_node();

        const width = if (style.value("width")) |w| w.to_px() else containing_block.content.width;
        var height: f32 = 0;

        const child_width = containing_block.content.width / @as(f32, @floatFromInt(style.children.items.len));

        for (self.children.items, 0..) |*child, ind| {
            switch (child.box_type) {
                BoxType.BlockNode => {
                    child.dimension.content.width = child_width;
                    child.dimension.content.x = @as(f32, @floatFromInt(ind)) * child_width;
                },
                else => {},
            }

            if (child.dimension.content.height > height) height = child.dimension.content.height;
        }

        self.dimension.content.width = width;
        // self.dimension.content.height = height;
        // std.debug.print("{any}\n", .{self.dimension.content});
    }

    pub fn calculate_block_width(self: *Lb, containing_block: Dimension) void {
        const style = self.get_style_node();

        const auto = Value{ .Keyword = "auto" };
        var width = if (style.value("width")) |w| w else auto;

        // style.node.node_type.print();
        // std.debug.print("w: {d}\n", .{width.to_px()});

        const zero = Value{ .Length = .{ .value = 0, .unit = .px } };

        var margin_left = style.lookup("margin-left", "margin", zero);
        var margin_right = style.lookup("margin-right", "margin", zero);

        const border_left = style.lookup("border-left-width", "border-width", zero);
        const border_right = style.lookup("border-right-width", "border-width", zero);

        const padding_left = style.lookup("padding-left", "padding", zero);
        const padding_right = style.lookup("padding-right", "padding", zero);

        const total = sum(&[_]Value{ margin_left, margin_right, border_left, border_right, padding_left, padding_right, width });

        if (!width.eq(auto) and total > containing_block.content.width) {
            if (margin_left.eq(auto)) {
                margin_left = Value{ .Length = .{ .value = 0, .unit = .px } };
            }
            if (margin_right.eq(auto)) {
                margin_right = Value{ .Length = .{ .value = 0, .unit = .px } };
            }
        }

        const underflow = containing_block.content.width - total;

        const match = .{ width.eq(auto), margin_left.eq(auto), margin_right.eq(auto) };

        if ((match[0] == match[1]) and (match[0] == match[2]) and (match[0] == false)) {
            margin_right = Value{ .Length = .{ .value = margin_right.to_px() + underflow, .unit = .px } };
        } else if ((match[0] == match[1]) and match[0] == false and match[2] == true) {
            margin_right = Value{ .Length = .{ .value = underflow, .unit = .px } };
        } else if ((match[0] == match[2]) and match[0] == false and match[1] == true) {
            margin_left = Value{ .Length = .{ .value = underflow, .unit = .px } };
        } else if (match[0] == true) {
            if (margin_left.eq(auto)) margin_left = Value{ .Length = .{ .value = 0, .unit = .px } };
            if (margin_right.eq(auto)) margin_right = Value{ .Length = .{ .value = 0, .unit = .px } };

            if (underflow >= 0) {
                //-- expand width to fill the underflow
                width = Value{ .Length = .{ .value = underflow, .unit = .px } };
            } else {
                //-- width can't be negative. Adjust the right margin insted
                width = Value{ .Length = .{ .value = 0, .unit = .px } };
                margin_right = Value{ .Length = .{ .value = margin_right.to_px() + underflow, .unit = .px } };
            }
        } else if ((match[1] == match[2]) and match[1] == true and match[0] == false) {
            margin_left = Value{ .Length = .{ .value = underflow / 2, .unit = .px } };
            margin_right = Value{ .Length = .{ .value = underflow / 2, .unit = .px } };
        }

        var d = &self.dimension;
        d.content.width = width.to_px();

        d.padding.left = padding_left.to_px();
        d.padding.right = padding_right.to_px();

        d.border.left = border_left.to_px();
        d.border.right = border_right.to_px();

        d.margin.left = margin_left.to_px();
        d.margin.right = margin_right.to_px();
    }

    fn get_style_node(self: *Lb) *StyledNode {
        return switch (self.box_type) {
            BoxType.BlockNode, BoxType.InlineNode => |node| return node,
            BoxType.AnonymouseBlock => @panic("Anonymouse block box has no style node"),
        };
    }

    fn calculate_block_position(self: *Lb, containing_block: Dimension) void {
        const style = self.get_style_node();
        var d = &self.dimension;

        const zero = Value{ .Length = .{ .value = 0, .unit = .px } };

        d.margin.top = style.lookup("margin-top", "margin", zero).to_px();
        d.margin.bottom = style.lookup("margin-bottom", "margin", zero).to_px();

        d.border.top = style.lookup("border-top-width", "border-width", zero).to_px();
        d.border.bottom = style.lookup("border-bottom-width", "border-width", zero).to_px();

        d.padding.top = style.lookup("padding-top", "padding", zero).to_px();
        d.padding.bottom = style.lookup("padding-bottom", "padding", zero).to_px();

        d.content.x = containing_block.content.x + d.margin.left + d.border.left + d.padding.left;
        d.content.y = containing_block.content.height + containing_block.content.y + d.margin.top + d.border.top + d.padding.top;
    }

    fn layout_block_children(self: *Lb) void {
        var d = &self.dimension;

        var prev: ?*LayoutBox = null;
        var overlap: f32 = 0;

        for (self.children.items) |*child| {
            child.layout(d.*);

            if (prev == null) {
                prev = child;
            } else {
                if (child.box_type.get_node_type() == null or child.box_type.get_node_type().? == .Text) continue;

                // std.debug.print("prev: ", .{});
                // prev.?.box_type.print();
                // std.debug.print("curr: ", .{});
                // child.box_type.print();

                overlap = if (prev.?.dimension.margin.bottom < child.dimension.margin.top) prev.?.dimension.margin.bottom else child.dimension.margin.top;
                // std.debug.print("{d} {d}\n", .{ prev.?.dimension.margin.bottom, overlap });
                prev = child;
            }

            d.content.height = d.content.height + child.dimension.margin_box().height;
            d.content.y -= overlap;
            overlap = 0;
        }
    }

    fn calculate_block_height(self: *Lb) void {
        if (self.get_style_node().value("height")) |h| {
            self.dimension.content.height = h.to_px();
        }
    }
};

const default_font_size: Value = .{ .Length = .{ .value = 50, .unit = .px } };
fn inharite_from_parent(parent: *StyledNode, child: *StyledNode) !void {
    switch (child.node.node_type) {
        .Text => {
            var it = parent.specified_values.iterator();
            while (it.next()) |entry| {
                if (!std.mem.startsWith(u8, entry.key_ptr.*, "margin") and
                    !std.mem.startsWith(u8, entry.key_ptr.*, "padding") and
                    !std.mem.startsWith(u8, entry.key_ptr.*, "border"))
                {
                    try child.specified_values.put(entry.key_ptr.*, entry.value_ptr.*);
                }
            }

            const font_size = if (child.specified_values.get("font-size")) |font_size| font_size else default_font_size;
            try child.specified_values.put("height", font_size);
        },
        else => {},
    }
}

pub fn build_layout_tree(style_node: *StyledNode, alloc: std.mem.Allocator) !LayoutBox {
    var text: ?[]const u8 = null;
    var img: ?[]const u8 = null;

    switch (style_node.node.node_type) {
        .Text => |txt| text = txt,
        .Element => |elem| if (std.mem.eql(u8, elem.tag_name, "img")) {
            img = elem.attrs.get("src");
        },
    }

    var root = LayoutBox.new(
        switch (style_node.display()) {
            .Flex => BoxType{ .BlockNode = style_node },
            .Block => BoxType{ .BlockNode = style_node },
            .Inline => BoxType{ .InlineNode = style_node },
            .None => @panic("Root node has display: none."),
        },
        text,
        img,
        alloc,
    );

    for (style_node.children.items) |*child| {
        // std.debug.print("{any}\n", .{child.display()});
        // std.debug.print("{any}\n", .{child.node.node_type});

        try inharite_from_parent(style_node, child);

        switch (child.display()) {
            .Flex, .Block => try root.children.append(try build_layout_tree(child, alloc)),
            .Inline => {
                var inline_container = try root.get_inline_container(alloc);
                try inline_container.children.append(try build_layout_tree(child, alloc));
            },
            .None => {},
        }
    }

    return root;
}

pub fn layout_tree(node: *StyledNode, containing_block: *Dimension, alloc: std.mem.Allocator) !LayoutBox {
    containing_block.content.height = 0;

    var root_box = try build_layout_tree(node, alloc);

    // pp(root_box);

    root_box.layout(containing_block.*);

    return root_box;
}

fn pp(lb: LayoutBox) void {
    for (lb.children.items) |child| {
        std.debug.print("bt :  {s}\n", .{@tagName(child.box_type)});
        child.box_type.print();

        pp(child);
    }
}

fn sum(slice: []const Value) f32 {
    var total: f32 = 0;

    for (slice) |itm| {
        total += itm.to_px();
    }

    return total;
}
