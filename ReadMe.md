# Bytzig
This repository implements the minimalist virtual machine [BytePusher](https://esolangs.org/wiki/BytePusher) in Zig (v 0.11.0) using SDL2.
The BytePusher Virtual Machine operates through the use of exactly one instruction, the acclaimed - "ByteByteJump" which acts on 3 address operands, copying data from 1st to 2nd and jumping to the third. BytePusher code, owing to the simple architecture, often involves lookup tables and self-modification. The BytePusher specification also requires a 256x256 pixels display screen and an audio output.

# Planned Features
- [x] Audio
- [ ] Save States
