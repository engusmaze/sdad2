const std = @import("std");
const sdad = @import("sdad");

const allocator = std.heap.page_allocator;

const YN = enum { y, n };
const Guy = struct { is_gay: YN };

pub fn main() !void {
    var parser = sdad.Parser.new("{ is_gay = y }");
    const guy = try parser.parse(Guy) orelse
        std.debug.panic("Cock & Balls", .{});
    std.debug.print("{}\n", .{guy});
}
