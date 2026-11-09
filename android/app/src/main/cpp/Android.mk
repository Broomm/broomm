LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_MODULE := broomm_root_process
LOCAL_SRC_FILES := root_process.c
LOCAL_CFLAGS := -std=c11 -Wall -Wextra -Werror -fvisibility=hidden
LOCAL_LDFLAGS := -Wl,-z,max-page-size=16384
include $(BUILD_SHARED_LIBRARY)

BROOMM_CHD := ../../../../../vendor/libchdr
include $(CLEAR_VARS)
LOCAL_MODULE := broomm_libchdr
LOCAL_SRC_FILES := $(BROOMM_CHD)/unity.c
LOCAL_C_INCLUDES := $(LOCAL_PATH)/$(BROOMM_CHD)/include \
    $(LOCAL_PATH)/$(BROOMM_CHD)/deps/miniz-3.1.1 \
    $(LOCAL_PATH)/$(BROOMM_CHD)/deps/zstd-1.5.7
LOCAL_CFLAGS := -std=c11 -D_FILE_OFFSET_BITS=64 -fvisibility=hidden
include $(BUILD_STATIC_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := broomm_ps2_disc
LOCAL_SRC_FILES := ps2_chd.c
LOCAL_C_INCLUDES := $(LOCAL_PATH)/$(BROOMM_CHD)/include
LOCAL_STATIC_LIBRARIES := broomm_libchdr
LOCAL_CFLAGS := -std=c11 -D_FILE_OFFSET_BITS=64 -Wall -Wextra -Werror -fvisibility=hidden
LOCAL_LDFLAGS := -Wl,-z,max-page-size=16384 -Wl,--exclude-libs,ALL
include $(BUILD_SHARED_LIBRARY)
