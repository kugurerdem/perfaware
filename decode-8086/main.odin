package main

import "core:fmt"
import "core:os"
import "core:strings"

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

Decode_Error :: enum {
	None,
	Unsupported_Opcode,
	Unsupported_Addressing_Mode,
}

Decode_Result :: struct {
	error:           Decode_Error,
	offset:          int,
	addressing_mode: u8,
}

decode :: proc(data: []u8, output: ^strings.Builder) -> Decode_Result {
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

		if opcode != u8(Opcode.MOV) {
			return {error = .Unsupported_Opcode, offset = i}
		}

		mod := b1 >> 6
		reg := (b1 >> 3) & 0b111
		rm := b1 & 0b111

		// This version only supports register-to-register MOV.
		if mod != 0b11 {
			return {error = .Unsupported_Addressing_Mode, offset = i, addressing_mode = mod}
		}

		// determine the reg and rm operands based on w field, and their values
		reg_operand: string
		rm_operand: string

		// TODO: If we just had one array instead of two different registers arrays,
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
			fmt.sbprintfln(output, "mov %s, %s", rm_operand, reg_operand)
		} else {
			fmt.sbprintfln(output, "mov %s, %s", reg_operand, rm_operand)
		}
	}

	return {}
}

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

	output := strings.builder_make()
	defer strings.builder_destroy(&output)

	result := decode(data, &output)
	switch result.error {
	case .Unsupported_Opcode:
		fmt.println("Unsupported operand! Only supported operand is MOV")
		return
	case .Unsupported_Addressing_Mode:
		fmt.printf(
			"Unsupported addressing mode at byte %d: mod=%02b\n",
			result.offset,
			result.addressing_mode,
		)
		return
	case .None:
	}

	err = os.write_entire_file(decodeFilePath, strings.to_string(output))
	if err != nil {
		fmt.println("Failed to write file:", err)
	}
}

