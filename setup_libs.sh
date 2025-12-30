#!/bin/bash

pushd c_libs/libepoxy
rm -rf build
meson setup build  -Ddefault_library=static -Dbuildtype=release -Dtests=false
meson compile -C build

popd

