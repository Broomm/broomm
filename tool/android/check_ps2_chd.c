#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <libchdr/chd.h>

static void big_endian(uint8_t *field, uint32_t value) {
    for (int i = 3; i >= 0; --i) {
        field[i] = (uint8_t)value;
        value >>= 8;
    }
}

static chd_error read_header(uint32_t logical_size, size_t stored_size, chd_header *header) {
    uint8_t bytes[CHD_V5_HEADER_SIZE] = {0};
    memcpy(bytes, "MComprHD", 8);
    big_endian(bytes + 8, sizeof(bytes));
    big_endian(bytes + 12, 5);
    big_endian(bytes + 36, logical_size);
    big_endian(bytes + 56, 2048);
    big_endian(bytes + 60, 2048);
    FILE *file = tmpfile();
    assert(file != NULL);
    assert(fwrite(bytes, 1, stored_size, file) == stored_size);
    const chd_error result = chd_read_header_file(file, header);
    assert(fclose(file) == 0);
    return result;
}

int main(void) {
    chd_header header;
    assert(read_header(17 * 2048, CHD_V5_HEADER_SIZE, &header) == CHDERR_NONE);
    assert(header.version == 5 && header.totalhunks == 17 && header.unitbytes == 2048);
    assert(read_header(4096 * 2048, CHD_V5_HEADER_SIZE, &header) == CHDERR_INVALID_DATA);
    assert(read_header(17 * 2048, CHD_V5_HEADER_SIZE - 1, &header) == CHDERR_READ_ERROR);
    puts("PS2 CHD header size and truncation checks passed");
    return 0;
}
