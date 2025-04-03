const std = @import("std");
const stdout = std.io.getStdOut().writer();
const debug = std.debug;
const math = std.math;
const expect = std.testing.expect;

const Pixel = struct {
    const Self = @This();
    r: u8,
    g: u8,
    b: u8,
    fn print(self: Self) !void {
        try stdout.writeByte(self.r);
        try stdout.writeByte(self.g);
        try stdout.writeByte(self.b);
    }

    fn black() Self {
        return .{ .r = 0, .g = 0, .b = 0 };
    }

    fn white() Self {
        return .{ .r = 255, .g = 255, .b = 255 };
    }
};

const Image = struct {
    const Self = @This();
    width: usize,
    height: usize,
    data: []Pixel,

    fn init(width: usize, height: usize, data: []Pixel) Self {
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

fn makeCenterCircle(allocator: std.mem.Allocator, width: usize, height: usize, r: usize) ![]Pixel {
    var img: []Pixel = try allocator.alloc(Pixel, width * height);
    const iheight: i64 = @intCast(height / 2);
    const iwidth: i64 = @intCast(width / 2);
    for (0..height) |y| {
        for (0..width) |x| {
            const iy: i64 = @intCast(y);
            const ix: i64 = @intCast(x);
            const dy = iy - iheight;
            const dx = ix - iwidth;
            const index = y * width + x;
            if (dx * dx + dy * dy > r * r) {
                img[index] = Pixel.white();
            } else {
                img[index] = Pixel.black();
            }
        }
    }
    return img;
}

//------------------------------------------------------------
//  Sphere
//------------------------------------------------------------

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
    center: Vec3,
    r: f32,
    color: Pixel,

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

fn project(allocator: std.mem.Allocator, camera: Camera, screen: Screen, sphere: Sphere, sphere2: Sphere) !Image {
    const img_width: usize = @intFromFloat(screen.width);
    const img_height: usize = @intFromFloat(screen.height);
    var data = try allocator.alloc(Pixel, img_width * img_height);
    for (0..img_height) |y| {
        for (0..img_width) |x| {
            const screen_coord = screen.pixelToWorld(x, y);
            const ray = screen.rayFromCameraThroughPixel(camera, screen_coord[0], screen_coord[1]);
            const index = y * img_width + x;
            const sphere_intersect = sphere.rayIntersect(camera, ray);
            const sphere2_intersect = sphere2.rayIntersect(camera, ray);

            // @todo this logic is probably horribly naive and won't scale well to additional
            // spheres, but will explore later.
            const use_sphere_color = sphere_intersect >= 0 and (sphere2_intersect < 0 or sphere2_intersect >= 0 and sphere_intersect > sphere2_intersect);
            const use_sphere2_color = !use_sphere_color and sphere2_intersect >= 0;

            const color = if (use_sphere_color)
                sphere.color
            else if (use_sphere2_color)
                sphere2.color
            else
                Pixel.black();

            data[index] = color;
        }
    }
    return Image.init(@intFromFloat(screen.width), @intFromFloat(screen.height), data);
}
//------------------------------------------------------------

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const sphere = Sphere{
        .center = .{ 0, 40, 0 },
        .r = 20,
        .color = .{ .r = 234, .g = 89, .b = 187 },
    };

    const sphere_blue = Sphere{
        .center = .{ -70, -10, 0 },
        .r = 20,
        .color = .{ .r = 10, .g = 20, .b = 180 },
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

    const proj = try project(allocator, camera, screen, sphere, sphere_blue);
    defer allocator.free(proj.data);
    try proj.printP6();
}
