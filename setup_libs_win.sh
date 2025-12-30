#!/bin/bash

BUILDDIR="buildwin"
pushd c_libs
export PATH=$PATH:$(pwd)
popd
echo $PATH

pushd c_libs/libepoxy
rm -rf $BUILDDIR
meson setup $BUILDDIR  -Ddefault_library=static -Dbuildtype=release -Dglx=no -Dx11=false -Dtests=false --cross-file ../meson_cross.txt
meson compile -C $BUILDDIR

popd
