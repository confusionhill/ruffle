#!/usr/bin/env bash
exec cargo run --manifest-path tools/as3-decompiler/Cargo.toml -p as3-decompiler-gui -- "$@"
