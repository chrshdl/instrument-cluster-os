################################################################################
#
# python-pyopengl
#
################################################################################

PYTHON_PYOPENGL_VERSION = 3.1.10
PYTHON_PYOPENGL_SOURCE = pyopengl-$(PYTHON_PYOPENGL_VERSION).tar.gz
PYTHON_PYOPENGL_SITE = https://files.pythonhosted.org/packages/6f/16/912b7225d56284859cd9a672827f18be43f8012f8b7b932bc4bd959a298e
PYTHON_PYOPENGL_SETUP_TYPE = setuptools
PYTHON_PYOPENGL_LICENSE = BSD-3-Clause
PYTHON_PYOPENGL_LICENSE_FILES = license.txt

# Ensure Mesa/OpenGL libraries are built BEFORE this package installs
PYTHON_PYOPENGL_DEPENDENCIES = libegl libgles

$(eval $(python-package))