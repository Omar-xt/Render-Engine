const std = @import("std");
const rl = @import("raylib");
const Dom = @import("dom.zig");
const CSS = @import("css.zig");
const HTML = @import("html.zig");
const Style = @import("style.zig");
const Layout = @import("layout.zig");
const Display = @import("display.zig");
const Watcher = @import("watcher.zig");
const print = @import("pritty.zig").print;

fn intToString(int: i32, buf: []u8) ![:0]const u8 {
    return try std.fmt.bufPrintZ(buf, "{}", .{int});
}

const TextureRect = struct { tex: rl.Texture2D, src_rect: rl.Rectangle, rect: rl.Rectangle };

pub fn main() anyerror!void {
    const screenWidth = 830;
    const screenHeight = 860;

    rl.initWindow(screenWidth, screenHeight, "Omar Hasan");
    defer rl.closeWindow();

    const font = rl.loadFont("open-sans/OpenSans-Regular.ttf");
    rl.setTextureFilter(font.texture, .texture_filter_bilinear);

    const bold_font = rl.loadFont("open-sans/OpenSans-Bold.ttf");
    // const bold_font = rl.loadFontEx("open-sans/OpenSans-Bold.ttf", 36, null);
    rl.setTextureFilter(bold_font.texture, .texture_filter_bilinear);

    rl.setWindowState(rl.ConfigFlags{ .window_resizable = true });
    rl.setTargetFPS(60);

    const allocator = std.heap.page_allocator;

    const path = "web-page/Portfolio2";

    var watcher = try Watcher.init(path, allocator);
    defer watcher.deinit();
    watcher.call_back = load;

    var display_list = try load(path, allocator);

    var textures = std.ArrayList(TextureRect).init(allocator);
    defer textures.deinit();

    for (display_list.items) |dl| {
        switch (dl) {
            .Img => |img| {
                const tex = rl.loadTexture(try std.fmt.allocPrintZ(allocator, "{s}", .{img.src}));
                try textures.append(.{
                    .tex = tex,
                    .src_rect = .{ .x = 0, .y = 0, .width = @floatFromInt(tex.width), .height = @floatFromInt(tex.height) },
                    .rect = get_rectangle(img.rect),
                });
            },
            else => {},
        }
    }

    var scroll_offset: f32 = 0;
    const scroll_speed: f32 = 50;

    // var fps_buf: [5]u8 = undefined;
    while (!rl.windowShouldClose()) {
        if (try watcher.watch()) |val| {
            display_list = val;
        }

        //-- event handel
        scroll_offset += (rl.getMouseWheelMove() * scroll_speed);

        //-- Draw -------
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.black);

        for (display_list.items) |dl| {
            switch (dl) {
                .SolidColor => |sc| {
                    rl.drawRectangle(
                        @intFromFloat(sc.rect.x),
                        @as(i32, @intFromFloat(sc.rect.y)) + @as(i32, @intFromFloat(scroll_offset)),
                        @intFromFloat(sc.rect.width),
                        @intFromFloat(sc.rect.height),
                        get_color(sc.color),
                    );
                    // std.debug.print("{d}\n", .{sc.rect.height});
                },

                // else => {},

                .Text => |sc| {
                    // rl.drawRectangle(
                    //     @intFromFloat(sc.rect.x),
                    //     @as(i32, @intFromFloat(sc.rect.y)) + @as(i32, @intFromFloat(scroll_offset)),
                    //     @intFromFloat(sc.rect.width),
                    //     @intFromFloat(sc.rect.height),
                    //     rl.Color.yellow,
                    // );

                    rl.drawTextEx(
                        switch (sc.font_weight) {
                            .Normal => font,
                            .Bold => bold_font,
                        },
                        try std.fmt.allocPrintZ(allocator, "{s}", .{sc.text}),
                        .{ .x = sc.rect.x, .y = sc.rect.y + scroll_offset },
                        @floatFromInt(sc.font_size),
                        0,
                        get_color(sc.color),
                    );

                    // rl.drawText(
                    //     try std.fmt.allocPrintZ(allocator, "{s}", .{sc.text}),
                    //     @intFromFloat(sc.rect.x),
                    //     @intFromFloat(sc.rect.y),
                    //     sc.font_size,
                    //     get_color(sc.color),
                    // );
                },

                else => {},
            }
        }

        for (textures.items) |tr| {
            rl.drawTexturePro(tr.tex, tr.src_rect, tr.rect, .{ .x = 0, .y = 0 }, 0, rl.Color.brown);
        }

        //-- fps draw
        // const fps = try intToString(rl.getFPS(), &fps_buf);
        // rl.drawText(fps, 10, 0, 20, rl.Color.light_gray);
    }
}

fn get_color(c: CSS.Color) rl.Color {
    return rl.Color{ .r = c.r, .g = c.g, .b = c.b, .a = c.a };
}

fn get_rectangle(rect: Layout.Rect) rl.Rectangle {
    return rl.Rectangle{ .x = rect.x, .y = rect.y, .width = rect.width, .height = rect.height };
}

fn load(path: []const u8, alloc: std.mem.Allocator) !Display.DisplayList {
    const html_path = try std.fmt.allocPrint(alloc, "{s}/index.html", .{path});
    const css_path = try std.fmt.allocPrint(alloc, "{s}/style.css", .{path});

    var html_file = try std.fs.cwd().openFile(html_path, .{});
    defer html_file.close();

    const css_file = try std.fs.cwd().openFile(css_path, .{});
    defer css_file.close();

    const src = try alloc.alloc(u8, try html_file.getEndPos());
    _ = try html_file.readAll(src);

    const css = try alloc.alloc(u8, try css_file.getEndPos());
    _ = try css_file.readAll(css);

    var view_port = Layout.Dimension.default();
    view_port.content.width = 800;
    view_port.content.height = 600;

    var root_node = try HTML.parse(src, alloc);
    var style_sheet = try CSS.parse(css, alloc);
    var style_root = try Style.style_tree(&root_node, &style_sheet, alloc);

    // std.debug.print("{s}\n", .{style_root.node.node_type.Element.tag_name});
    // var it = style_root.specified_values.iterator();
    // while (it.next()) |entry| {
    //     std.debug.print("{s}\n", .{entry.key_ptr.*});
    //     switch (entry.value_ptr.*) {
    //         .Keyword => |key| std.debug.print("       {s}\n", .{key}),
    //         else => |val| std.debug.print("      {any}\n", .{val}),
    //     }
    // }

    var layout_root = try Layout.layout_tree(&style_root, &view_port, alloc);
    const display_list = try Display.build_display_list(&layout_root, alloc);

    return display_list;
}
