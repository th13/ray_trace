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
                img[index] = .{ .r = 0, .b = 0, .g = 0 };
            } else {
                img[index] = .{ .r = 144, .b = 132, .g = 89 };
            }
        }
    }
    return img;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const width = 1920;
    const height = 1080;
    const r = 250;

    const circle = try makeCenterCircle(allocator, width, height, r);
    defer allocator.free(circle);

    const circleImg = Image.init(width, height, circle);
    try circleImg.printP6();
}
