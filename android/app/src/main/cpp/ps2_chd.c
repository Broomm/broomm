/* Bounded, read-only CHD sector access in the unprivileged Android app. */
#include <jni.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>
#include <libchdr/chd.h>

enum { sector_bytes = 2048, max_hunk_bytes = 1024 * 1024 };
struct reader {
    FILE *file;
    chd_file *chd;
    const chd_header *header;
    uint8_t *hunk;
    uint32_t cached_hunk;
};

static void close_reader(struct reader *r) {
    if (r->chd) chd_close(r->chd);
    if (r->file) fclose(r->file);
    free(r->hunk);
    free(r);
}

JNIEXPORT jlong JNICALL Java_app_broomm_broomm_Armsx2Chd_open(
        JNIEnv *env, jobject object, jint descriptor) {
    (void)env;
    (void)object;
    const uint64_t max_bytes = 10ULL * 1024 * 1024 * 1024;
    struct stat info;
    if (fstat(descriptor, &info) || !S_ISREG(info.st_mode) ||
        info.st_size < 124 || (uint64_t)info.st_size > max_bytes) return 0;
    struct reader *r = calloc(1, sizeof(*r));
    if (!r) return 0;
    int fd = dup(descriptor);
    if (fd < 0) goto fail;
    r->file = fdopen(fd, "rb");
    if (!r->file) { close(fd); goto fail; }
    chd_header header;
    if (chd_read_header_file(r->file, &header) != CHDERR_NONE || header.version != 5 ||
        (header.unitbytes != sector_bytes && header.unitbytes != 2352 && header.unitbytes != 2448) ||
        header.hunkbytes < header.unitbytes || header.hunkbytes > max_hunk_bytes ||
        header.hunkbytes % header.unitbytes || header.logicalbytes % header.unitbytes ||
        header.logicalbytes < 17ULL * header.unitbytes || header.logicalbytes > max_bytes ||
        header.totalhunks == 0 || header.totalhunks > 2000000) goto fail;
    for (unsigned i = 0; i < sizeof(header.parentsha1); ++i)
        if (header.parentsha1[i]) goto fail;
    if (chd_open_file(r->file, CHD_OPEN_READ, NULL, &r->chd) != CHDERR_NONE) goto fail;
    r->header = chd_get_header(r->chd);
    if (!r->header || r->header->hunkbytes != header.hunkbytes ||
        r->header->unitbytes != header.unitbytes || r->header->logicalbytes != header.logicalbytes) goto fail;
    r->hunk = malloc(header.hunkbytes);
    if (!r->hunk) goto fail;
    r->cached_hunk = UINT32_MAX;
    return (jlong)(uintptr_t)r;
fail:
    close_reader(r);
    return 0;
}

JNIEXPORT jlongArray JNICALL Java_app_broomm_broomm_Armsx2Chd_geometry(
        JNIEnv *env, jobject object, jlong handle) {
    (void)object;
    struct reader *r = (struct reader *)(uintptr_t)handle;
    jlong dimensions[] = { (jlong)(r->header->logicalbytes / r->header->unitbytes), r->header->unitbytes };
    jlongArray result = (*env)->NewLongArray(env, 2);
    if (result) (*env)->SetLongArrayRegion(env, result, 0, 2, dimensions);
    return result;
}

JNIEXPORT jbyteArray JNICALL Java_app_broomm_broomm_Armsx2Chd_sector(
        JNIEnv *env, jobject object, jlong handle, jlong index, jint offset) {
    (void)object;
    struct reader *r = (struct reader *)(uintptr_t)handle;
    const chd_header *h = r->header;
    if (index < 0 || (uint64_t)index >= h->logicalbytes / h->unitbytes ||
        offset < 0 || (uint32_t)offset + sector_bytes > h->unitbytes) return NULL;
    uint64_t position = (uint64_t)index * h->unitbytes + (uint32_t)offset;
    uint32_t hunk = (uint32_t)(position / h->hunkbytes);
    uint32_t start = (uint32_t)(position % h->hunkbytes);
    if (hunk >= h->totalhunks || start + sector_bytes > h->hunkbytes) return NULL;
    if (r->cached_hunk != hunk) {
        r->cached_hunk = UINT32_MAX;
        if (chd_read(r->chd, hunk, r->hunk) != CHDERR_NONE) return NULL;
        r->cached_hunk = hunk;
    }
    jbyteArray result = (*env)->NewByteArray(env, sector_bytes);
    if (result) (*env)->SetByteArrayRegion(env, result, 0, sector_bytes, (const jbyte *)(r->hunk + start));
    return result;
}

JNIEXPORT void JNICALL Java_app_broomm_broomm_Armsx2Chd_close(
        JNIEnv *env, jobject object, jlong handle) {
    (void)env;
    (void)object;
    close_reader((struct reader *)(uintptr_t)handle);
}
