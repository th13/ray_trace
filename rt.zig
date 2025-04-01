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

fn dot(a: Vec3, b: Vec3) f32 {
    const prod = a * b;
    return @reduce(.Add, prod);
}

fn mul(a: f32, x: Vec3) Vec3 {
    return x * @as(Vec3, @splat(a));
}

const Sphere = struct {
    const Self = @This();
    center: Vec3,
    r: f32,

    fn rayIntersect(self: Self, camera: Camera, ray: Vec3) ?f32 {
        const L = camera.position - self.center;
        const a = dot(ray, ray);
        const b = 2 * dot(ray, L);
        const c = dot(L, L) - self.r * self.r;
        const discriminant = b * b - 4.0 * a * c;

        if (discriminant < 0) return null;
        const sqrt_disc = @sqrt(discriminant);
        const t0 = (-b - sqrt_disc) / 2.0 * a;
        const t1 = (-b + sqrt_disc) / 2.0 * a;
        if (t0 > 0) return t0;
        if (t1 > 0) return t1;
        return null;
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

fn project(allocator: std.mem.Allocator, sphere: Sphere, camera: Camera, width: usize, height: usize) !Image {
    var data = try allocator.alloc(Pixel, width * height);
    for (0..height) |y| {
        for (0..width) |x| {
            const ix: i32 = @intCast(x);
            const iy: i32 = @intCast(y);
            const ray = camera.rayFromPixel(ix, iy, @intCast(width), @intCast(height));
            const index = y * width + x;
            if (sphere.rayIntersect(camera, ray)) |dist| {
                std.debug.print("ray intersected at dist = {d:.2}", .{dist});
                data[index] = Pixel.black();
            } else {
                data[index] = Pixel.white();
            }
            debug.print("({d}, {d}) = {d}\n", .{ x, y, data[index].r });
        }
    }
    return Image.init(width, height, data);
}

//------------------------------------------------------------

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const width = 64;
    const height = 48;
    const r = 5;

    // const circle = try makeCenterCircle(allocator, width, height, r);
    // defer allocator.free(circle);

    // const circleImg = Image.init(width, height, circle);
    // try circleImg.printP6();

    const sphere = Sphere{
        .center = .{ 0, 0, 0 },
        .r = r,
    };

    const camera = Camera{
        .position = .{ 0, 0, -20 },
        .direction = .{ 0, 0, 0 },
    };

    const proj = try project(allocator, sphere, camera, width, height);
    defer allocator.free(proj.data);
    try proj.printP6();
}
