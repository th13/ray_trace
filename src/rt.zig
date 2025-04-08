const std = @import("std");
const stdout = std.io.getStdOut().writer();
const debug = std.debug;
const math = std.math;
const expect = std.testing.expect;
const tp = @import("tp.zig");

pub const Profiler = struct {
    const Self = @This();
    start_ns: i128,

    pub fn start() Profiler {
        return .{ .start_ns = std.time.nanoTimestamp() };
    }

    pub fn end(self: *const Self) f64 {
        const elapsed_ns = std.time.nanoTimestamp() - self.start_ns;
        return @as(f64, @floatFromInt(elapsed_ns)) / 1e9;
    }
};

pub const Color = struct {
    const Self = @This();
    intensities: Vec3,

    pub fn rgb(red: u8, green: u8, blue: u8) Self {
        return .{ .intensities = .{
            Self.byteToIntensity(red),
            Self.byteToIntensity(green),
            Self.byteToIntensity(blue),
        } };
    }

    pub fn black() Self {
        return .{ .intensities = .{ 0, 0, 0 } };
    }

    pub fn white() Self {
        return .{ .intensities = .{ 1, 1, 1 } };
    }

    pub fn intensify(self: Self, intensity: f32) Self {
        return .{ .intensities = mul(intensity, self.intensities) };
    }

    pub fn addLighting(self: Self, light: Light) Self {
        const blend = self.intensities * light.color.intensities;
        return .{ .intensities = mul(light.intensity, blend) };
    }

    pub fn print(self: Self) !void {
        try stdout.writeByte(self.r());
        try stdout.writeByte(self.g());
        try stdout.writeByte(self.b());
    }

    pub fn printFmt(self: Self) void {
        std.debug.print("({d}, {d}, {d})", .{ self.r(), self.g(), self.b() });
    }

    pub fn r(self: Self) u8 {
        return Self.intensityToByte(self.intensities[0]);
    }

    pub fn g(self: Self) u8 {
        return Self.intensityToByte(self.intensities[1]);
    }

    pub fn b(self: Self) u8 {
        return Self.intensityToByte(self.intensities[2]);
    }

    pub fn intensityToByte(intensity: f32) u8 {
        const clamped = @max(0.0, @min(1.0, intensity));
        return @as(u8, @intFromFloat(clamped * 255.0));
    }

    pub fn byteToIntensity(byte: u8) f32 {
        const scaled: f32 = @as(f32, @floatFromInt(byte)) / 255.0;
        return @max(0, @min(1.0, scaled));
    }
};

pub const Image = struct {
    const Self = @This();
    width: usize,
    height: usize,
    data: []Color,

    pub fn init(width: usize, height: usize, data: []Color) Self {
        return .{ .width = width, .height = height, .data = data };
    }

    pub fn printBinary(self: Self) !void {
        for (0..self.height * self.width) |i| {
            try self.data[i].print();
        }
    }

    pub fn printP6(self: Self) !void {
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

pub const Vec3 = @Vector(3, f32);

pub fn mag(v: Vec3) f32 {
    return @sqrt(dot(v, v));
}

pub fn norm(v: Vec3) Vec3 {
    return div(v, mag(v));
}

pub fn dot(a: Vec3, b: Vec3) f32 {
    const prod = a * b;
    return @reduce(.Add, prod);
}

pub fn mul(a: f32, x: Vec3) Vec3 {
    return x * @as(Vec3, @splat(a));
}

pub fn div(x: Vec3, a: f32) Vec3 {
    return mul(1.0 / a, x);
}

pub fn dist(a: Vec3, b: Vec3) f32 {
    return @abs(mag(a - b));
}

pub const Sphere = struct {
    const Self = @This();
    name: []const u8,
    center: Vec3,
    r: f32,
    color: Color,

    pub fn rayIntersect(self: Self, position: Vec3, ray: Vec3) f32 {
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

pub const Camera = struct {
    const Self = @This();
    position: Vec3,
    direction: Vec3,

    pub fn rayFromPixel(self: Self, x: i32, y: i32, width: i32, height: i32) Vec3 {
        _ = self;
        const dx = @as(f32, @floatFromInt(x - width)) / 2.0;
        const dy = @as(f32, @floatFromInt(y - height)) / 2.0;
        const dz = 20.0;
        return .{ dx, dy, dz };
    }
};

pub const Screen = struct {
    const Self = @This();
    const camera_up: Vec3 = .{ 0, 1, 0 };
    const camera_right: Vec3 = .{ 1, 0, 0 };
    width: f32,
    height: f32,
    focal_distance: f32,

    pub fn pixelToWorld(self: Self, x: f32, y: f32) Vec3 {
        const x_world = x - self.width / 2.0;
        const y_world = self.height / 2.0 - y;
        // This should probably actually be computed when creating the screen, relative to
        // camera.
        const z_world = -self.focal_distance;
        return .{ x_world, y_world, z_world };
    }

    pub fn rayFromCameraThroughPixel(self: Self, camera: Camera, x: f32, y: f32) Vec3 {
        const screen_center = camera.position + mul(self.focal_distance, camera.direction);
        const pixel_to_scene = screen_center + mul(x, camera_right) + mul(y, camera_up);
        const d = pixel_to_scene - camera.position;
        return norm(d);
    }
};

pub const Light = struct {
    const Self = @This();
    position: Vec3,
    color: Color,
    intensity: f32,
};

pub const SceneConfig = struct {
    ambient_light: f32,
    enable_antialiasing: bool,
};

pub const Scene = struct {
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
    config: SceneConfig,
    spheres: std.ArrayList(Sphere),
    pool: *tp.ThreadPool,
    rand: std.Random,

    pub fn init(allocator: std.mem.Allocator, prng: *std.Random.DefaultPrng, camera: Camera, screen: Screen, light: Light, scene_config: SceneConfig) !Self {
        const thread_count = try std.Thread.getCpuCount();

        return .{
            .camera = camera,
            .screen = screen,
            .light = light,
            .config = scene_config,
            .spheres = std.ArrayList(Sphere).init(allocator),
            .pool = try tp.ThreadPool.init(allocator, thread_count),
            .rand = prng.random(),
        };
    }

    pub fn deinit(self: Self) void {
        self.spheres.deinit();
        self.pool.deinit();
    }

    /// Projects the current scene state onto a newly allocated `Image`.
    pub fn project(self: *Self, allocator: std.mem.Allocator) !Image {
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

    pub fn pixelTask(ctx: *anyopaque) void {
        var row: *PixelRow = @ptrCast(@alignCast(ctx));
        for (0..row.width) |x| {
            const fx = @as(f32, @floatFromInt(x));
            const fy = @as(f32, @floatFromInt(row.y));

            // Get first sample
            var blend = row.scene.samplePoint(fx, fy);

            // Apply antialiasing if enabled
            if (row.scene.config.enable_antialiasing) {
                const offsets = [2]f32{ -0.25, 0.25 };
                for (offsets) |offset_x| {
                    for (offsets) |offset_y| {
                        blend.intensities += row.scene.samplePoint(fx + offset_x, fy + offset_y).intensities;
                    }
                }
                blend = Color{ .intensities = div(blend.intensities, 4.0) };
            }

            row.data[x] = blend;
        }
    }

    /// Samples a random point in the square bounded by -0.5<=(x-i)<=0.5, -0.5<=(y-j)<=0.5
    pub fn samplePoint(self: Self, x: f32, y: f32) Color {
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

    pub fn calculateLighting(self: Self, hit_point: Vec3, sphere: Sphere) f32 {
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
        return self.config.ambient_light + diffuse * self.light.intensity;
    }
};
