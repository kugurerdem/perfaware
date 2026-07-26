package main

import "core:fmt"
import "core:os"
import "core:strings"

// Opcode is the first 6 bits of the instruction
// it can be obtained by applying >> 2 to the first half of the instruction
Opcode :: enum u8 {
	REGISTER_MEMORY_TO_FROM_REGISTER_MOV = 0b100010,
	IMMEDIATE_TO_REG_MOV                 = 0b1011,
}

// We use registers_8 when w == 0, and registers_16 when w == 1
// The order of these strings are determined based on the mapping of bits to registers
// For example, if w == 0, then REG field is 000 it will map to registers_8[000] -> al
registers_8 := [8]string{"al", "cl", "dl", "bl", "ah", "ch", "dh", "bh"}
registers_16 := [8]string{"ax", "cx", "dx", "bx", "sp", "bp", "si", "di"}

// Effective-address expressions selected by the r/m field when mod != 0b11.
// They are used for main memory
effective_addresses := [8]string {
	"bx + si", // r/m=000: base address in BX plus source index in SI
	"bx + di", // r/m=001: base address in BX plus destination index in DI
	"bp + si", // r/m=010: stack base in BP plus source index in SI
	"bp + di", // r/m=011: stack base in BP plus destination index in DI
	"si", // r/m=100: address stored in the source index register
	"di", // r/m=101: address stored in the destination index register
	"bp", // r/m=110: address in BP; with mod=00, this means a direct address
	"bx", // r/m=111: address stored in the base register
}

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
	for i := 0; i + 1 < len(data); {
		b0 := data[i] // opcode (6 bits) d w
		i += 1

		b1 := data[i] // mod reg r/m
		i += 1

		switch {
		case b0 >> 2 == u8(Opcode.REGISTER_MEMORY_TO_FROM_REGISTER_MOV):
			// d determines the operand direction
			// it 0, we copy from reg_operand to rm_operand
			// if 1, we copy from rm_operand to reg_operand
			d := (b0 >> 1) & 1

			// w determines which register table to use
			// if 0, we use lower or higher half of the registers
			// if 1, we use the whole registers
			w := b0 & 1

			mod := b1 >> 6
			reg := (b1 >> 3) & 0b111
			rm := b1 & 0b111

			reg_operand := registers_8[reg]
			if w == 1 {
				reg_operand = registers_16[reg]
			}

			rm_builder := strings.builder_make()

			// All cases except 0b11, means that rm is used for the memory address
			switch mod {
			// mod = 0b00 is a special case, if rm == 0b110, then we put address,
			// otherwise effective_addresses
			case 0b00:
				if rm == 0b110 {
					// mod=00, r/m=110 is a direct 16-bit address rather
					// than the otherwise expected [bp].
					address := u16(data[i]) | u16(data[i + 1]) << 8
					i += 2
					fmt.sbprintf(&rm_builder, "[%d]", address)
				} else {
					fmt.sbprintf(&rm_builder, "[%s]", effective_addresses[rm])
				}

			// mod == 0b01 is for 8 bit displacement
			case 0b01:
				displacement := int(i8(data[i]))
				i += 1
				if displacement < 0 {
					fmt.sbprintf(&rm_builder, "[%s - %d]", effective_addresses[rm], -displacement)
				} else if displacement > 0 {
					fmt.sbprintf(&rm_builder, "[%s + %d]", effective_addresses[rm], displacement)
				} else {
					fmt.sbprintf(&rm_builder, "[%s]", effective_addresses[rm])
				}

			// mod == 0b10 is for 16 bit displacement
			case 0b10:
				raw_displacement := u16(data[i]) | u16(data[i + 1]) << 8
				i += 2
				displacement := int(i16(raw_displacement))
				if displacement < 0 {
					fmt.sbprintf(&rm_builder, "[%s - %d]", effective_addresses[rm], -displacement)
				} else if displacement > 0 {
					fmt.sbprintf(&rm_builder, "[%s + %d]", effective_addresses[rm], displacement)
				} else {
					fmt.sbprintf(&rm_builder, "[%s]", effective_addresses[rm])
				}

			// mod == 0b11 is for from registor to register
			case 0b11:
				if w == 0 {
					strings.write_string(&rm_builder, registers_8[rm])
				} else {
					strings.write_string(&rm_builder, registers_16[rm])
				}
			}

			rm_operand := strings.to_string(rm_builder)
			if d == 0 {
				fmt.sbprintfln(output, "mov %s, %s", rm_operand, reg_operand)
			} else {
				fmt.sbprintfln(output, "mov %s, %s", reg_operand, rm_operand)
			}
			strings.builder_destroy(&rm_builder)

			continue
		case b0 >> 4 == u8(Opcode.IMMEDIATE_TO_REG_MOV):
			w := (b0 >> 3) & 1
			reg := b0 & 0b111

			if w == 0 {
				immediate := i8(b1)
				fmt.sbprintfln(output, "mov %s, %d", registers_8[reg], immediate)
			} else {
				immediate := u16(b1) | u16(data[i]) << 8
				i += 1
				fmt.sbprintfln(output, "mov %s, %d", registers_16[reg], i16(immediate))
			}
			continue
		}

		return {error = .Unsupported_Opcode, offset = i}
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

