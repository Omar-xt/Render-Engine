const std = @import("std");
const Dom = @import("dom.zig");
const Parser = @import("Parser.zig");
const expectEqual = std.testing.expectEqual;

const Self = @This();

parser: Parser,

pub const Stylesheet = struct {
    rules: std.ArrayList(Rule),
};

pub const Rule = struct {
    selector: std.ArrayList(Selector),
    declarations: std.ArrayList(Declaration),
};

// const Specificity = [3]u8;
pub const Specificity = struct {
    a: u8,
    b: u8,
    c: u8,

    pub fn sum(self: @This()) u32 {
        return self.a + self.b + self.c;
    }
};

pub const Selector = union(enum) {
    Simple: SimpleSelector,

    pub fn specificity(self: @This()) Specificity {
        const simple = Selector{ .Simple = self.Simple };
        const a: u8 = @intCast(if (simple.Simple.id) |id| id.len else 0);
        const b: u8 = @intCast(simple.Simple.class.items.len);
        const c: u8 = @intCast(if (simple.Simple.tag_name) |tn| tn.len else 0);

        // return .{  a, b, c };
        return Specificity{ .a = a, .b = b, .c = c };
    }
};

pub const SimpleSelector = struct {
    tag_name: ?[]const u8,
    id: ?[]const u8,
    class: std.ArrayList([]const u8),
};

pub const Declaration = struct {
    name: []const u8,
    value: Value,
};

const default_font_size: f32 = 16;
pub const Value = union(enum) {
    Keyword: []const u8,
    Length: Length,
    ColorValue: Color,

    pub fn to_px(self: @This()) f32 {
        return switch (self) {
            .Length => |l| switch (l.unit) {
                .px => l.value,
                //-- px = default font size * em;
                .em => l.value * default_font_size,
            },
            else => 0,
        };
    }

    pub fn eq(self: @This(), other: Value) bool {
        return switch (self) {
            .Keyword => |kw| blk: {
                break :blk switch (other) {
                    .Keyword => |rkw| std.mem.eql(u8, kw, rkw),
                    else => false,
                };
            },
            .Length => |l| blk: {
                break :blk switch (other) {
                    .Length => |rl| l.value == rl.value,
                    else => false,
                };
            },
            .ColorValue => |c| blk: {
                break :blk switch (other) {
                    .ColorValue => |rc| c.eq(rc),
                    else => false,
                };
            },
        };
    }
};

const Length = struct {
    value: f32,
    unit: Unit,
};

const Unit = enum { px, em };

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn eq(self: @This(), other: Color) bool {
        return self.r == other.r and self.g == other.g and self.b == other.b and self.a == other.a;
    }
};
//----

//-----

pub fn init(src: []const u8, alloc: std.mem.Allocator) Self {
    return Self{
        .parser = Parser{ .pos = 0, .input = src, .alloc = alloc },
    };
}

pub fn parse_simple_selector(self: *Self) !SimpleSelector {
    var selector = SimpleSelector{
        .tag_name = null,
        .id = null,
        .class = std.ArrayList([]const u8).init(self.parser.alloc),
    };

    while (!self.parser.eof()) {
        switch (self.parser.next_char()) {
            '#' => {
                _ = self.parser.consume_char();
                selector.id = try self.parser.parse_identifer();
            },
            '.' => {
                _ = self.parser.consume_char();
                try selector.class.append(try self.parser.parse_identifer());
            },
            '*' => {
                _ = self.parser.consume_char();
            },
            else => |c| {
                if (Parser.valid_identifier_char(c)) {
                    selector.tag_name = try self.parser.parse_identifer();
                } else break;
            },
        }
    }

    return selector;
}

//--

pub fn parse_rule(self: *Self) !Rule {
    return Rule{
        .selector = try self.parse_selectors(),
        .declarations = try self.parse_declarations(),
    };
}

pub fn parse_declarations(self: *Self) !std.ArrayList(Declaration) {
    try expectEqual(self.parser.consume_char(), '{');
    var declarations = std.ArrayList(Declaration).init(self.parser.alloc);
    while (true) {
        try self.parser.consume_whitespace();
        if (self.parser.next_char() == '}') {
            _ = self.parser.consume_char();
            break;
        }

        if (self.parser.starts_with("/*")) {
            try self.parse_comment();
        } else {
            try declarations.append(try self.parse_declaration());
        }
    }

    return declarations;
}

fn parse_comment(self: *Self) !void {
    try self.parser.expect("/*");
    while (true) {
        if (self.parser.starts_with("*/")) {
            self.parser.consume_chars(2);
            break;
        }
        _ = self.parser.consume_char();
    }
}

fn parse_declaration(self: *Self) !Declaration {
    const property_name = try self.parser.parse_identifer();
    try self.parser.consume_whitespace();
    try expectEqual(self.parser.consume_char(), ':');
    const value = try self.parse_value();
    try self.parser.consume_whitespace();
    try expectEqual(self.parser.consume_char(), ';');
    return .{ .name = property_name, .value = value };
}

fn parse_value(self: *Self) !Value {
    try self.parser.consume_whitespace();

    return switch (self.parser.next_char()) {
        '0'...'9', '.' => self.parse_length(),
        '#' => self.parse_color(),
        else => Value{ .Keyword = try self.parser.parse_identifer() },
    };
}

fn parse_length(self: *Self) !Value {
    return Value{ .Length = .{
        .value = try self.parse_float(),
        .unit = try self.parse_unit(),
    } };
}

fn chkd(c: u8) bool {
    return switch (c) {
        '0'...'9', '.' => true,
        else => false,
    };
}
fn parse_float(self: *Self) !f32 {
    const s = try self.parser.consume_while(chkd);
    const f = try std.fmt.parseFloat(f32, s);
    return f;
}

fn parse_unit(self: *Self) !Unit {
    const unit = try self.parser.parse_identifer();

    var buf: [16]u8 = undefined;
    const lower_unit = std.ascii.lowerString(&buf, unit);

    if (std.mem.eql(u8, lower_unit, "px") or unit.len == 0) {
        return Unit.px;
    } else if (std.mem.eql(u8, lower_unit, "em")) {
        return Unit.em;
    } else @panic("Only support units { px, em }");
}

fn parse_color(self: *Self) !Value {
    try expectEqual(self.parser.consume_char(), '#');
    return Value{ .ColorValue = .{
        .r = try self.parse_hex_pair(),
        .g = try self.parse_hex_pair(),
        .b = try self.parse_hex_pair(),
        .a = 255,
    } };
}

fn parse_hex_pair(self: *Self) !u8 {
    const s = self.parser.input[self.parser.pos .. self.parser.pos + 2];
    self.parser.pos += 2;
    return try std.fmt.parseInt(u8, s, 16);
}

pub fn parse_selectors(self: *Self) !std.ArrayList(Selector) {
    var selectors = std.ArrayList(Selector).init(self.parser.alloc);
    while (true) {
        try selectors.append(Selector{ .Simple = try self.parse_simple_selector() });
        try self.parser.consume_whitespace();
        switch (self.parser.next_char()) {
            ',' => {
                _ = self.parser.consume_char();
                try self.parser.consume_whitespace();
            },
            '{' => break,
            else => |c| {
                const msg = try std.fmt.allocPrint(self.parser.alloc, "Unexpected carecter {s} in selector list", .{&[1]u8{c}});
                @panic(msg);
            },
        }
    }

    std.mem.sort(Selector, selectors.items, {}, cmpfn);
    return selectors;
}

fn cmpfn(_: void, a: Selector, b: Selector) bool {
    return b.specificity().sum() > a.specificity().sum();
}

//--
pub fn parse_rules(self: *Self) !std.ArrayList(Rule) {
    var rules = std.ArrayList(Rule).init(self.parser.alloc);

    while (true) {
        try self.parser.consume_whitespace();
        if (self.parser.eof()) {
            break;
        }

        try rules.append(try self.parse_rule());
    }

    return rules;
}

pub fn parse(src: []const u8, alloc: std.mem.Allocator) !Stylesheet {
    var css = Self.init(src, alloc);

    return Stylesheet{ .rules = try css.parse_rules() };
}
