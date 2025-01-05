const std = @import("std");
const assert = std.debug.assert;
const math = std.math;

/// Represents an integer that can have a runtime-known number of bits,
/// implemented with a `comptime`-known backing integer type.
/// Operations will automatically be adjusted so that the result will
/// fit in an `n`-bit number casted via `@intCast`. All "checked" arithmetic
pub fn VariableInt(comptime BackingInt: type) type {
    switch (@typeInfo(BackingInt)) {
        .int => |info| if (info.bits == 0)
            @compileError("VariableInt may not have a backing integer of '" ++ @typeName(BackingInt) ++ "'"),
        else => @compileError("BackingInt of VariableInt must be an integer type"),
    }
    return struct {
        pub const BitsInt = std.math.Log2Int(BackingInt);
        const is_signed = @typeInfo(BackingInt).int.signedness == .signed;

        /// The number of bits that should be used for arithmetic.
        /// It is assumed that this value will not change after initialization;
        /// modifying it may result in unexpected behavior.
        bits: BitsInt,
        value: BackingInt = 0,

        const Self = @This();

        pub fn init(bits: BitsInt) Self {
            return .{
                .bits = bits,
            };
        }

        pub fn set(self: *Self, value: BackingInt) bool {
            if (value > maxValue(self.bits) or value < minValue(self.bits))
                return false;
            self.value = value;
            return true;
        }

        pub fn to(self: *Self, comptime T: type) ?T {
            return math.cast(T, self.value);
        }

        fn maxValue(bits: BitsInt) BackingInt {
            return if (bits == 0)
                0
            else
                (@as(BackingInt, 1) << (bits - @intFromBool(is_signed))) - 1;
        }

        fn minValue(bits: BitsInt) BackingInt {
            return if (bits == 0 or !is_signed)
                0
            else
                -@as(BackingInt, 1) << (bits - 1);
        }

        pub fn addWrap(self: *Self, rhs: BackingInt) void {
            _ = self.addWithOverflow(rhs);
        }

        pub fn subWrap(self: *Self, rhs: BackingInt) void {
            _ = self.subWithOverflow(rhs);
        }

        pub fn add(self: *Self, rhs: BackingInt) void {
            assert(!self.addWithOverflow(rhs));
        }

        pub fn sub(self: *Self, rhs: BackingInt) void {
            assert(!self.subWithOverflow(rhs));
        }

        pub fn div(self: *Self, rhs: BackingInt) void {
            assertInRange(self.bits, rhs);
            self.value /= rhs;
        }

        pub fn rem(self: *Self, rhs: BackingInt) void {
            assertInRange(self.bits, rhs);
            self.value = @rem(self.value, rhs);
        }

        pub fn mod(self: *Self, rhs: BackingInt) void {
            assertInRange(self.bits, rhs);
            self.value = @rem(self.value, rhs);
        }

        pub fn shl(self: *Self, shift: BitsInt) void {
            _ = self.shlWithOverflow(shift);
        }

        pub fn addWithOverflow(self: *Self, rhs: BackingInt) bool {
            assertInRange(self.bits, rhs);
            if (self.bits == @bitSizeOf(BackingInt)) {
                // we can just do a plain `@addWithOverflow` in this case
                const result, const overflow = @addWithOverflow(self.value, rhs);
                self.value = result;
                return overflow;
            }
            const overflow, const val = adjustInt(self.value + rhs, self.bits);
            self.value = val;
            return overflow;
        }

        pub fn subWithOverflow(self: *Self, rhs: BackingInt) bool {
            assertInRange(self.bits, rhs);
            if (self.bits == @bitSizeOf(BackingInt)) {
                // we can just do a plain `@subWithOverflow` in this case
                const result, const overflow = @subWithOverflow(self.value, rhs);
                self.value = result;
                return overflow;
            }
            const overflow, const val = adjustInt(self.value - rhs, self.bits);
            self.value = val;
            return overflow;
        }

        pub fn mulWithOverflow(self: *Self, rhs: BackingInt) bool {
            assertInRange(self.bits, rhs);
            const result, const overflow = @mulWithOverflow(self.value, rhs);
            if (overflow == 1) {
                self.value = adjustInt(result, self.bits)[1];
                return true;
            } else {
                const adjusted, const actual_result = adjustInt(result, self.bits);
                self.value = actual_result;
                return adjusted;
            }
        }

        pub fn shlWithOverflow(self: *Self, rhs: BitsInt) bool {
            if (rhs >= self.bits) {
                self.value = 0;
                return true;
            }
            const result, const overflow = @shlWithOverflow(self.value, rhs);
            const adjusted, const real_result = adjustInt(result, self.bits);
            self.value = real_result;
            return overflow == 1 or adjusted;
        }

        pub fn shr(self: *Self, rhs: BitsInt) void {
            if (rhs >= self.bits) {
                self.value = 0;
                return true;
            }
            if (is_signed) {
                self.value = adjustInt(self.value, self.bits)[1] >> self.bits;
            } else {
                self.value >>= self.bits;
            }
        }

        pub fn bitAnd(self: *Self, rhs: BackingInt) void {
            assertInRange(self.bits, rhs);
            self.value &= rhs;
        }

        pub fn bitOr(self: *Self, rhs: BackingInt) void {
            assertInRange(self.bits, rhs);
            self.value |= rhs;
        }

        pub fn bitXor(self: *Self, rhs: BackingInt) void {
            assertInRange(self.bits, rhs);
            self.value |= rhs;
        }

        pub fn bitNot(self: *Self) void {
            self.value ^= (@as(BackingInt, 1) << self.bits) - 1;
        }

        /// Returns `.{ true, <result> }` if the integer
        /// was adjusted and `.{ false, <result> }` if it was not.
        fn adjustInt(val: BackingInt, bits: BitsInt) struct { bool, BackingInt } {
            const max = maxValue(bits);
            const min = minValue(bits);

            if (val > max) {
                if (is_signed) {
                    const mask = (@as(BackingInt, 1) << bits) - 1;
                    var result = val & mask;
                    if (val & (@as(BackingInt, 1) << (bits - 1)) != 0) {
                        result |= ~mask;
                    }
                    return .{ true, result };
                } else {
                    return .{ true, val & max };
                }
            } else if (is_signed) {
                if (val < min) {
                    const mask = (@as(BackingInt, 1) << bits) - 1;
                    var result = val & mask;
                    if (val & (@as(BackingInt, 1) << (bits - 1)) != 0) {
                        result |= ~mask;
                    }
                    return .{ true, result };
                }
            }
            return .{ false, val };
        }

        pub fn negate(self: *Self) void {
            comptime assert(is_signed);
            self.value = -self.value;
        }

        inline fn assertInRange(bits: BitsInt, val: BackingInt) void {
            if (std.debug.runtime_safety) {
                const max = maxValue(bits);
                const min = minValue(bits);
                assert(val <= max and val >= min);
            }
        }
    };
}
