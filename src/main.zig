const std = @import("std");
const rt = @import("rt.zig");

fn render_scene(allocator: std.mem.Allocator) !rt.Image {
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });

    const camera = rt.Camera{
        .position = .{ 0, 0, -80 },
        .direction = .{ 0, 0, 1 },
    };

    const screen = rt.Screen{
        .width = 1920,
        .height = 1080,
        .focal_distance = 880,
    };

    const overhead_light = rt.Light{
        .position = .{ 0, 400, 0 },
        .color = rt.Color.white(),
        .intensity = 0.85,
    };

    var scene = try rt.Scene.init(allocator, &prng, camera, screen, overhead_light, .{
        .ambient_light = 0.01,
        .enable_antialiasing = true,
    });
    defer scene.deinit();

    try scene.spheres.append(rt.Sphere{
        .name = "Sphere (Red)",
        .center = .{ 0, -40, 250 },
        .r = 40,
        .color = rt.Color.rgb(255, 192, 203),
    });

    try scene.spheres.append(rt.Sphere{
        .name = "Sphere (Blue)",
        .center = .{ -200, 100, 300 },
        .r = 50,
        .color = rt.Color.rgb(144, 213, 255),
    });

    try scene.spheres.append(rt.Sphere{
        .name = "Sphere (Grey)",
        .center = .{ 100, -100, 200 },
        .r = 90,
        .color = rt.Color.rgb(130, 135, 125),
    });

    try scene.spheres.append(rt.Sphere{
        .name = "Christina's Sphere",
        .center = .{ -220, -100, 300 },
        .r = 90,
        .color = rt.Color.rgb(180, 140, 200),
    });

    return try scene.project(allocator);
}

const rl = @import("raylib");
fn show_rl(allocator: std.mem.Allocator, rendering: *const rt.Image) !void {
    rl.initWindow(@intCast(rendering.width), @intCast(rendering.height), "Hello Raylib");
    defer rl.closeWindow();

    const pixels: []rl.Color = try allocator.alloc(rl.Color, rendering.width * rendering.height);
    defer allocator.free(pixels);

    for (pixels, 0..) |*p, i| p.* = rl.Color{ .r = rendering.data[i].r(), .g = rendering.data[i].g(), .b = rendering.data[i].b(), .a = 255 };

    const image = rl.Image{
        .data = pixels.ptr,
        .width = @intCast(rendering.width),
        .height = @intCast(rendering.height),
        .format = .uncompressed_r8g8b8a8,
        .mipmaps = 1,
    };

    const texture = try rl.loadTextureFromImage(image);
    defer rl.unloadTexture(texture);

    rl.setTargetFPS(1);

    while (!rl.windowShouldClose()) {
        rl.updateTexture(texture, pixels.ptr);

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.white);
        rl.drawTexture(texture, 0, 0, .white);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const rendered_img = try render_scene(allocator);
    defer allocator.free(rendered_img.data);
    try show_rl(allocator, &rendered_img);
}
