# Homework

There are three milestones to this project.

- [X] Write a program that reads an 8086 binary and disassembles only the register-to-register MOV instruction into Intel assembly syntax.
- [ ] Extend the program so that it decodes all MOV forms. Handle variable-length instructions, memory operands, and displacements.
  - [X] Register to register (with 8-bit and 16-bit displacemets)
  - [X] Immediate-to-register (both for 8-bit and 16-bit)
  - [ ] Source address calculation
  - [ ] Source address calculation plus 8-bit displacement
  - [ ] Source address calculation plus 16-bit displacement
  - [ ] Dest address calculation
  - [ ] Signed displacements
  - [ ] Explicit sizes
  - [ ] Direct address
  - [ ] Memory to accumulator
  - [ ] Accumulator to memory
- [ ] Extend the decoder to support arithmetic instructions like `ADD`, `SUB`, and `CMP`.

Page 164 of the [8086 Reference Manual](https://edge.edx.org/c4x/BITSPilani/EEE231/asset/8086_family_Users_Manual_1_.pdf) should be helpful.

## Testing

I've put the files provided by Casey under `testdata` folder.

Install NASM, then run all decode/reassemble round-trip tests with:

```bash
odin test .
```

The tests decode each provided binary, reassemble the decoded instructions with
NASM, and compare the resulting bytes with the original binary.

To test only specific listings:

```bash
odin test . -- -tests:listing_0037_single_register_mov,listing_0038_many_register_mov
```
