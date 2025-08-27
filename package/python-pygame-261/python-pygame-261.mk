################################################################################
#
# python-pygame-261
#
################################################################################

PYTHON_PYGAME_261_VERSION = 79807da84c9bacf8df5a177763e14c924e3b15e2
PYTHON_PYGAME_261_SITE = $(call github,pygame,pygame,$(PYTHON_PYGAME_261_VERSION))

PYTHON_PYGAME_261_LICENSE = LGPL-2.1+
PYTHON_PYGAME_261_LICENSE_FILES = LGPL

PYTHON_PYGAME_261_SETUP_TYPE = pep517

PYTHON_PYGAME_261_DEPENDENCIES = sdl2 sdl2_image sdl2_ttf libpng jpeg freetype

PYTHON_PYGAME_261_ENV += SDL_CONFIG="$(STAGING_DIR)/usr/bin/sdl2-config"

$(eval $(python-package))