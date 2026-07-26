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
		{
			name = "more movs",
			input = #load("testdata/listing_0039_more_movs"),
			expected = "mov si, bx\n" +
			"mov dh, al\n" +
			"mov cl, 12\n" +
			"mov ch, -12\n" +
			"mov cx, 12\n" +
			"mov cx, -12\n" +
			"mov dx, 3948\n" +
			"mov dx, -3948\n" +
			"mov al, [bx + si]\n" +
			"mov bx, [bp + di]\n" +
			"mov dx, [bp]\n" +
			"mov ah, [bx + si + 4]\n" +
			"mov al, [bx + si + 4999]\n" +
			"mov [bx + di], cx\n" +
			"mov [bp + si], cl\n" +
			"mov [bp], ch\n",
		},
		{
			name = "challenge movs",
			input = #load("testdata/listing_0040_challenge_movs"),
			expected = "mov ax, [bx + di - 37]\n" +
			"mov [si - 300], cx\n" +
			"mov dx, [bx - 32]\n" +
			"mov [bp + di], byte 7\n" +
			"mov [di + 901], word 347\n" +
			"mov bp, [5]\n" +
			"mov bx, [3458]\n" +
			"mov ax, [2555]\n" +
			"mov ax, [16]\n" +
			"mov [2554], ax\n" +
			"mov [15], ax\n",
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
