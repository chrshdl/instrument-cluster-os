################################################################################
# python-instrument-cluster
################################################################################

# Always pull latest from main
PYTHON_INSTRUMENT_CLUSTER_SITE_METHOD = git
PYTHON_INSTRUMENT_CLUSTER_SITE = https://github.com/chrshdl/instrument-cluster.git
PYTHON_INSTRUMENT_CLUSTER_VERSION = main

PYTHON_INSTRUMENT_CLUSTER_LICENSE = MIT
PYTHON_INSTRUMENT_CLUSTER_LICENSE_FILES = LICENSE

PYTHON_INSTRUMENT_CLUSTER_SETUP_TYPE = pep517

define PYTHON_INSTRUMENT_CLUSTER_INSTALL_INIT_SYSTEMD
	$(INSTALL) -D -m 0644 $(BR2_EXTERNAL)/package/python-instrument-cluster/instrument-cluster.service \
		$(TARGET_DIR)/usr/lib/systemd/system/instrument-cluster.service
	mkdir -p $(TARGET_DIR)/etc/systemd/system/multi-user.target.wants
	ln -sf /usr/lib/systemd/system/instrument-cluster.service \
		$(TARGET_DIR)/etc/systemd/system/multi-user.target.wants/instrument-cluster.service
endef


$(eval $(python-package))
