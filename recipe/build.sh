#!/bin/bash

set -ex

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

if [[ -f "libcody/build-aux/config.sub" ]]; then
  rm libcody/build-aux/config.sub
  cp config.sub libcody/build-aux/config.sub
fi

# Undo conda-build madness
export host_platform=$target_platform
export target_platform=$cross_target_platform
# set the TARGET variable. HOST and BUILD are already set by the compilers/conda-build
export TARGET=${macos_machine}
# clang emits a ton of warnings
export NO_WARN_CFLAGS="-Wno-array-bounds -Wno-unknown-warning-option -Wno-deprecated -Wno-mismatched-tags -Wno-unused-command-line-argument -Wno-ignored-attributes"
# Remove C++ flags as libcody expects exactly C++11
export CXXFLAGS="$(echo $CXXFLAGS | sed s/-std=c++[0-9]*/-std=c++11/g)"

export enable_darwin_at_rpath=yes

sed -i.bak 's/cp xgcc/echo cp xgcc/g' gcc/Makefile.in
sed -i.bak 's/cp gfortran/echo cp gfortran/g' gcc/fortran/Make-lang.in
# GCC 13+
sed -i.bak 's@rm -f include-fixed/README;@@g' gcc/Makefile.in
# GCC <=12
sed -i.bak 's@rm -f include-fixed/README@@g' gcc/Makefile.in
sed -i.bak 's@rm -rf include-fixed; mkdir include-fixed@echo rm -rf include-fixed; echo mkdir include-fixed@g' gcc/Makefile.in
sed -i.bak 's@cp $(srcdir)/../fixincludes/README-fixinc@pwd; ls -alh include-fixed; echo cp $(srcdir)/../fixincludes/README-fixinc@g' gcc/Makefile.in

# conda binary prefix rewriting fails if the variables are not volatile
sed -i.bak 's/static const char \*const standard_/static const char * volatile standard_/g' gcc/gcc.c*

if [[ "$host_platform" != "$build_platform" ]]; then
    # We need to compile GFORTRAN_FOR_TARGET and GCC_FOR_TARGET
    mkdir -p build_host
    pushd build_host
    if [[ "$build_platform" == "$target_platform" ]]; then
       extra_host_options="--with-native-system-header-dir=$CONDA_BUILD_SYSROOT/usr/include"
    fi
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
       --with-isl=${BUILD_PREFIX} \
       $extra_host_options

    mkdir -p gcc/include-fixed
    cp ../gcc/gcc-ar.cc gcc/gcc-nm.cc || cp ../gcc/gcc-ar.c gcc/gcc-nm.c
    cp ../gcc/gcc-ar.cc gcc/gcc-ranlib.cc || cp ../gcc/gcc-ar.c gcc/gcc-ranlib.c
    cp ../fixincludes/README-fixinc gcc/include-fixed/README
    ln -sf $PWD/gcc/xgcc $PWD/gcc/gcc-cross
    ln -sf $PWD/gcc/gfortran $PWD/gcc/gfortran-cross

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

mkdir -p build_conda
cd build_conda

# libatomic is having trouble with pthreads and stack protector checks
# for gcc 11 on osx-arm64
if [[ "$host_platform" != "$build_platform" ]]; then
  export CFLAGS=${CFLAGS//"-fstack-protector-strong"/"-fno-stack-protector"}
  export CXXFLAGS=${CXXFLAGS//"-fstack-protector-strong"/"-fno-stack-protector"}
  export CPPFLAGS=${CPPFLAGS//"-fstack-protector-strong"/"-fno-stack-protector"}
fi

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
    --enable-darwin-at-rpath \
    ${extra_configure_options}

mkdir -p gcc/include-fixed
cp ../gcc/gcc-ar.cc gcc/gcc-nm.cc || cp ../gcc/gcc-ar.c gcc/gcc-nm.c
cp ../gcc/gcc-ar.cc gcc/gcc-ranlib.cc || cp ../gcc/gcc-ar.c gcc/gcc-ranlib.c
cp ../fixincludes/README-fixinc gcc/include-fixed/README
ln -sf $PWD/gcc/xgcc $PWD/gcc/gcc-cross
ln -sf $PWD/gcc/gfortran $PWD/gcc/gfortran-cross

echo "Building a compiler that runs on ${HOST} and targets ${TARGET}"
if [[ "$host_platform" == "$target_platform" ]]; then
  # Build if the compiler is a cross-native/native compiler

  # Make sure that the libgomp configure script knows that the fortran
  # compiler used is GNU. Otherwise the standard fortran modules for
  # libgomp are not installed. TODO: figure out why the configure script thinks it isn't.
  if [[ "$host_platform" != "$build_platform" ]]; then
    export ac_cv_fc_compiler_gnu=${TARGET}-gfortran
    export FC=${TARGET}-gfortran
    export ac_cv_prog_FC=$FC
    $FC --version
    sed -i.bak "s/USE_FORTRAN_FALSE=.*/USE_FORTRAN_FALSE='#'/g" $SRC_DIR/libgomp/configure
    sed -i.bak "s/USE_FORTRAN_TRUE=.*/USE_FORTRAN_TRUE=/g" $SRC_DIR/libgomp/configure
  fi

  make -j"${CPU_COUNT}" || (cat $TARGET/libquadmath/*.log && false)
  cat $TARGET/libquadmath/*.log
  make install-strip -j${CPU_COUNT}
  rm $PREFIX/lib/libgomp.dylib
  rm $PREFIX/lib/libgomp.1.dylib
  ln -s $PREFIX/lib/libomp.dylib $PREFIX/lib/libgomp.dylib
  ln -s $PREFIX/lib/libomp.dylib $PREFIX/lib/libgomp.1.dylib

  rm ${PREFIX}/lib/libgfortran.spec
  sed "s#@CONDA_PREFIX@#$PREFIX#g" $RECIPE_DIR/libgfortran.spec > libgfortran.spec
  if [[ "$target_platform" == "osx-arm64" && "$gfortran_version" == "11.3.0" ]]; then
    sed -i.bak "s#-lquadmath##g" libgfortran.spec
  fi
  mv libgfortran.spec ${PREFIX}/lib/libgfortran.spec

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

mv ${PREFIX}/libexec/gcc/${TARGET}/${gfortran_version}/cc1 ${PREFIX}/libexec/gcc/${TARGET}/${gfortran_version}/cc1.bin
sed "s#@PATH@#${PREFIX}/libexec/gcc/${TARGET}/${gfortran_version}#g" ${RECIPE_DIR}/cc1 > ${PREFIX}/libexec/gcc/${TARGET}/${gfortran_version}/cc1
chmod +x ${PREFIX}/libexec/gcc/${TARGET}/${gfortran_version}/cc1

if [[ ! -f $PREFIX/bin/${TARGET}-gfortran ]]; then
  mv ${PREFIX}/bin/gfortran ${PREFIX}/bin/${TARGET}-gfortran
  # -ln -sf ${PREFIX}/bin/${TARGET}-gfortran ${PREFIX}/bin/gfortran
fi
