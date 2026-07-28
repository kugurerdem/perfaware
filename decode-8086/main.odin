package main

import "core:fmt"
import "core:os"
import "core:strings"

// Opcode contains the fixed opcode bits for each supported instruction form.
// The suffix documents how many low-order bits must be removed from the first
// instruction byte before comparing it with the enum value.
Opcode :: enum u8 {
	REGISTER_MEMORY_TO_FROM_REGISTER_ADD_SHIFT_2 = 0b000000,
	REGISTER_MEMORY_TO_FROM_REGISTER_SUB_SHIFT_2 = 0b001010,
	REGISTER_MEMORY_TO_FROM_REGISTER_CMP_SHIFT_2 = 0b001110,
	REGISTER_MEMORY_TO_FROM_REGISTER_MOV_SHIFT_2 = 0b100010,
	IMMEDIATE_TO_ACCUMULATOR_ADD_SHIFT_1         = 0b00000010,
	IMMEDIATE_TO_ACCUMULATOR_SUB_SHIFT_1         = 0b00010110,
	IMMEDIATE_TO_ACCUMULATOR_CMP_SHIFT_1         = 0b00011110,
	IMMEDIATE_TO_REGISTER_MEMORY_BYTE            = 0b10000000,
	IMMEDIATE_TO_REGISTER_MEMORY_WORD            = 0b10000001,
	IMMEDIATE_TO_REGISTER_MEMORY_SIGN_EXTENDED   = 0b10000011,
	IMMEDIATE_TO_REG_MOV_SHIFT_4                 = 0b1011,
	IMMEDIATE_TO_REGISTER_MEMORY_MOV_SHIFT_1     = 0b1100011,
	ACCUMULATOR_MEMORY_MOV_SHIFT_2               = 0b101000,
}

Arithmetic_Opcode_Extension :: enum u8 {
	ADD = 0,
	SUB = 5,
	CMP = 7,
}

// We use registers_8 when w == 0, and registers_16 when w == 1
// The order of these strings are determined based on the mapping of bits to registers
// For example, if w == 0, then REG field is 000 it will map to registers_8[000] -> al
registers_8 := [8]string{"al", "cl", "dl", "bl", "ah", "ch", "dh", "bh"}
registers_16 := [8]string{"ax", "cx", "dx", "bx", "sp", "bp", "si", "di"}
final_register_order := [8]u8{0, 3, 1, 2, 4, 5, 6, 7}

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

write_rm_operand :: proc(data: []u8, i: ^int, mod, rm, w: u8, output: ^strings.Builder) {
	switch mod {
	case 0b00:
		if rm == 0b110 {
			address := u16(data[i^]) | u16(data[i^ + 1]) << 8
			i^ += 2
			fmt.sbprintf(output, "[%d]", address)
		} else {
			fmt.sbprintf(output, "[%s]", effective_addresses[rm])
		}
	case 0b01:
		displacement := int(i8(data[i^]))
		i^ += 1
		if displacement < 0 {
			fmt.sbprintf(output, "[%s - %d]", effective_addresses[rm], -displacement)
		} else if displacement > 0 {
			fmt.sbprintf(output, "[%s + %d]", effective_addresses[rm], displacement)
		} else {
			fmt.sbprintf(output, "[%s]", effective_addresses[rm])
		}
	case 0b10:
		raw_displacement := u16(data[i^]) | u16(data[i^ + 1]) << 8
		i^ += 2
		displacement := int(i16(raw_displacement))
		if displacement < 0 {
			fmt.sbprintf(output, "[%s - %d]", effective_addresses[rm], -displacement)
		} else if displacement > 0 {
			fmt.sbprintf(output, "[%s + %d]", effective_addresses[rm], displacement)
		} else {
			fmt.sbprintf(output, "[%s]", effective_addresses[rm])
		}
	case 0b11:
		if w == 0 {
			strings.write_string(output, registers_8[rm])
		} else {
			strings.write_string(output, registers_16[rm])
		}
	}
}

jump_mnemonics := [16]string {
	"jo",
	"jno",
	"jb",
	"jnb",
	"je",
	"jne",
	"jbe",
	"ja",
	"js",
	"jns",
	"jp",
	"jnp",
	"jl",
	"jnl",
	"jle",
	"jg",
}

loop_mnemonics := [4]string{"loopnz", "loopz", "loop", "jcxz"}

write_relative_jump :: proc(output: ^strings.Builder, mnemonic: string, displacement: i8) {
	target_offset := int(displacement) + 2
	if target_offset < 0 {
		fmt.sbprintfln(output, "%s $-%d", mnemonic, -target_offset)
	} else if target_offset > 0 {
		fmt.sbprintfln(output, "%s $+%d", mnemonic, target_offset)
	} else {
		fmt.sbprintfln(output, "%s $", mnemonic)
	}
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

Simulation_Error :: enum {
	None,
	Unsupported_Instruction,
	Truncated_Instruction,
}

Simulation_Result :: struct {
	error:  Simulation_Error,
	offset: int,
}

decode :: proc(data: []u8, output: ^strings.Builder) -> Decode_Result {
	for i := 0; i + 1 < len(data); {
		b0 := data[i] // opcode (6 bits) d w
		i += 1

		b1 := data[i] // mod reg r/m
		i += 1

		switch {
		// We can group these ADD, SUB and CMP operations simply because,
		// their handling is same except for the opcode/mnemonic
		case b0 >> 2 == u8(Opcode.REGISTER_MEMORY_TO_FROM_REGISTER_ADD_SHIFT_2) ||
		     b0 >> 2 == u8(Opcode.REGISTER_MEMORY_TO_FROM_REGISTER_SUB_SHIFT_2) ||
		     b0 >> 2 == u8(Opcode.REGISTER_MEMORY_TO_FROM_REGISTER_CMP_SHIFT_2):
			mnemonic := "add"
			switch b0 >> 2 {
			case u8(Opcode.REGISTER_MEMORY_TO_FROM_REGISTER_SUB_SHIFT_2):
				mnemonic = "sub"
			case u8(Opcode.REGISTER_MEMORY_TO_FROM_REGISTER_CMP_SHIFT_2):
				mnemonic = "cmp"
			}

			d := (b0 >> 1) & 1
			w := b0 & 1
			mod := b1 >> 6
			reg := (b1 >> 3) & 0b111
			rm := b1 & 0b111

			reg_operand := registers_8[reg]
			if w == 1 {
				reg_operand = registers_16[reg]
			}

			rm_builder := strings.builder_make()
			write_rm_operand(data, &i, mod, rm, w, &rm_builder)
			rm_operand := strings.to_string(rm_builder)

			if d == 0 {
				fmt.sbprintfln(output, "%s %s, %s", mnemonic, rm_operand, reg_operand)
			} else {
				fmt.sbprintfln(output, "%s %s, %s", mnemonic, reg_operand, rm_operand)
			}
			strings.builder_destroy(&rm_builder)
			continue

		// We can group these ADD, SUB and CMP operations simply because,
		// their handling is same except for the opcode/mnemonic
		case b0 >> 1 == u8(Opcode.IMMEDIATE_TO_ACCUMULATOR_ADD_SHIFT_1) ||
		     b0 >> 1 == u8(Opcode.IMMEDIATE_TO_ACCUMULATOR_SUB_SHIFT_1) ||
		     b0 >> 1 == u8(Opcode.IMMEDIATE_TO_ACCUMULATOR_CMP_SHIFT_1):
			mnemonic := "add"
			switch b0 >> 1 {
			case u8(Opcode.IMMEDIATE_TO_ACCUMULATOR_SUB_SHIFT_1):
				mnemonic = "sub"
			case u8(Opcode.IMMEDIATE_TO_ACCUMULATOR_CMP_SHIFT_1):
				mnemonic = "cmp"
			}

			w := b0 & 1
			if w == 0 {
				fmt.sbprintfln(output, "%s al, %d", mnemonic, i8(b1))
			} else {
				immediate := u16(b1) | u16(data[i]) << 8
				i += 1
				fmt.sbprintfln(output, "%s ax, %d", mnemonic, i16(immediate))
			}
			continue

		case b0 == u8(Opcode.IMMEDIATE_TO_REGISTER_MEMORY_BYTE) ||
		     b0 == u8(Opcode.IMMEDIATE_TO_REGISTER_MEMORY_WORD) ||
		     b0 == u8(Opcode.IMMEDIATE_TO_REGISTER_MEMORY_SIGN_EXTENDED):
			mod := b1 >> 6
			opcode_extension := (b1 >> 3) & 0b111
			rm := b1 & 0b111

			mnemonic := ""
			switch opcode_extension {
			case u8(Arithmetic_Opcode_Extension.ADD):
				mnemonic = "add"
			case u8(Arithmetic_Opcode_Extension.SUB):
				mnemonic = "sub"
			case u8(Arithmetic_Opcode_Extension.CMP):
				mnemonic = "cmp"
			case:
				return {error = .Unsupported_Opcode, offset = i - 2}
			}

			w: u8 = 0
			if b0 != u8(Opcode.IMMEDIATE_TO_REGISTER_MEMORY_BYTE) {
				w = 1
			}

			rm_builder := strings.builder_make()
			write_rm_operand(data, &i, mod, rm, w, &rm_builder)
			rm_operand := strings.to_string(rm_builder)

			switch b0 {
			case u8(Opcode.IMMEDIATE_TO_REGISTER_MEMORY_BYTE):
				immediate := i8(data[i])
				i += 1
				if mod == 0b11 {
					fmt.sbprintfln(output, "%s %s, %d", mnemonic, rm_operand, immediate)
				} else {
					fmt.sbprintfln(output, "%s byte %s, %d", mnemonic, rm_operand, immediate)
				}
			case u8(Opcode.IMMEDIATE_TO_REGISTER_MEMORY_WORD):
				raw_immediate := u16(data[i]) | u16(data[i + 1]) << 8
				i += 2
				immediate := i16(raw_immediate)
				if mod == 0b11 {
					fmt.sbprintfln(
						output,
						"%s %s, strict word %d",
						mnemonic,
						rm_operand,
						immediate,
					)
				} else {
					fmt.sbprintfln(
						output,
						"%s word %s, strict word %d",
						mnemonic,
						rm_operand,
						immediate,
					)
				}
			case u8(Opcode.IMMEDIATE_TO_REGISTER_MEMORY_SIGN_EXTENDED):
				immediate := i8(data[i])
				i += 1
				if mod == 0b11 {
					fmt.sbprintfln(
						output,
						"%s %s, strict byte %d",
						mnemonic,
						rm_operand,
						immediate,
					)
				} else {
					fmt.sbprintfln(
						output,
						"%s word %s, strict byte %d",
						mnemonic,
						rm_operand,
						immediate,
					)
				}
			}

			strings.builder_destroy(&rm_builder)
			continue
		case b0 >> 4 == 0b0111:
			write_relative_jump(output, jump_mnemonics[b0 & 0b1111], i8(b1))
			continue
		case b0 & 0b11111100 == 0b11100000:
			write_relative_jump(output, loop_mnemonics[b0 & 0b11], i8(b1))
			continue
		case b0 >> 2 == u8(Opcode.ACCUMULATOR_MEMORY_MOV_SHIFT_2):
			// A0-A3 encode a move between AL/AX and a direct 16-bit
			// memory address. The instruction has no ModR/M byte, so b1
			// is the low byte of the address that was read above.
			d := (b0 >> 1) & 1
			w := b0 & 1
			address := u16(b1) | u16(data[i]) << 8
			i += 1

			accumulator := registers_8[0]
			if w == 1 {
				accumulator = registers_16[0]
			}

			if d == 0 {
				fmt.sbprintfln(output, "mov %s, [%d]", accumulator, address)
			} else {
				fmt.sbprintfln(output, "mov [%d], %s", address, accumulator)
			}
			continue
		case b0 >> 2 == u8(Opcode.REGISTER_MEMORY_TO_FROM_REGISTER_MOV_SHIFT_2):
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
			write_rm_operand(data, &i, mod, rm, w, &rm_builder)

			rm_operand := strings.to_string(rm_builder)
			if d == 0 {
				fmt.sbprintfln(output, "mov %s, %s", rm_operand, reg_operand)
			} else {
				fmt.sbprintfln(output, "mov %s, %s", reg_operand, rm_operand)
			}
			strings.builder_destroy(&rm_builder)

			continue
		case b0 >> 4 == u8(Opcode.IMMEDIATE_TO_REG_MOV_SHIFT_4):
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
		case b0 >> 1 == u8(Opcode.IMMEDIATE_TO_REGISTER_MEMORY_MOV_SHIFT_1):
			w := b0 & 1
			mod := b1 >> 6
			opcode_extension := (b1 >> 3) & 0b111
			rm := b1 & 0b111

			// C6/C7 use the ModR/M reg field as an opcode extension, which
			// must be zero for MOV.
			if opcode_extension != 0 {
				return {error = .Unsupported_Opcode, offset = i - 2}
			}

			rm_builder := strings.builder_make()
			write_rm_operand(data, &i, mod, rm, w, &rm_builder)

			rm_operand := strings.to_string(rm_builder)
			if w == 0 {
				immediate := i8(data[i])
				i += 1
				if mod == 0b11 {
					fmt.sbprintfln(output, "mov %s, %d", rm_operand, immediate)
				} else {
					fmt.sbprintfln(output, "mov %s, byte %d", rm_operand, immediate)
				}
			} else {
				immediate := u16(data[i]) | u16(data[i + 1]) << 8
				i += 2
				if mod == 0b11 {
					fmt.sbprintfln(output, "mov %s, %d", rm_operand, i16(immediate))
				} else {
					fmt.sbprintfln(output, "mov %s, word %d", rm_operand, i16(immediate))
				}
			}
			strings.builder_destroy(&rm_builder)
			continue
		}

		return {error = .Unsupported_Opcode, offset = i}
	}

	return {}
}

simulate :: proc(data: []u8, input_path: string, output: ^strings.Builder) -> Simulation_Result {
	registers: [8]u16

	fmt.sbprintfln(output, "--- %s execution ---", input_path)

	for i := 0; i < len(data); {
		instruction_offset := i
		b0 := data[i]
		i += 1

		// B8-BF encode a 16-bit immediate-to-register MOV.
		if b0 >> 4 == u8(Opcode.IMMEDIATE_TO_REG_MOV_SHIFT_4) && (b0 >> 3) & 1 == 1 {
			if i + 1 >= len(data) {
				return {error = .Truncated_Instruction, offset = instruction_offset}
			}

			register_index := b0 & 0b111
			value := u16(data[i]) | u16(data[i + 1]) << 8
			i += 2

			previous_value := registers[register_index]
			registers[register_index] = value
			fmt.sbprintfln(
				output,
				"mov %s, %d ; %s:0x%x->0x%x",
				registers_16[register_index],
				i16(value),
				registers_16[register_index],
				previous_value,
				value,
			)
			continue
		}

		// The first simulator milestone only supports 16-bit register-to-register
		// MOVs. Memory operands and 8-bit register aliases are intentionally rejected.
		if b0 >> 2 == u8(Opcode.REGISTER_MEMORY_TO_FROM_REGISTER_MOV_SHIFT_2) && b0 & 1 == 1 {
			if i >= len(data) {
				return {error = .Truncated_Instruction, offset = instruction_offset}
			}

			b1 := data[i]
			i += 1
			mod := b1 >> 6
			if mod != 0b11 {
				return {error = .Unsupported_Instruction, offset = instruction_offset}
			}

			d := (b0 >> 1) & 1
			reg := (b1 >> 3) & 0b111
			rm := b1 & 0b111

			destination := rm
			source := reg
			if d == 1 {
				destination = reg
				source = rm
			}

			previous_value := registers[destination]
			registers[destination] = registers[source]
			fmt.sbprintfln(
				output,
				"mov %s, %s ; %s:0x%x->0x%x",
				registers_16[destination],
				registers_16[source],
				registers_16[destination],
				previous_value,
				registers[destination],
			)
			continue
		}

		return {error = .Unsupported_Instruction, offset = instruction_offset}
	}

	strings.write_string(output, "\nFinal registers:\n")
	for register_index in final_register_order {
		fmt.sbprintfln(
			output,
			"      %s: 0x%04x (%d)",
			registers_16[register_index],
			registers[register_index],
			registers[register_index],
		)
	}
	strings.write_rune(output, '\n')

	return {}
}

print_usage :: proc() {
	fmt.println("Usage: decode_8086 inputfile targetfile [-sim]")
}

main :: proc() {
	simulate_mode := false
	switch len(os.args) {
	case 3:
	case 4:
		if os.args[3] != "-sim" {
			print_usage()
			return
		}
		simulate_mode = true
	case:
		print_usage()
		return
	}

	binaryFilePath := os.args[1]
	decodeFilePath := os.args[2]

	if simulate_mode {
		fmt.printf("Simulating %s into %s\n", binaryFilePath, decodeFilePath)
	} else {
		fmt.printf("Decompiling %s into %s\n", binaryFilePath, decodeFilePath)
	}

	data, err := os.read_entire_file(binaryFilePath, context.allocator)
	if err != nil {
		fmt.println("Failed to read file:", err)
		return
	}
	defer delete(data)

	output := strings.builder_make()
	defer strings.builder_destroy(&output)

	if simulate_mode {
		result := simulate(data, binaryFilePath, &output)
		switch result.error {
		case .Unsupported_Instruction:
			fmt.printf("Unsupported simulation instruction at byte %d\n", result.offset)
			return
		case .Truncated_Instruction:
			fmt.printf("Truncated simulation instruction at byte %d\n", result.offset)
			return
		case .None:
		}
	} else {
		result := decode(data, &output)
		switch result.error {
		case .Unsupported_Opcode:
			fmt.printf("Unsupported opcode at byte %d\n", result.offset)
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
	}

	err = os.write_entire_file(decodeFilePath, strings.to_string(output))
	if err != nil {
		fmt.println("Failed to write file:", err)
	}
}

