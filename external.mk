include $(sort $(wildcard $(BR2_EXTERNAL_INSTRUMENT_CLUSTER_OS_PATH)/package/*/*.mk))


PYTHON_NUMPY_CONF_OPTS += -Dblas=openblas -Dlapack=openblas
PYTHON_NUMPY_DEPENDENCIES += openblas
PYTHON_SCIPY_CONF_OPTS += -Dblas=openblas -Dlapack=openblas
PYTHON_SCIPY_DEPENDENCIES += openblas python-numpy
