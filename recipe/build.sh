#!/bin/bash

set -e

function start_spinner {
    if [ -n "$SPINNER_PID" ]; then
        return
    fi

    >&2 echo "Building libraries..."
    # Start a process that runs as a keep-alive
    # to avoid travis quitting if there is no output
    (while true; do
        sleep 60
        >&2 echo "Still building..."
    done) &
    SPINNER_PID=$!
    disown
}

function stop_spinner {
    if [ ! -n "$SPINNER_PID" ]; then
        return
    fi

    kill $SPINNER_PID
    unset SPINNER_PID

    >&2 echo "Building libraries finished."
}

start_spinner

set -x

# Undo conda-build madness
export host_platform=$target_platform
export target_platform=$cross_target_platform
# set the TARGET variable. HOST and BUILD are already set by the compilers/conda-build
export TARGET=${macos_machine}
# clang emits a ton of warnings
export NO_WARN_CFLAGS="-Wno-array-bounds -Wno-unknown-warning-option -Wno-deprecated -Wno-mismatched-tags -Wno-unused-command-line-argument -Wno-ignored-attributes"

if [[ "$host_platform" != "$build_platform" && "$host_platform" == "$target_platform" ]]; then
    # We need to compile the target libraries when host_platform == target_platform, but if
    # build_platform != host_platform, we need gfortran (to build libgfortran) and gcc (to build libgcc).
    # So, we need a compiler that can target target_platform, but can run on build_platform.
    mkdir -p build_host
    pushd build_host
    CC=$CC_FOR_BUILD CXX=$CXX_FOR_BUILD AR="$($CC_FOR_BUILD -print-prog-name=ar)" LD="$($CC_FOR_BUILD -print-prog-name=ld)" \
         RANLIB="$($CC_FOR_BUILD -print-prog-name=ranlib)" NM="$($CC_FOR_BUILD -print-prog-name=nm)"  \
         CFLAGS="$NO_WARN_CFLAGS" CXXFLAGS="$NO_WARN_CFLAGS" CPPFLAGS="$NO_WARN_CFLAGS" \
         LDFLAGS="-L$BUILD_PREFIX/lib -Wl,-rpath,$BUILD_PREFIX/lib" ../configure \
       --prefix=${BUILD_PREFIX} \
       --build=${BUILD} \
       --host=${BUILD} \
       --target=${TARGET} \
       --with-libiconv-prefix=${BUILD_PREFIX} \
       --enable-languages="c,fortran" \
       --disable-multilib \
       --enable-checking=release \
       --disable-bootstrap \
       --disable-libssp \
       --with-gmp=${BUILD_PREFIX} \
       --with-mpfr=${BUILD_PREFIX} \
       --with-mpc=${BUILD_PREFIX} \
       --with-isl=${BUILD_PREFIX}
    echo "Building a compiler that runs on ${BUILD} and targets ${TARGET}"
    make all-gcc -j${CPU_COUNT}
    make install-gcc -j${CPU_COUNT}
    popd
    # For the target compiler to work, it need some tools
    ln -sf ${BUILD_PREFIX}/bin/${TARGET}-ar       ${BUILD_PREFIX}/lib/gcc/${TARGET}/${gfortran_version}/ar
    ln -sf ${BUILD_PREFIX}/bin/${TARGET}-as       ${BUILD_PREFIX}/lib/gcc/${TARGET}/${gfortran_version}/as
    ln -sf ${BUILD_PREFIX}/bin/${TARGET}-nm       ${BUILD_PREFIX}/lib/gcc/${TARGET}/${gfortran_version}/nm
    ln -sf ${BUILD_PREFIX}/bin/${TARGET}-ranlib   ${BUILD_PREFIX}/lib/gcc/${TARGET}/${gfortran_version}/ranlib
    ln -sf ${BUILD_PREFIX}/bin/${TARGET}-strip    ${BUILD_PREFIX}/lib/gcc/${TARGET}/${gfortran_version}/strip
    ln -sf ${BUILD_PREFIX}/bin/${TARGET}-ld       ${BUILD_PREFIX}/lib/gcc/${TARGET}/${gfortran_version}/ld
fi

mkdir build_conda
cd build_conda

if [[ "$target_platform" == osx* ]]; then
    if [[ "$target_platform" == "$host_platform" ]]; then
        export LDFLAGS_FOR_TARGET="$LDFLAGS_FOR_TARGET $LDFLAGS"
        export CFLAGS_FOR_TARGET="$CFLAGS_FOR_TARGET $CFLAGS"
        export CXXFLAGS_FOR_TARGET="$CXXFLAGS_FOR_TARGET $CXXFLAGS"
        export CPPFLAGS_FOR_TARGET="$CPPFLAGS_FOR_TARGET $CPPFLAGS"
    fi
    # $PWD/$TARGET/libgcc is needed because the previous bootstrap compiler we built needs libemutls_w.a
    export LDFLAGS_FOR_TARGET="$LDFLAGS_FOR_TARGET -L$PWD/$TARGET/libgcc -L$CONDA_BUILD_SYSROOT/usr/lib"
    # -isysroot here doesn't work
    export CFLAGS_FOR_TARGET="$CFLAGS_FOR_TARGET -O3 -isystem $CONDA_BUILD_SYSROOT/usr/include $LDFLAGS_FOR_TARGET"
    export CXXFLAGS_FOR_TARGET="$CXXFLAGS_FOR_TARGET -O3 -isystem $CONDA_BUILD_SYSROOT/usr/include $LDFLAGS_FOR_TARGET"
    export CPPFLAGS_FOR_TARGET="$CPPFLAGS_FOR_TARGET -O3 -isystem $CONDA_BUILD_SYSROOT/usr/include $LDFLAGS_FOR_TARGET"
fi

if [[ "$host_platform" == osx* ]]; then
    export LDFLAGS="$LDFLAGS -L$CONDA_BUILD_SYSROOT/usr/lib"
    export CFLAGS="$CFLAGS -isysroot $CONDA_BUILD_SYSROOT $NO_WARN_CFLAGS"
    export CXXFLAGS="$CXXFLAGS -isysroot $CONDA_BUILD_SYSROOT $NO_WARN_CFLAGS"
    export CPPFLAGS="$CPPFLAGS -isysroot $CONDA_BUILD_SYSROOT $NO_WARN_CFLAGS"
fi

if [[ "$build_platform" == "$host_platform" ]]; then
    extra_configure_options="$extra_configure_options --with-native-system-header-dir=$CONDA_BUILD_SYSROOT/usr/include"
fi

../configure \
    --prefix=${PREFIX} \
    --build=${BUILD} \
    --host=${HOST} \
    --target=${TARGET} \
    --with-libiconv-prefix=${PREFIX} \
    --enable-languages=fortran \
    --disable-multilib \
    --enable-checking=release \
    --disable-bootstrap \
    --disable-libssp \
    --with-gmp=${PREFIX} \
    --with-mpfr=${PREFIX} \
    --with-mpc=${PREFIX} \
    --with-isl=${PREFIX} \
    ${extra_configure_options}

echo "Building a compiler that runs on ${HOST} and targets ${TARGET}"
if [[ "$host_platform" == "$target_platform" ]]; then
  # Build if the compiler is a cross-native/native compiler

  # Make sure that the libgomp configure script knows that the fortran
  # compiler used is GNU. Otherwise the standard fortran modules for
  # libgomp are not installed. TODO: figure out why the configure script thinks it isn't.
  export ac_cv_fc_compiler_gnu=yes

  make -j"${CPU_COUNT}" || (cat $TARGET/libgomp/*.log && false)
  make install-strip -j${CPU_COUNT}
  rm $PREFIX/lib/libgomp.dylib
  rm $PREFIX/lib/libgomp.1.dylib
  ln -s $PREFIX/lib/libomp.dylib $PREFIX/lib/libgomp.dylib
  ln -s $PREFIX/lib/libomp.dylib $PREFIX/lib/libgomp.1.dylib

  rm ${PREFIX}/lib/libgfortran.spec
  sed "s#@CONDA_PREFIX@#$PREFIX#g" $RECIPE_DIR/libgfortran.spec > ${PREFIX}/lib/libgfortran.spec

  for file in libgfortran.spec libgomp.spec; do
    mv $PREFIX/lib/$file $PREFIX/lib/gcc/${TARGET}/${gfortran_version}/$file
    ln -s $PREFIX/lib/gcc/${TARGET}/${gfortran_version}/$file $PREFIX/lib/$file
  done
else
  # The compiler is a cross compiler. Only make the compiler. No target libraries
  make all-gcc -j${CPU_COUNT}
  make install-gcc -j${CPU_COUNT}
fi

stop_spinner

ls -al $PREFIX/lib
