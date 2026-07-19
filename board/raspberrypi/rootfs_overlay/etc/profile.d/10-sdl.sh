#!/bin/sh
# SDL uses the KMS/DRM backend on the Pi console
export SDL_VIDEODRIVER=kmsdrm
# pick the first DRM device
# export SDL_KMSDRM_DEVICE_INDEX=0