const std = @import("std");
const stdout = std.io.getStdOut().writer();
const debug = std.debug;
const math = std.math;
const expect = std.testing.expect;

const Color = struct {
    const Self = @This();
    r: u8,
    g: u8,
    b: u8,

    fn rgb(r: u8, g: u8, b: u8) Self {
        return .{ .r = r, .g = g, .b = b };
    }

    fn black() Self {
        return .{ .r = 0, .g = 0, .b = 0 };
    }

    fn white() Self {
        return .{ .r = 255, .g = 255, .b = 255 };
    }

    fn print(self: Self) !void {
        try stdout.writeByte(self.r);
        try stdout.writeByte(self.g);
        try stdout.writeByte(self.b);
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
            const px = self.data[i];
            try px.print();
        }
    }

    fn printP6(self: Self) !void {
        try stdout.print("P6\n{d} {d}\n255\n", .{ self.width, self.height });
        try self.printBinary();
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

const Sphere = struct {
    const Self = @This();
    name: []const u8,
    center: Vec3,
    r: f32,
    color: Color,

    fn rayIntersect(self: Self, camera: Camera, ray: Vec3) f32 {
        const L = camera.position - self.center;
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

const Scene = struct {
    const Self = @This();
    const SphereIntersect = struct {
        sphere: Sphere,
        intersection: f32,
    };
    camera: Camera,
    screen: Screen,
    spheres: []Sphere,

    /// Projects the current scene state onto a newly allocated `Image`.
    fn project(self: Self, allocator: std.mem.Allocator) !Image {
        const img_width: usize = @intFromFloat(self.screen.width);
        const img_height: usize = @intFromFloat(self.screen.height);
        var img_data = try allocator.alloc(Color, img_width * img_height);

        // Calculate each pixel.
        for (0..img_height) |y| {
            for (0..img_width) |x| {
                const screen_coord = self.screen.pixelToWorld(x, y);
                const ray = self.screen.rayFromCameraThroughPixel(self.camera, screen_coord[0], screen_coord[1]);

                // Calculate closest sphere.
                var closest_intersect: f32 = -1;
                var closest_sphere: ?Sphere = null;
                for (self.spheres) |sphere| {
                    const intersect = sphere.rayIntersect(self.camera, ray);
                    if (intersect > 0 and (intersect < closest_intersect or closest_intersect < 0)) {
                        closest_intersect = intersect;
                        closest_sphere = sphere;
                    }
                }

                // Set pixel color to color of closest sphere.
                const index = y * img_width + x;
                img_data[index] = if (closest_sphere) |sphere|
                    sphere.color
                else
                    Color.black();
            }
        }

        return Image.init(img_width, img_height, img_data);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const sphere = Sphere{
        .name = "Sphere (Pink)",
        .center = .{ 0, 40, 20 },
        .r = 20,
        .color = Color.rgb(234, 89, 187),
    };

    const sphere_blue = Sphere{
        .name = "Sphere (Blue)",
        .center = .{ -20, 40, 0 },
        .r = 10,
        .color = Color.rgb(10, 20, 180),
    };

    const camera = Camera{
        .position = .{ 0, 0, -90 },
        .direction = .{ 0, 0, 1 },
    };

    const screen = Screen{
        .width = 640,
        .height = 480,
        .focal_distance = 416,
    };

    const spheres = try allocator.alloc(Sphere, 2);
    defer allocator.free(spheres);
    spheres[0] = sphere;
    spheres[1] = sphere_blue;

    const scene = Scene{
        .camera = camera,
        .screen = screen,
        .spheres = spheres,
    };

    const proj = try scene.project(allocator);
    defer allocator.free(proj.data);
    try proj.printP6();

    //const proj = try project(allocator, camera, screen, sphere, sphere_blue);
    //defer allocator.free(proj.data);
    //try proj.printP6();
}
