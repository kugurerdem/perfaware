package main

import "core:strings"
import "core:testing"

@(test)
decode_assembly_output :: proc(t: ^testing.T) {
	tests := []struct {
		name:     string,
		input:    string,
		expected: string,
	} {
		{
			name = "single register mov",
			input = #load("testdata/listing_0037_single_register_mov"),
			expected = "mov cx, bx\n",
		},
		{
			name = "many register movs",
			input = #load("testdata/listing_0038_many_register_mov"),
			expected = "mov cx, bx\n" +
			"mov ch, ah\n" +
			"mov dx, bx\n" +
			"mov si, bx\n" +
			"mov bx, di\n" +
			"mov al, cl\n" +
			"mov ch, ch\n" +
			"mov bx, ax\n" +
			"mov bx, si\n" +
			"mov sp, di\n" +
			"mov bp, ax\n",
		},
	}

	for test in tests {
		output := strings.builder_make()
		result := decode(transmute([]u8)test.input, &output)

		testing.expect_value(t, result.error, Decode_Error.None)
		testing.expect_value(t, strings.to_string(output), test.expected)

		strings.builder_destroy(&output)
	}
}
