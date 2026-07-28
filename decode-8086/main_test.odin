package main

import "core:bytes"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

expect_assembly_round_trip :: proc(t: ^testing.T, input: string) {
	temp_dir, err := os.make_directory_temp("", "decode-8086-*", context.allocator)
	if !testing.expectf(t, err == nil, "could not create temporary directory: %v", err) {
		return
	}
	defer delete(temp_dir)
	defer os.remove_all(temp_dir)

	asm_path, _ := filepath.join({temp_dir, "decoded.asm"})
	bin_path, _ := filepath.join({temp_dir, "decoded.bin"})
	defer delete(asm_path)
	defer delete(bin_path)

	output := strings.builder_make()
	defer strings.builder_destroy(&output)
	strings.write_string(&output, "bits 16\n\n")

	result := decode(transmute([]u8)input, &output)
	if !testing.expectf(
		t,
		result.error == .None,
		"decode failed at byte %d with %v",
		result.offset,
		result.error,
	) {
		return
	}

	err = os.write_entire_file(asm_path, strings.to_string(output))
	if !testing.expectf(t, err == nil, "could not write decoded assembly: %v", err) {
		return
	}

	state, stdout, stderr, process_err := os.process_exec(
		{command = {"nasm", "-f", "bin", "-o", bin_path, asm_path}},
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)

	if !testing.expectf(t, process_err == nil, "could not run nasm: %v", process_err) {
		return
	}
	if !testing.expectf(t, state.success, "nasm failed:\n%s", string(stderr)) {
		return
	}

	assembled, read_err := os.read_entire_file(bin_path, context.allocator)
	defer delete(assembled)
	if !testing.expectf(t, read_err == nil, "could not read nasm output: %v", read_err) {
		return
	}

	testing.expect(t, bytes.equal(assembled, transmute([]u8)input), "round-trip bytes differ")
}

expect_simulation_trace :: proc(t: ^testing.T, input, input_path, expected_trace: string) {
	output := strings.builder_make()
	defer strings.builder_destroy(&output)

	result := simulate(transmute([]u8)input, input_path, &output)
	if !testing.expectf(
		t,
		result.error == .None,
		"simulation failed at byte %d with %v",
		result.offset,
		result.error,
	) {
		return
	}

	expected_builder := strings.builder_make()
	defer strings.builder_destroy(&expected_builder)
	strings.write_string(&expected_builder, expected_trace)
	strings.builder_replace_all(&expected_builder, "\r\n", "\n")
	strings.builder_replace_all(&expected_builder, " \n", "\n")
	expected := strings.to_string(expected_builder)

	testing.expectf(
		t,
		strings.to_string(output) == expected,
		"simulation trace differs\nexpected:\n%s\nactual:\n%s",
		expected,
		strings.to_string(output),
	)
}

@(test)
listing_0037_single_register_mov :: proc(t: ^testing.T) {
	expect_assembly_round_trip(t, #load("testdata/listing_0037_single_register_mov"))
}

@(test)
listing_0038_many_register_mov :: proc(t: ^testing.T) {
	expect_assembly_round_trip(t, #load("testdata/listing_0038_many_register_mov"))
}

@(test)
listing_0039_more_movs :: proc(t: ^testing.T) {
	expect_assembly_round_trip(t, #load("testdata/listing_0039_more_movs"))
}

@(test)
listing_0040_challenge_movs :: proc(t: ^testing.T) {
	expect_assembly_round_trip(t, #load("testdata/listing_0040_challenge_movs"))
}

@(test)
listing_0041_add_sub_cmp_jnz :: proc(t: ^testing.T) {
	expect_assembly_round_trip(t, #load("testdata/listing_0041_add_sub_cmp_jnz"))
}

@(test)
simulate_listing_0043_immediate_movs :: proc(t: ^testing.T) {
	expect_simulation_trace(
		t,
		#load("testdata/listing_0043_immediate_movs"),
		"test\\listing_0043_immediate_movs",
		#load("testdata/listing_0043_immediate_movs.txt"),
	)
}

@(test)
simulate_listing_0044_register_movs :: proc(t: ^testing.T) {
	expect_simulation_trace(
		t,
		#load("testdata/listing_0044_register_movs"),
		"test\\listing_0044_register_movs",
		#load("testdata/listing_0044_register_movs.txt"),
	)
}

@(test)
simulate_rejects_unsupported_instruction :: proc(t: ^testing.T) {
	// mov ax, [0] uses a memory operand and is outside the first simulator milestone.
	data := [3]u8{0xa1, 0x00, 0x00}
	output := strings.builder_make()
	defer strings.builder_destroy(&output)

	result := simulate(data[:], "memory-mov", &output)
	testing.expect(t, result.error == .Unsupported_Instruction)
	testing.expect(t, result.offset == 0)
}

@(test)
simulate_reports_truncated_instruction :: proc(t: ^testing.T) {
	data := [2]u8{0xb8, 0x01}
	output := strings.builder_make()
	defer strings.builder_destroy(&output)

	result := simulate(data[:], "truncated", &output)
	testing.expect(t, result.error == .Truncated_Instruction)
	testing.expect(t, result.offset == 0)
}
