#!/usr/bin/env bash
# Sourced by native tools AFTER Nix's Flutter wrapper has added its own SDK.
# Keep the reviewed GTK graph and host ABI, including nested compiler invocations.
: "${BROOMM_LINUX_PKG_CONFIG_PATH:?Run tool/ci/build_linux.sh to select the native SDK}"
unset CFLAGS CXXFLAGS CPPFLAGS LIBRARY_PATH LD_LIBRARY_PATH
unset CMAKE_PREFIX_PATH CMAKE_FRAMEWORK_PATH CMAKE_APPBUNDLE_PATH
unset NIX_LDFLAGS NIX_CFLAGS_COMPILE NIX_CC SDKROOT
export PKG_CONFIG_PATH="$BROOMM_LINUX_PKG_CONFIG_PATH"
export PKG_CONFIG_PATH_FOR_TARGET="$BROOMM_LINUX_PKG_CONFIG_PATH"
export PKG_CONFIG_LIBDIR="$BROOMM_LINUX_PKG_CONFIG_PATH"
export LDFLAGS=-fuse-ld=/usr/bin/ld
