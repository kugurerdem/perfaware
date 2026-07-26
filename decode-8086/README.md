# Homework

The first part of the series has homeworks related to implementing an assembly decoder, and then also, simulating the parts we have implemented.

For reference, Page 164 of the [8086 Reference Manual](https://edge.edx.org/c4x/BITSPilani/EEE231/asset/8086_family_Users_Manual_1_.pdf) should be helpful.

## Decoder

There were three milestones to implementing the decoder, which are all currently implemented and also available through the git tags (`decode8086-1`, `decode8086-2` and `decode8086-3`).

- [X] Write a program that reads an 8086 binary and disassembles only the register-to-register MOV instruction into Intel assembly syntax.
- [X] Extend the program so that it decodes all MOV forms. Handle variable-length instructions, memory operands, and displacements.
- [X] Extend the decoder to support arithmetic instructions like `ADD`, `SUB`, and `CMP`.

## Simulator

- [ ] Simulate non-memory MOVs
- [ ] Simulating ADD, SUB, and CMP

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
