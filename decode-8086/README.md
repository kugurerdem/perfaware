# Homework

Write a program that reads an 8086 binary and disassembles only the register-to-register MOV instruction into Intel assembly syntax.

Page 164 of the [8086 Reference Manual](https://edge.edx.org/c4x/BITSPilani/EEE231/asset/8086_family_Users_Manual_1_.pdf) should be helpful.

## Testing

I've put the files provided by Casey under `testdata` folder.

To test our decoder implementation against them, we can simply:

```bash
./decode_8086 listing_0037_single_register_mov listing_0037_single_register_mov.decoded.asm
```

