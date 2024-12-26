//! The BytePusher VM has the following specs:
//! Framerate:
//!		60 frames per second.
//!	CPU Speed:
//!		65536 instructions per frame.
//! Graphics:
//!		8-bit, 256*256 pixels.
//! Audio:
//!		8-bit mono, 256 samples per frame.
//! Keyboard:
//!		16 keys - 0,1,...,9,A,B,C,D,E,F (hexdigits)
//! Memory:
//!		The VM has a memory of 16777216 bytes.
//!		This being larger than 65535, requires 3 bytes for addressing.
//! Instruction Set:
//! 	BytePusher uses only a single instrcution, i.e, ByteByteJump.
//! 	The ByteByteJump is a 9-byte, 3-operand instruction of the form ABC.
//! 	The instruction copies data from A->B, and jumps to C.

const sdl = @import("uzsdl.zig");
const std = @import("std");

/// Display window size.
const WINDOW_WIDTH = 768;
const WINDOW_HEIGHT = 768;

/// Virtual window size.
const SCREEN_WIDTH = 256;
const SCREEN_HEIGHT = 256;

const MEMORY_SIZE = 16777216;
const INSTR_COUNT = 65536;

const FPS = 60;

const PIXEL_WIDTH = WINDOW_WIDTH / SCREEN_WIDTH;
const PIXEL_HEIGHT = WINDOW_HEIGHT / SCREEN_HEIGHT;

const SAMPLE_FREQUENCY = 15360;
const SAMPLE_COUNT = 256;

const MSPF = 1000 / FPS;

const Allocator = std.mem.Allocator;

const VmError = error{
    InvalidIp,
    InvalidAddr,
};

fn u24_from_u8(v0: u8, v1: u8, v2: u8) u24 {
    var ret: u24 = v0;
    ret <<= 8;
    ret |= v1;
    ret <<= 8;
    ret |= v2;
    return ret;
}

const Vm = struct {
    ip: usize,
    m: []u8,

    /// Free VM memory.
    pub fn deinit(self: *Vm, alloca: Allocator) void {
        alloca.free(self.m);
    }

    /// Set the entire memory of VM to zero.
    pub fn zeroset(self: *Vm) void {
        @memset(self.m, 0);
    }

    /// Open a file for reading, and transfer its contents into memory.
    pub fn loadFile(self: *Vm, path: [:0]const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const bytes_read = try file.readAll(self.m);
        for (bytes_read..MEMORY_SIZE) |i| {
            self.m[i] = 0;
        }
    }

    /// Reset instruction pointer by reading from offset 2.
    fn resetIp(self: *Vm) void {
        self.ip = u24_from_u8(self.m[2], self.m[3], self.m[4]);
    }

    /// Execute a single instruction pointed to by the instruction pointer.
    /// The instruction is Byte-Byte-Jump: A B C (9 bytes).
    /// Roughly:
    ///     mov A, B
    ///     jmp C
    pub fn execute(self: *Vm) VmError!void {
        // Verify instruction and operands before executing.
        if (self.ip + 9 > MEMORY_SIZE) return VmError.InvalidIp;
        // Read the addresses
        const addr1 = u24_from_u8(self.m[self.ip], self.m[self.ip + 1], self.m[self.ip + 2]);
        if (addr1 >= MEMORY_SIZE) return VmError.InvalidAddr;

        const addr2 = u24_from_u8(self.m[self.ip + 3], self.m[self.ip + 4], self.m[self.ip + 5]);
        if (addr2 >= MEMORY_SIZE) return VmError.InvalidAddr;

        const addr3 = u24_from_u8(self.m[self.ip + 6], self.m[self.ip + 7], self.m[self.ip + 8]);
        if (addr3 >= MEMORY_SIZE) return VmError.InvalidAddr;

        // Copy data from addr1 to addr2.
        self.m[addr2] = self.m[addr1];
        self.ip = addr3; // Move instruction pointer.
    }

    /// From the given array of bools representing the state of keys,
    /// create the corresponding bitflags and write them into address 0.
    pub fn setInputFlags(self: *Vm, input: [16]bool) void {
        var bitflags: u16 = 0;
        for (input) |flag| {
            bitflags <<= 1;
            bitflags |= if (flag) 1 else 0;
        }
        self.m[0] = @as(u8, @intCast((bitflags & 0xff00) >> 8));
        self.m[1] = @intCast(bitflags & 0xff);
    }

    /// Get the memory address for the start of pixel data.
    fn getPixelDataStart(self: *const Vm) usize {
        const ret: usize = self.m[5];
        return (ret << 16);
    }

    /// Get the current audio buffer.
    fn getAudioBuffer(self: *const Vm) []const u8 {
        var loc: usize = self.m[6];
        loc <<= 8;
        loc |= self.m[7];
        loc <<= 8;
        return self.m[loc..(loc + SAMPLE_COUNT)];
    }
};

pub fn createVm(alloca: Allocator) !Vm {
    return Vm{ .ip = 0, .m = try alloca.alloc(u8, MEMORY_SIZE) };
}

pub fn run(vm: *Vm) !void {
    try sdl.initAll();
    defer sdl.quit();

    const window = try sdl.createWindow("Bytzig", WINDOW_WIDTH, WINDOW_HEIGHT);
    defer sdl.destroyWindow(window);

    const renderer = try sdl.createRenderer(window);
    defer sdl.destroyRenderer(renderer);

    const audio = try sdl.getAudioContext(sdl.RawAudioSpec{ .frequency = SAMPLE_FREQUENCY, .channels = 1, .samples = SAMPLE_COUNT });
    defer audio.release();

    while (true) {
        const start_time = sdl.ticks();

        var flags = [_]bool{false} ** 16;
        if (!sdl.handle_events(&flags)) break;

        {
            // Write into VM's key-state bytes.
            vm.setInputFlags(flags);

            // Execute exactly 65535 instructions.
            vm.resetIp();
            for (0..INSTR_COUNT) |_| {
                try vm.execute();
            }

            // Read pixel data from specified location.
            const pxd_st = vm.getPixelDataStart();
            const pxd_en = pxd_st + SCREEN_WIDTH * SCREEN_HEIGHT;
            for (vm.m[pxd_st..pxd_en], 0..) |value, index| {
                const c = sdl.color8b(value);
                const x = (index % SCREEN_WIDTH) * PIXEL_WIDTH;
                const y = (index / SCREEN_WIDTH) * PIXEL_HEIGHT;
                try sdl.drawFilledRect(
                    renderer,
                    @as(i32, @intCast(x)),
                    @as(i32, @intCast(y)),
                    PIXEL_WIDTH,
                    PIXEL_HEIGHT,
                    c,
                );
            }

            sdl.presentRendered(renderer);
            // Deliberately avoiding clearing the renderer, since all pixel colours will be opaque.

            // Queue / render audio from the buffer.
            try audio.render(vm.getAudioBuffer());
        }

        const elapsed = sdl.ticks() - start_time;
        if (elapsed < MSPF) {
            sdl.delay(MSPF - elapsed);
        }
    }
}

test "color8b_tests" {
    try std.testing.expectEqual(@as(sdl.RgbColor, sdl.RgbColor{ .red = 0, .green = 0, .blue = 0 }), sdl.color8b(0));
}
