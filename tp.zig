const std = @import("std");

pub const Task = struct {
    const Self = @This();
    operation: *const fn (ctx: *anyopaque) void,
    ctx: *anyopaque,

    pub fn run(self: *const Self) void {
        self.operation(self.ctx);
    }
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

        self.tasks.deinit();
        self.allocator.free(self.threads);
        self.allocator.destroy(self);
    }

    pub fn waitForAll(self: *Self) void {
        self.mutex.lock();
        self.running = false;
        self.mutex.unlock();

        for (self.threads) |thread| {
            thread.join();
        }
    }

    pub fn submit(self: *Self, operation: *const fn (*anyopaque) void, ctx: *anyopaque) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.running) return error.PoolClosed;
        try self.tasks.append(Task{
            .operation = operation,
            .ctx = ctx,
        });
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
                t.run();
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

    const results = try allocator.alloc(Result, 4);
    defer allocator.free(results);

    try pool.submit(task1, &results[0]);
    try pool.submit(task2, &results[1]);
    try pool.submit(task1, &results[2]);
    try pool.submit(task2, &results[3]);

    pool.waitForAll();

    for (results, 0..) |result, i| {
        std.debug.print("Task {d} yielded {d}\n", .{ i, result.value });
    }

    std.debug.print("Main thread done\n", .{});
}

const Result = struct {
    const Self = @This();
    value: i32,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) !*Self {
        return allocator.create(Self);
    }

    fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }
};

fn task1(ctx: *anyopaque) void {
    const result: *Result = @ptrCast(@alignCast(ctx));
    std.debug.print("Task 1 running on thread {d}\n", .{std.Thread.getCurrentId()});
    std.time.sleep(500 * std.time.ns_per_ms);
    result.value = 5;
}

fn task2(ctx: *anyopaque) void {
    const result: *Result = @ptrCast(@alignCast(ctx));
    std.debug.print("Task 2 running on thread {d}\n", .{std.Thread.getCurrentId()});
    std.time.sleep(300 * std.time.ns_per_ms);
    result.value = 3;
}
