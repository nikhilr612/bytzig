//! A simple BytePusher emulator written in Zig.

const std = @import("std");
const emu = @import("impl.zig");

pub fn main() !void {
    const a = std.heap.page_allocator;
    var vm = try emu.createVm(a); // The rare case when page allocator actually helps since memory size is large.
    // vm.zeroset(); // For now.
    try vm.loadFile("PaletteTest.BytePusher");
    defer vm.deinit(a);
    try emu.run(&vm);
}
