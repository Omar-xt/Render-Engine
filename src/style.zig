const std = @import("std");
const Dom = @import("dom.zig");
const Parser = @import("Parser.zig");
const CSS = @import("css.zig");

const Value = CSS.Value;
const Selector = CSS.Selector;
const SimpleSelector = CSS.SimpleSelector;
const Specificity = CSS.Specificity;
const Stylesheet = CSS.Stylesheet;
const Rule = CSS.Rule;

const Self = @This();

parser: Parser,

const PropertyMap = std.StringHashMap(Value);

pub const StyledNode = struct {
    node: *Dom.Node,
    specified_values: PropertyMap,
    children: std.ArrayList(StyledNode),

    pub fn value(self: @This(), name: []const u8) ?Value {
        return self.specified_values.get(name);
    }

    pub fn display(self: @This()) Display {
        const disp = self.value("display");

        return if (disp) |d|
            switch (d) {
                .Keyword => |kwd| blk: {
                    if (std.mem.eql(u8, kwd, "block")) {
                        break :blk Display.Block;
                    } else if (std.mem.eql(u8, kwd, "flex")) {
                        break :blk Display.Flex;
                    } else if (std.mem.eql(u8, kwd, "none")) {
                        break :blk Display.None;
                    } else break :blk Display.Inline;
                },
                else => Display.Inline,
            }
        else
            Display.Block;
    }

    pub fn lookup(self: @This(), name: []const u8, fallback_name: []const u8, default: Value) Value {
        if (self.value(name)) |val| {
            return val;
        } else if (self.value(fallback_name)) |val| {
            return val;
        } else {
            return default;
        }
    }

    pub fn generic_lookup(self: @This(), args: anytype) Value {
        const typ = @TypeOf(args);
        const typeInfo = @typeInfo(typ);

        if (typeInfo != .Struct) {
            @compileError("expected tuple or struct argument, found " ++ @typeName(typ));
        }

        const fields = typeInfo.Struct.fields;

        var val: ?Value = null;

        inline for (fields[0 .. fields.len - 1]) |fld| {
            const fld_name = @field(args, fld.name);
            val = self.specified_values.get(fld_name);

            if (val != null) return val.?;
        }

        return @field(args, fields[fields.len - 1].name);
    }
};

const Display = enum {
    Inline,
    Block,
    Flex,
    None,
};

fn matches(elem: *Dom.ElementData, selector: *Selector, alloc: std.mem.Allocator) !bool {
    return switch (selector.*) {
        .Simple => |*s| try matches_simple_selector(elem, s, alloc),
    };
}

fn matches_simple_selector(elem: *Dom.ElementData, selector: *SimpleSelector, alloc: std.mem.Allocator) !bool {
    if (selector.tag_name) |tn| {
        if (!std.mem.eql(u8, tn, elem.tag_name)) return false;
    }

    if (selector.id) |id| {
        if (elem.id()) |id2| {
            if (!std.mem.eql(u8, id, id2)) return false;
        } else return false;
    }

    const elem_classes = try elem.classes(alloc);
    for (selector.class.items) |cls| {
        var match = false;
        for (elem_classes.items) |e_cls| {
            if (std.mem.eql(u8, cls, e_cls)) match = true;
        }

        if (!match) return false;
    }

    return true;
}

//-----

const MatchdRule = struct { specificity: Specificity, rule: *Rule };

fn match_rule(elem: *Dom.ElementData, rule: *Rule, alloc: std.mem.Allocator) !?MatchdRule {
    for (rule.selector.items) |*slc| {
        if (try matches(elem, slc, alloc)) {
            return MatchdRule{ .specificity = slc.specificity(), .rule = rule };
        }
    }

    return null;
}

fn matching_rules(elem: *Dom.ElementData, stylesheet: *Stylesheet, alloc: std.mem.Allocator) !std.ArrayList(MatchdRule) {
    var result = std.ArrayList(MatchdRule).init(alloc);

    for (stylesheet.rules.items) |*rule| {
        if (try match_rule(elem, rule, alloc)) |m_rule| {
            try result.append(m_rule);
        }
    }

    return result;
}

fn mrcmpfn(_: void, a: MatchdRule, b: MatchdRule) bool {
    return a.specificity.sum() < b.specificity.sum();
}

fn specified_values(elem: *Dom.ElementData, stylesheet: *Stylesheet, alloc: std.mem.Allocator) !PropertyMap {
    var values = std.StringHashMap(Value).init(alloc);
    const rules = try matching_rules(elem, stylesheet, alloc);

    std.mem.sort(MatchdRule, rules.items, {}, mrcmpfn);

    // std.debug.print("a- {any}\n", .{rules.items});

    for (rules.items) |rule| {
        for (rule.rule.declarations.items) |dec| {
            try values.put(dec.name, dec.value);
        }
    }

    return values;
}

pub fn style_tree(root: *Dom.Node, stylesheet: *Stylesheet, alloc: std.mem.Allocator) !StyledNode {
    var childrens = std.ArrayList(StyledNode).init(alloc);

    for (root.children.items) |*child| {
        try childrens.append(try style_tree(child, stylesheet, alloc));
    }

    return StyledNode{
        .node = root,
        .specified_values = switch (root.node_type) {
            .Element => |*elem| blk: {
                var value_map = try specified_values(elem, stylesheet, alloc);
                try add_additional_values(elem, stylesheet, &value_map, alloc);
                try evaluate_style_in_attr_map(root, &value_map, alloc);
                break :blk value_map;
            },
            .Text => try add_default_values(alloc),
        },
        .children = childrens,
    };
}

fn evaluate_style_in_attr_map(node: *Dom.Node, value_map: *PropertyMap, alloc: std.mem.Allocator) !void {
    switch (node.node_type) {
        .Element => |elem| {
            if (elem.attrs.get("style")) |css| {
                const src = try std.fmt.allocPrint(alloc, "a {{ {s} }}", .{css});
                const style_sheet = try CSS.parse(src, alloc);

                for (style_sheet.rules.items) |rule| {
                    // std.debug.print("{any}\n", .{rule.declarations.items});

                    for (rule.declarations.items) |dec| {
                        try value_map.put(dec.name, dec.value);
                    }
                }
            }
        },
        else => {},
    }
}

fn add_default_values(alloc: std.mem.Allocator) !PropertyMap {
    var p_map = PropertyMap.init(alloc);

    const default_falue = "* { font-size: 20px; color: #ffffff; }";
    const style_sheet = try CSS.parse(default_falue, alloc);

    for (style_sheet.rules.items) |rule| {
        // std.debug.print("{any}\n", .{rule.declarations.items});

        for (rule.declarations.items) |dec| {
            try p_map.put(dec.name, dec.value);
        }
    }

    return p_map;
}
fn add_additional_values(elem: *Dom.ElementData, _: *Stylesheet, value_map: *PropertyMap, alloc: std.mem.Allocator) !void {
    var ad_map = std.StringArrayHashMap([]const u8).init(alloc);
    try ad_map.put("h1", "h1 { display: block; font-size: 2em; margin-top: 0.67em; margin-bottom: 0.67em; margin-left: 0; margin-right: 0; font-weight: bold; }");
    try ad_map.put("h2", "h2 { display: block; font-size: 1.5em; margin-top: 0.83em; margin-bottom: 0.83em; margin-left: 0; margin-right: 0; font-weight: bold; }");
    try ad_map.put("h3", "h3 { display: block; font-size: 1.17em; margin-top: 1em; margin-bottom: 1em; margin-left: 0; margin-right: 0; font-weight: bold; }");
    try ad_map.put("h4", "h4 { display: block; font-size: 1em; margin-top: 1.33em; margin-bottom: 1.33em; margin-left: 0; margin-right: 0; font-weight: bold; }");
    try ad_map.put("h5", "h5 { display: block; font-size: 0.83em; margin-top: 1.67em; margin-bottom: 1.67em; margin-left: 0; margin-right: 0; font-weight: bold; }");
    try ad_map.put("h6", "h6 { display: block; font-size: 0.67em; margin-top: 2.33em; margin-bottom: 2.33em; margin-left: 0; margin-right: 0; font-weight: bold; }");
    try ad_map.put("ul", "ul { display: block; margin-top: 1em; margin-bottom: 1em; margin-left: 0px; margin-right: 0px; }");
    try ad_map.put("ol", "ol { display: block; margin-top: 1em; margin-bottom: 1em; margin-left: 0px; margin-right: 0px; }");
    try ad_map.put("p", "p { display: block; margin-top: 1em; margin-bottom: 1em; margin-left: 0px; margin-right: 0px; }");

    //-- img tag specific
    if (std.mem.eql(u8, elem.tag_name, "img")) {
        if (elem.attrs.get("width")) |width| {
            const css = try std.fmt.allocPrint(alloc, "img {{ width: {s}; }}", .{width});
            const style_sheet = try CSS.parse(css, alloc);

            for (style_sheet.rules.items) |rule| {
                for (rule.declarations.items) |dec| {
                    if (value_map.get(dec.name) == null) {
                        try value_map.put(dec.name, dec.value);
                    }
                }
            }
        }

        if (elem.attrs.get("height")) |width| {
            const css = try std.fmt.allocPrint(alloc, "img {{ height: {s}; }}", .{width});
            const style_sheet = try CSS.parse(css, alloc);

            for (style_sheet.rules.items) |rule| {
                for (rule.declarations.items) |dec| {
                    if (value_map.get(dec.name) == null) {
                        try value_map.put(dec.name, dec.value);
                    }
                }
            }
        }
    }
    //---

    if (ad_map.get(elem.tag_name)) |val| {
        const style_sheet = try CSS.parse(val, alloc);

        for (style_sheet.rules.items) |rule| {
            // std.debug.print("{any}\n", .{rule.declarations.items});

            for (rule.declarations.items) |dec| {
                // if (std.mem.eql(u8, val, "li")) {
                //     try value_map.put(try std.fmt.allocPrint(alloc, "* {s}", .{dec.name}), dec.value);
                // }
                if (value_map.get(dec.name) == null) {
                    try value_map.put(dec.name, dec.value);
                }
            }
        }
    }
}
