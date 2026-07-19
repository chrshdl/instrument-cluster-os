#!/bin/sh
set -eu

# Mount /data if it isn't already
mountpoint -q /data || mount /data || true

# Setup OverlayFS for /etc and /var
for dir in etc var; do
    lower="/${dir}"
    upper="/data/upper/${dir}"
    work="/data/work/${dir}"
    mkdir -p "$upper" "$work"
    mount -t overlay overlay \
        -o lowerdir="$lower",upperdir="$upper",workdir="$work" \
        "/${dir}"
done
