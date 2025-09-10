#!/bin/bash

BUILDDIR="buildwin"
pushd c_libs
export PATH=$PATH:$(pwd)
popd
echo $PATH

pushd c_libs/freetype_build
rm -rf $BUILDDIR
meson setup $BUILDDIR -Dbrotli=disabled -Dbzip2=disabled -Dharfbuzz=disabled -Dpng=disabled -Dzlib=disabled -Ddefault_library=static --cross-file ../meson_cross.txt
meson compile -C $BUILDDIR

popd

pushd c_libs/libepoxy
rm -rf $BUILDDIR
meson setup $BUILDDIR  -Ddefault_library=static -Dbuildtype=release -Dglx=no -Dx11=false -Dtests=false --cross-file ../meson_cross.txt
meson compile -C $BUILDDIR

popd
