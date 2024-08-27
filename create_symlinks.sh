#!/bin/bash

# Navigate to the target directory
cd debian/usr/hobot/lib || { echo "Directory not found"; exit 1; }

# List of base library names
libs=(
    "libalog.so"
    "libcam.so"
    "libhbipcfhal.so"
    "libhbmem.so"
    "libhbplayer.so"
    "libmultimedia.so"
    "libota_common.so"
    "libte600_engine.so"
    "libupdate.so"
    "libvpf.so"
)

# Loop through each library
for lib in "${libs[@]}"; do
    # Find the corresponding versioned file
    file=$(ls ${lib}* 2>/dev/null | grep -E "${lib}.[0-9]+(\.[0-9]+)*$" | sort -V | tail -n 1)

    # If the file exists, create a symbolic link
    if [[ -n "$file" ]]; then
        ln -sf "$file" "$lib"
        echo "Created symlink: $lib -> $file"
    else
        echo "No versioned file found for $lib"
    fi
done
