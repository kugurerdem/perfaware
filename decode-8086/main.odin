package main

import "core:fmt"
import "core:os"

// Opcode is the first 6 bits of the instruction
// it can be obtained by applying >> 2 to the first half of the instruction
Opcode :: enum u8 {
	MOV = 0b100010,
}

// We use registers_8 when w == 0, and registers_16 when w == 1
// The order of these strings are determined based on the mapping of bits to registers
// For example, if w == 0, then REG field is 000 it will map to registers_8[000] -> al
registers_8 := [8]string{"al", "cl", "dl", "bl", "ah", "ch", "dh", "bh"}
registers_16 := [8]string{"ax", "cx", "dx", "bx", "sp", "bp", "si", "di"}

main :: proc() {
	if len(os.args) < 3 {
		fmt.println("Example Usage: decode_8086 inputfile targetfile")
		return
	}

	binaryFilePath := os.args[1]
	decodeFilePath := os.args[2]

	fmt.printf("Decompiling %s into %s\n", binaryFilePath, decodeFilePath)

	data, err := os.read_entire_file(binaryFilePath, context.allocator)
	if err != nil {
		fmt.println("Failed to read file:", err)
		return
	}
	defer delete(data)

	// We should create an output file
	output_file: ^os.File
	output_file, err = os.create(decodeFilePath)
	if err != nil {
		fmt.println("Failed to create output file:", err)
		return
	}
	defer os.close(output_file)

	for i := 0; i + 1 < len(data); i += 2 {
		b0 := data[i] // opcode (6 bits) d w
		b1 := data[i + 1] // mod reg r/m

		opcode := b0 >> 2
		// d determines the operand direction
		// it 0, we copy from reg_operand to rm_operand
		// if 1, we copy from rm_operand to reg_operand
		d := (b0 >> 1) & 1

		// w determines which register table to use
		// if 0, we use lower or higher half of the registers
		// if 1, we use the whole registers 
		w := b0 & 1

		if (opcode != u8(Opcode.MOV)) {
			fmt.println("Unsupported operand! Only supported operand is MOV")
			return
		}

		mod := b1 >> 6
		reg := (b1 >> 3) & 0b111
		rm := b1 & 0b111

		// This version only supports register-to-register MOV.
		if mod != 0b11 {
			fmt.printf("Unsupported addressing mode at byte %d: mod=%02b\n", i, mod)
			return
		}

		// determine the reg and rm operands based on w field, and their values
		reg_operand: string
		rm_operand: string

		// TODO: If he just had one array instead of two different registers arrays,
		// I think we could have done something smarter here
		if w == 0 {
			reg_operand = registers_8[reg]
			rm_operand = registers_8[rm]
		} else {
			reg_operand = registers_16[reg]
			rm_operand = registers_16[rm]
		}

		// Determine the destination and source order based on d bit
		if d == 0 {
			fmt.fprintfln(output_file, "mov %s, %s", rm_operand, reg_operand)
		} else {
			fmt.fprintfln(output_file, "mov %s, %s", reg_operand, rm_operand)
		}

	}
}

