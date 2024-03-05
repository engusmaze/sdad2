const std = @import("std");
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const allocator = std.heap.page_allocator;

const reserved = [_]u8{ ' ', '\t', '\r', '\n', '\x0B', '\x0C', '{', '}', '=', '#' };
pub const Parser = struct {
    ptr: [*]const u8,
    end: [*]const u8,

    const Self = @This();
    pub fn new(bytes: []const u8) Self {
        return Self{
            .ptr = bytes.ptr,
            .end = bytes.ptr + bytes.len,
        };
    }
    inline fn read(self: *Self) ?u8 {
        if (@intFromPtr(self.ptr) < @intFromPtr(self.end)) {
            return self.ptr[0];
        } else {
            return null;
        }
    }
    inline fn next(self: *Self) void {
        self.ptr += 1;
    }
    fn skip_unused(self: *Self) void {
        while (self.read()) |char| : (self.next()) {
            switch (char) {
                ' ', '\t', '\r', '\n', '\x0B', '\x0C' => {},
                '#' => while (self.read()) |inner| {
                    self.next();
                    if (inner == '\n') break;
                },
                else => break,
            }
        }
    }
    fn parse_char(self: *Self, comptime match: u8) ?void {
        self.skip_unused();
        if (self.read()) |char| {
            self.next();
            return if (char == match) {} else null;
        }
    }
    fn parse_ident(self: *Self) ?[]const u8 {
        self.skip_unused();
        const start = self.ptr;

        chars: while (self.read()) |char| : (self.next())
            for (reserved) |space|
                if (char == space)
                    break :chars;

        if (self.ptr == start) {
            return null;
        } else {
            return start[0 .. @intFromPtr(self.ptr) - @intFromPtr(start)];
        }
    }
    fn parse_string(self: *Self) !?[]const u8 {
        self.parse_char('"') orelse return null;
        const start = self.ptr;

        var array = ArrayListUnmanaged(u8){};
        while (self.read()) |char| {
            self.next();
            switch (char) {
                '"' => break,
                else => try array.append(allocator, char),
            }
        }

        if (self.ptr == start) {
            return null;
        } else {
            return start[0 .. @intFromPtr(self.ptr) - 1 - @intFromPtr(start)];
        }
    }
    fn parse_array(self: *Self, comptime T: type) !?[]T {
        self.parse_char('{') orelse return null;

        var array = ArrayListUnmanaged(T){};
        while (self.parse(T)) |value| try array.append(allocator, value);

        self.parse_char('}') orelse return null;
        return try array.toOwnedSlice(allocator);
    }
    fn parse_struct(self: *Self, comptime T: type) !?T {
        self.parse_char('{') orelse return null;

        var value: T = undefined;
        inline for (std.meta.fields(T)) |field| {
            const field_ident = self.parse_ident() orelse return null;
            if (std.mem.eql(u8, field_ident, field.name)) {
                self.parse_char('=') orelse return null;
                @field(value, field.name) = try self.parse(field.type) orelse return null;
            }
        }
        self.parse_char('}') orelse return null;
        return value;
    }
    fn parse_union(self: *Self, comptime T: type) !?T {
        var value: T = undefined;
        const union_ident = self.parse_ident() orelse return null;
        self.parse_char('=') orelse return null;
        inline for (std.meta.fields(T)) |field| {
            if (std.mem.eql(u8, union_ident, field.name)) {
                @field(value, field.name) = try self.parse(field.type) orelse return null;
            }
        }
        return value;
    }
    fn parse_enum(self: *Self, comptime T: type) ?T {
        const union_ident = self.parse_ident() orelse return null;
        inline for (std.meta.fields(T)) |field| {
            if (std.mem.eql(u8, union_ident, field.name)) {
                return @field(T, field.name);
            }
        }
        return null;
    }
    pub fn parse(self: *Self, comptime T: type) !?T {
        switch (@typeInfo(T)) {
            // .Array => |array| {
            //     if (T == []const u8) {
            //         return self.parse_ident();
            //     }

            //     @compileLog(std.fmt.comptimePrint("type: {}", .{array.child}));

            //     return null;
            // },
            .Pointer => |ptr| {
                if (ptr.size == .Slice) {
                    if (ptr.child == u8) {
                        return try self.parse_string() orelse return null;
                    } else {
                        return self.parse_array(ptr.child);
                    }
                }
                // @compileLog(std.fmt.comptimePrint("type: {}", .{ptr}));
            },
            .Struct => return self.parse_struct(T),
            .Union => return self.parse_union(T),
            .Enum => return self.parse_enum(T),
            else => {},
        }
        @compileError(std.fmt.comptimePrint("Unsopported type: {any}", .{T}));
    }
};
