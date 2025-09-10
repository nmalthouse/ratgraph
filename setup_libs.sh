#!/bin/bash

pushd c_libs/freetype_build
rm -rf build
meson setup build -Dbrotli=disabled -Dbzip2=disabled -Dharfbuzz=disabled -Dpng=disabled -Dzlib=disabled -Ddefault_library=static
meson compile -C build

popd

pushd c_libs/libepoxy
rm -rf build
meson setup build  -Ddefault_library=static -Dbuildtype=release
meson compile -C build

popd

