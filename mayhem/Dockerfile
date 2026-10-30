# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile (SMALL form, PREFERRED) — builds ON TOP of the org C/C++ base
# image (ghcr.io/savantenvs/base). The base already provides debian + clang/llvm +
# libFuzzer/afl++ + the identities + the build-contract ENV, so this only adds the
# per-commit build (built on top of the prebuilt base, rather than building the toolchain in-image).
#
# Build (from the repo root):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) \
#       [--build-arg SOURCE_DATE_EPOCH=$(date +%s)] \
#       -t mytag .

# The org base, pinned to a fixed DATE-tagged base (YYYYMMDD; shared by all integrations
# minted against it). Use the current dated tag; pin by digest in production: ...base@sha256:<digest>.
FROM ghcr.io/savantenvs/base:20261023

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (available to build.sh); do NOT bake it as an ENV — an
# empty value breaks clang ("must be a non-negative decimal integer") both here and for
# any in-image rebuild. build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH

# Sanitizer override: the base exports SANITIZER_FLAGS (ASan+UBSan, halting) as the default.
# To change it for a build (e.g. ASan-only, or add MSan): --build-arg SANITIZER_FLAGS="...".
# Declare it WITHOUT a default (no '='): an undefaulted ARG lets the base ENV flow through to
# build.sh when not passed, and an explicit --build-arg overrides it. (An empty default — `=` —
# would instead shadow the base ENV and silently wipe the sanitizers.)
ARG SANITIZER_FLAGS
# Coverage (optional, off by default): instrument the TEST build to measure how much of the project
# the suite exercises — --build-arg COVERAGE_FLAGS="-fprofile-instr-generate -fcoverage-mapping".
# Empty by default (no effect on the normal oracle build); build.sh appends it to the test build only.
ARG COVERAGE_FLAGS=
# Build parallelism (optional). build.sh falls back to nproc when unset: --build-arg MAYHEM_JOBS=8
ARG MAYHEM_JOBS=

# Build dependencies, vendored prebuilt under /opt/toolchains/lib/<lib> (fixed, $HOME-independent, so the
# air-gapped PATCH re-run of build.sh finds them). Each is the exact version opennn's CMake fetches at
# configure time, downloaded once here with a sha256 check: Eigen 5.0.1 (headers), zlib 1.3.2, libjpeg-turbo
# 3.1.4 (same options as opennn's CMake: static, no SIMD) and googletest 1.18.0, each built once into
# <lib>/{include,lib}. Only the OpenMP runtime (libomp) comes from apt.
USER root
RUN [ -n "$SOURCE_DATE_EPOCH" ] && repro-sources-list.sh || true ; \
    apt-get update && apt-get install -yq --no-install-recommends libomp-19-dev \
 && rm -rf /var/lib/apt/lists/*
ENV LIB_DIR=/opt/toolchains/lib
RUN set -eux; \
    fetch() { curl -fsSL -o "/tmp/$1.tar.gz" "$2"; echo "$3  /tmp/$1.tar.gz" | sha256sum -c -; \
              mkdir -p "/tmp/src/$1"; tar -xzf "/tmp/$1.tar.gz" -C "/tmp/src/$1" --strip-components=1; }; \
    export CC=clang CXX=clang++ CFLAGS="-O2 -g0 -fPIC" CXXFLAGS="-O2 -g0 -fPIC"; \
    mkdir -p "$LIB_DIR/eigen"; \
    fetch eigen https://gitlab.com/libeigen/eigen/-/archive/5.0.1/eigen-5.0.1.tar.gz \
          e9c326dc8c05cd1e044c71f30f1b2e34a6161a3b6ecf445d56b53ff1669e3dec; \
    cp -a /tmp/src/eigen/Eigen /tmp/src/eigen/unsupported "$LIB_DIR/eigen/"; \
    fetch zlib https://github.com/madler/zlib/releases/download/v1.3.2/zlib-1.3.2.tar.gz \
          bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16; \
    cmake -S /tmp/src/zlib -B /tmp/b/zlib -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$LIB_DIR/zlib" \
          -DZLIB_BUILD_SHARED=OFF -DZLIB_BUILD_STATIC=ON -DZLIB_BUILD_TESTING=OFF; \
    cmake --build /tmp/b/zlib && cmake --install /tmp/b/zlib; \
    fetch libjpeg-turbo https://github.com/libjpeg-turbo/libjpeg-turbo/archive/refs/tags/3.1.4.tar.gz \
          3a581ad5a3060cee69487aae0bc71a1f3be94b89f92215e32b43742ec4a5055c; \
    cmake -S /tmp/src/libjpeg-turbo -B /tmp/b/jpeg -G Ninja -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX="$LIB_DIR/libjpeg-turbo" -DCMAKE_INSTALL_LIBDIR=lib \
          -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_JAVA=OFF -DWITH_SIMD=OFF -DWITH_TESTS=OFF \
          -DWITH_TOOLS=OFF -DWITH_TURBOJPEG=OFF; \
    cmake --build /tmp/b/jpeg && cmake --install /tmp/b/jpeg --component include && cmake --install /tmp/b/jpeg --component lib; \
    fetch googletest https://github.com/google/googletest/releases/download/v1.18.0/googletest-1.18.0.tar.gz \
          6e3191c1455468b3fc35a417fb565c1c5071aee1b7e7f85e30cf48a98d37d8b5; \
    cmake -S /tmp/src/googletest -B /tmp/b/gtest -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=20 \
          -DCMAKE_INSTALL_PREFIX="$LIB_DIR/googletest" -DCMAKE_INSTALL_LIBDIR=lib -DBUILD_GMOCK=OFF; \
    cmake --build /tmp/b/gtest && cmake --install /tmp/b/gtest; \
    rm -rf /tmp/src /tmp/b /tmp/*.tar.gz; \
    chmod -R a+rX "$LIB_DIR"; ls "$LIB_DIR"/*/lib
USER mayhem

# Source enters from the build CONTEXT (the CI checkout): the FULL repo (incl. .git
# history) is copied to /mayhem as `mayhem`; build.sh builds in place.
USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

# Anything a Dockerfile step materializes into the tree (downloaded fixtures, generated headers,
# vendored deps) MUST be committed or (re)created by build.sh: rlenv's patch grader runs
# `git clean -ffdX` before every graded build, so a gitignored, untracked file is gone by then and
# every honest patch scores zero (SPEC §6.2 item 16; verify-repo.sh checks it).
#
# OPTIONAL compile-cache pre-fill (SPEC §6.2 item 18). Bases minted with /opt/mayhem/ccache/prefill
# run the build under rlenv's pinned ccache, so the patch grader's first (otherwise cold) rebuild is
# warm — this is what keeps large C/C++ targets inside the build time limit. Older bases fall back to
# the plain build; a missing or stale pre-fill only costs a cold cache. Never enable ccache in
# build.sh or via ENV/PATH, and keep the compiler resolving by name (CC=clang) or nothing is cached.
RUN if [ -x /opt/mayhem/ccache/prefill ]; then /opt/mayhem/ccache/prefill bash mayhem/build.sh; \
    else bash mayhem/build.sh; fi

# Run the project's functional tests at build time IF the repo ships them (mayhem/test.sh is
# optional — omit it only when the repo has no tests meaningful for RL). A failing suite fails the
# image build, so the commit image is guaranteed to build AND pass its own tests.
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
