const std = @import("std");
const stdout = std.io.getStdOut().writer();
const debug = std.debug;
const math = std.math;
const expect = std.testing.expect;
const tp = @import("tp.zig");

const Profiler = struct {
    const Self = @This();
    start_ns: i128,

    fn start() Profiler {
        return .{ .start_ns = std.time.nanoTimestamp() };
    }

    fn end(self: *const Self) f64 {
        const elapsed_ns = std.time.nanoTimestamp() - self.start_ns;
        return @as(f64, @floatFromInt(elapsed_ns)) / 1e9;
    }
};

const Color = struct {
    const Self = @This();
    intensities: Vec3,

    fn rgb(red: u8, green: u8, blue: u8) Self {
        return .{ .intensities = .{
            Self.byteToIntensity(red),
            Self.byteToIntensity(green),
            Self.byteToIntensity(blue),
        } };
    }

    fn black() Self {
        return .{ .intensities = .{ 0, 0, 0 } };
    }

    fn white() Self {
        return .{ .intensities = .{ 1, 1, 1 } };
    }

    fn intensify(self: Self, intensity: f32) Self {
        return .{ .intensities = mul(intensity, self.intensities) };
    }

    fn addLighting(self: Self, light: Light) Self {
        const blend = self.intensities * light.color.intensities;
        return .{ .intensities = mul(light.intensity, blend) };
    }

    fn print(self: Self) !void {
        try stdout.writeByte(self.r());
        try stdout.writeByte(self.g());
        try stdout.writeByte(self.b());
    }

    fn printFmt(self: Self) void {
        std.debug.print("({d}, {d}, {d})", .{ self.r(), self.g(), self.b() });
    }

    fn r(self: Self) u8 {
        return Self.intensityToByte(self.intensities[0]);
    }

    fn g(self: Self) u8 {
        return Self.intensityToByte(self.intensities[1]);
    }

    fn b(self: Self) u8 {
        return Self.intensityToByte(self.intensities[2]);
    }

    fn intensityToByte(intensity: f32) u8 {
        const clamped = @max(0.0, @min(1.0, intensity));
        return @as(u8, @intFromFloat(clamped * 255.0));
    }

    fn byteToIntensity(byte: u8) f32 {
        const scaled: f32 = @as(f32, @floatFromInt(byte)) / 255.0;
        return @max(0, @min(1.0, scaled));
    }
};

const Image = struct {
    const Self = @This();
    width: usize,
    height: usize,
    data: []Color,

    fn init(width: usize, height: usize, data: []Color) Self {
        return .{ .width = width, .height = height, .data = data };
    }

    fn printBinary(self: Self) !void {
        for (0..self.height * self.width) |i| {
            try self.data[i].print();
        }
    }

    fn printP6(self: Self) !void {
        var buffered_writer = std.io.bufferedWriter(stdout);
        const writer = buffered_writer.writer();

        try writer.print("P6\n{d} {d}\n255\n", .{ self.width, self.height });
        for (self.data) |pixel| {
            try writer.writeByte(pixel.r());
            try writer.writeByte(pixel.g());
            try writer.writeByte(pixel.b());
        }
        try buffered_writer.flush();
    }
};

const Vec3 = @Vector(3, f32);

fn mag(v: Vec3) f32 {
    return @sqrt(dot(v, v));
}

fn norm(v: Vec3) Vec3 {
    return div(v, mag(v));
}

fn dot(a: Vec3, b: Vec3) f32 {
    const prod = a * b;
    return @reduce(.Add, prod);
}

fn mul(a: f32, x: Vec3) Vec3 {
    return x * @as(Vec3, @splat(a));
}

fn div(x: Vec3, a: f32) Vec3 {
    return mul(1.0 / a, x);
}

fn dist(a: Vec3, b: Vec3) f32 {
    return @abs(mag(a - b));
}

const Sphere = struct {
    const Self = @This();
    name: []const u8,
    center: Vec3,
    r: f32,
    color: Color,

    fn rayIntersect(self: Self, position: Vec3, ray: Vec3) f32 {
        const L = position - self.center;
        const a = dot(ray, ray);
        const b = 2 * dot(ray, L);
        const c = dot(L, L) - self.r * self.r;
        const discriminant = b * b - 4.0 * a * c;

        if (discriminant < 0) return -1;
        const sqrt_disc = @sqrt(discriminant);
        const t0 = (-b - sqrt_disc) / 2.0 * a;
        const t1 = (-b + sqrt_disc) / 2.0 * a;
        if (t0 > 0) return t0;
        if (t1 > 0) return t1;
        return -1;
    }
};

const Camera = struct {
    const Self = @This();
    position: Vec3,
    direction: Vec3,

    fn rayFromPixel(self: Self, x: i32, y: i32, width: i32, height: i32) Vec3 {
        _ = self;
        const dx = @as(f32, @floatFromInt(x - width)) / 2.0;
        const dy = @as(f32, @floatFromInt(y - height)) / 2.0;
        const dz = 20.0;
        return .{ dx, dy, dz };
    }
};

const Screen = struct {
    const Self = @This();
    const camera_up: Vec3 = .{ 0, 1, 0 };
    const camera_right: Vec3 = .{ 1, 0, 0 };
    width: f32,
    height: f32,
    focal_distance: f32,

    fn pixelToWorld(self: Self, x: usize, y: usize) Vec3 {
        const fx = @as(f32, @floatFromInt(x));
        const fy = @as(f32, @floatFromInt(y));
        const x_world = fx - self.width / 2.0;
        const y_world = self.height / 2.0 - fy;
        // This should probably actually be computed when creating the screen, relative to
        // camera.
        const z_world = -self.focal_distance;
        return .{ x_world, y_world, z_world };
    }

    fn rayFromCameraThroughPixel(self: Self, camera: Camera, x: f32, y: f32) Vec3 {
        const screen_center = camera.position + mul(self.focal_distance, camera.direction);
        const pixel_to_scene = screen_center + mul(x, camera_right) + mul(y, camera_up);
        const d = pixel_to_scene - camera.position;
        return norm(d);
    }
};

const Light = struct {
    const Self = @This();
    position: Vec3,
    color: Color,
    intensity: f32,
};

const Scene = struct {
    const Self = @This();

    const SphereIntersect = struct {
        sphere: Sphere,
        intersection: f32,
    };

    const PixelRow = struct {
        scene: *Scene,
        width: usize,
        y: usize,
        data: []Color,
    };

    camera: Camera,
    screen: Screen,
    light: Light,
    ambient_light: f32,
    spheres: std.ArrayList(Sphere),
    pool: *tp.ThreadPool,

    fn init(allocator: std.mem.Allocator, camera: Camera, screen: Screen, light: Light, ambient_light: f32) !Self {
        const thread_count = try std.Thread.getCpuCount();
        return .{
            .camera = camera,
            .screen = screen,
            .light = light,
            .ambient_light = ambient_light,
            .spheres = std.ArrayList(Sphere).init(allocator),
            .pool = try tp.ThreadPool.init(allocator, thread_count),
        };
    }

    fn deinit(self: Self) void {
        self.spheres.deinit();
        self.pool.deinit();
    }

    /// Projects the current scene state onto a newly allocated `Image`.
    fn project(self: *Self, allocator: std.mem.Allocator) !Image {
        const img_width: usize = @intFromFloat(self.screen.width);
        const img_height: usize = @intFromFloat(self.screen.height);
        var img_data = try allocator.alloc(Color, img_width * img_height);

        // Calculate each pixel.
        const pixel_calc_profile = Profiler.start();
        var rows = try allocator.alloc(PixelRow, img_height);
        defer allocator.free(rows);
        for (0..img_height) |y| {
            const row_i = y * img_width;
            rows[y] = PixelRow{
                .scene = self,
                .width = img_width,
                .y = y,
                .data = img_data[row_i..(row_i + img_width)],
            };
            try self.pool.submit(pixelTask, &rows[y]);
        }

        self.pool.waitForAll();
        std.debug.print("Pixel calculation took {d}s\n", .{pixel_calc_profile.end()});
        for (rows) |*row| {
            for (row.data, 0..) |_, x| {
                img_data[row.y * row.width + x] = row.data[x];
            }
        }

        return Image.init(img_width, img_height, img_data);
    }

    fn pixelTask(ctx: *anyopaque) void {
        var row: *PixelRow = @ptrCast(@alignCast(ctx));
        for (0..row.width) |col| {
            const color = row.scene.calculatePixel(col, row.y);
            row.data[col] = color;
        }
    }

    fn calculatePixel(self: Self, x: usize, y: usize) Color {
        const screen_coord = self.screen.pixelToWorld(x, y);
        const ray = self.screen.rayFromCameraThroughPixel(self.camera, screen_coord[0], screen_coord[1]);

        // Calculate closest sphere.
        var closest_intersect: f32 = -1;
        var closest_sphere: ?Sphere = null;
        for (self.spheres.items) |sphere| {
            const intersect = sphere.rayIntersect(self.camera.position, ray);
            if (intersect > 0 and (intersect < closest_intersect or closest_intersect < 0)) {
                closest_intersect = intersect;
                closest_sphere = sphere;
            }
        }

        // Set pixel color to color of closest sphere.
        const hit_point = mul(closest_intersect, ray) + self.camera.position;
        return if (closest_sphere) |sphere|
            sphere.color.addLighting(self.light).intensify(self.calculateLighting(hit_point, sphere))
        else
            Color.black();
    }

    fn calculateLighting(self: Self, hit_point: Vec3, sphere: Sphere) f32 {
        const normal = norm(hit_point - sphere.center);
        const ray_dir = norm(self.light.position - hit_point);
        const light_dist = dist(hit_point, self.light.position);

        // If ray hits another sphere, we're in shadow.
        for (self.spheres.items) |other_sphere| {
            // Don't intersect with ourself!
            if (std.mem.eql(u8, sphere.name, other_sphere.name)) continue;
            // If we hit another sphere, we have a shadow.
            const intersect = other_sphere.rayIntersect(hit_point, ray_dir);
            if (intersect > 0 and intersect < light_dist) return 0.0;
        }

        const diffuse = dot(ray_dir, normal);
        return self.ambient_light + diffuse * self.light.intensity;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const camera = Camera{
        .position = .{ 0, 0, -90 },
        .direction = .{ 0, 0, 1 },
    };

    const screen = Screen{
        .width = 1920,
        .height = 1080,
        .focal_distance = 416,
    };

    const overhead_light = Light{
        .position = .{ 0, 80, 0 },
        .color = Color.white(),
        .intensity = 1.0,
    };

    var scene = try Scene.init(allocator, camera, screen, overhead_light, 0.01);
    defer scene.deinit();

    try scene.spheres.append(Sphere{
        .name = "Sphere (Red)",
        .center = .{ 0, 30, 40 },
        .r = 20,
        .color = Color.rgb(255, 192, 203),
    });

    try scene.spheres.append(Sphere{
        .name = "Sphere (Blue)",
        .center = .{ -30, 20, 10 },
        .r = 10,
        .color = Color.rgb(144, 213, 255),
    });

    try scene.spheres.append(Sphere{
        .name = "Sphere (Green)",
        .center = .{ 0, -10, 0 },
        .r = 30,
        .color = Color.rgb(130, 135, 125),
    });

    const proj = try scene.project(allocator);
    defer allocator.free(proj.data);
    try proj.printP6();
}
