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
