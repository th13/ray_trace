const std = @import("std");
const rt = @import("rt.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

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

    const proj = try scene.project(allocator);
    defer allocator.free(proj.data);
    try proj.printP6();
}
