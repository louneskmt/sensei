# build the web interface
FROM node:16 as web-admin-builder

WORKDIR /build

COPY . .

WORKDIR /build/web-admin
RUN npm install
RUN npm run build

# prepare image for build (install nightly, add rustfmt, install cargo-chef for build optimization)
FROM rust:1.62 as sensei-prepare

RUN rustup toolchain install nightly --allow-downgrade -c rustfmt
RUN rustup component add rustfmt --toolchain nightly
RUN cargo +nightly install --git https://github.com/louneskmt/cargo-chef --branch nightly-unstable -Z sparse-registry
WORKDIR /build

# we use cargo-chef (https://github.com/LukeMathWalker/cargo-chef) to optimize the build process
# it allows us to cache the dependencies build process and to use the cache for the next build
FROM sensei-prepare as sensei-planner

COPY . .
RUN cargo chef prepare --recipe-path recipe.json

# build sensei
FROM sensei-prepare as sensei-builder

COPY --from=sensei-planner /build/recipe.json recipe.json

# build dependencies
RUN cargo chef cook --nightly --release --recipe-path recipe.json -Z sparse-registry

# copy source tree
COPY . .
COPY --from=web-admin-builder /build/web-admin/build/ /build/web-admin/build/

# we have to use sparse-registry nightly cargo feature to avoid running out of RAM:
# https://github.com/rust-lang/cargo/issues/10781
RUN cargo +nightly build --release -Z sparse-registry

# our final base
FROM debian:buster-slim as final

# add sensei user
RUN addgroup --system -gid 1000 sensei && \
    adduser --system --uid 1000 --gid 1000 --home /data --gecos "" sensei

USER sensei
WORKDIR /data

# copy the build artifact from the build stage
COPY --from=sensei-builder /build/target/release/senseid /bin/senseid
COPY --from=sensei-builder /build/target/release/senseicli /bin/senseicli

ENTRYPOINT ["/bin/senseid"]
