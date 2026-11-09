LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_MODULE := broomm_root_process
LOCAL_SRC_FILES := root_process.c
LOCAL_CFLAGS := -std=c11 -Wall -Wextra -Werror -fvisibility=hidden
LOCAL_LDFLAGS := -Wl,-z,max-page-size=16384
include $(BUILD_SHARED_LIBRARY)
