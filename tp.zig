const std = @import("std");

pub fn Ctx(comptime T: type) type {
    return struct {
        data: T,
    };
}

pub const Task = struct {
    operation: *const fn () void,
};

pub const ThreadPool = struct {
    const Self = @This();
    threads: []std.Thread,
    tasks: std.ArrayList(Task),
    mutex: std.Thread.Mutex,
    running: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, count: usize) !*Self {
        const pool = try allocator.create(Self);
        pool.* = Self{
            .threads = try allocator.alloc(std.Thread, count),
            .tasks = std.ArrayList(Task).init(allocator),
            .mutex = std.Thread.Mutex{},
            .running = true,
            .allocator = allocator,
        };

        for (pool.threads) |*thread| {
            thread.* = try std.Thread.spawn(.{}, worker, .{pool});
        }

        return pool;
    }

    pub fn deinit(self: *Self) void {
        self.mutex.lock();
        self.running = false;
        self.mutex.unlock();

        for (self.threads) |thread| {
            thread.join();
        }

        self.tasks.deinit();
        self.allocator.free(self.threads);
        self.allocator.destroy(self);
    }

    pub fn submit(self: *Self, operation: *const fn () void) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.running) return error.PoolClosed;
        try self.tasks.append(Task{ .operation = operation });
    }

    fn worker(pool: *Self) void {
        while (true) {
            var task: ?Task = null;
            pool.mutex.lock();
            task = pool.tasks.pop();

            if (!pool.running and task == null) {
                pool.mutex.unlock();
                return;
            }

            pool.mutex.unlock();
            if (task) |t| {
                t.operation();
            } else {
                std.time.sleep(1 * std.time.ns_per_ms);
            }
        }
    }
};

test "test some tasks" {
    const allocator = std.testing.allocator;
    const thread_count = try std.Thread.getCpuCount();
    var pool = try ThreadPool.init(allocator, thread_count);
    defer pool.deinit();
    std.debug.print("Started thread pool with {d} threads\n", .{thread_count});

    try pool.submit(task1);
    try pool.submit(task2);
    try pool.submit(task1);
    try pool.submit(task2);

    std.time.sleep(2 * std.time.ns_per_s);
    std.debug.print("Main thread done\n", .{});
}

fn task1() void {
    std.debug.print("Task 1 running on thread {d}\n", .{std.Thread.getCurrentId()});
    std.time.sleep(500 * std.time.ns_per_ms);
}

fn task2() void {
    std.debug.print("Task 2 running on thread {d}\n", .{std.Thread.getCurrentId()});
    std.time.sleep(300 * std.time.ns_per_ms);
}
