//! Layout constraints (placeholder)
const std = @import("std");

pub const Direction = enum {
    horizontal,
    vertical,
};

pub const Constraint = enum {
    length,
    percentage,
    ratio,
    min,
    max,
};
