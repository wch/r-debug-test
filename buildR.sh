#!/bin/bash
set -x

# Env vars used by configure. Get settings from `R CMD config CFLAGS` and
# CXXFLAGS, but without `-O2` and `-fdebug-prefix-map=...`. The latter causes
# the configure script to fail on Docker Hub when used with
# `-fsanitize=address`.
export LIBnn=lib
export CFLAGS="-fstack-protector-strong -Wformat -Werror=format-security -Wdate-time -D_FORTIFY_SOURCE=2 -g -O0 -Wall"
export CXXFLAGS="-fstack-protector-strong -Wformat -Werror=format-security -Wdate-time -D_FORTIFY_SOURCE=2 -g -g -O0 -Wall"


# =============================================================================
# Customized settings for various builds
# =============================================================================
if [[ $# -eq 0 ]]; then
    suffix=""
    configure_flags=""

elif [[ $1 = "valgrind2" ]]; then
    suffix="valgrind2"
    configure_flags="--with-valgrind-instrumentation=2"

elif [[ $1 = "san" ]]; then
    suffix="san"
    # According to https://cran.r-project.org/doc/manuals/r-devel/R-exts.html#Using-Undefined-Behaviour-Sanitizer
    # there is a problem compiling R gcc and openmp.
    configure_flags="--disable-openmp"
    # Settings borrowed from:
    # http://www.stats.ox.ac.uk/pub/bdr/memtests/README.txt
    # https://github.com/rocker-org/r-devel-san/blob/mzaster/Dockerfile
    # But without -mtune=native because the Docker image needs to be portable.
    export CXX="g++ -fsanitize=address,undefined,bounds-strict -fno-omit-frame-pointer"
    export CFLAGS="${CFLAGS} -pedantic -fsanitize=address"
    export FFLAGS="${CFLAGS}"
    export FCFLAGS="${CFLAGS}"
    export CXXFLAGS="${CFLAGS} -pedantic"
    # Using -no-pie is a workaround for a kernel bug with ASAN which is
    # present on Docker Hub build machines. From:
    # https://github.com/google/sanitizers/issues/856#issuecomment-327657374
    # Once the Docker Hub build machines get a new kernel (other than
    # 4.4.0-93-generic), this can be removed.
    if [[ "$(uname -r)" = "4.4.0-93-generic" ]]; then
        export LDFLAGS="${LDFLAGS} -no-pie"
    fi
    export MAIN_LDFLAGS="-fsanitize=address,undefined"

    # Did not copy over ~/.R/Makevars from BDR's page because other R
    # installations would also read that file, and packages built for those
    # other R installations would inherit settings meant for this build.
elif [[ "$1" = "strictbarrier" ]]; then
    suffix="strictbarrier"
    configure_flags="--enable-strict-barrier"

elif [[ "$1" = "assertthread" ]]; then
    suffix="assertthread"
    configure_flags=""
fi

dirname="RD${suffix}"

# =============================================================================
# Build
# =============================================================================
mkdir -p /usr/local/${dirname}/

cd /tmp/r-source

./configure \
    --prefix=/usr/local/${dirname} \
    --enable-R-shlib \
    --without-blas \
    --without-lapack \
    --with-readline \
    ${configure_flags}

cat config.log

# Clean up, but don't delete rsync'ed packages
git clean -xdf -e src/library/Recommended/
rm src/library/Recommended/Makefile
