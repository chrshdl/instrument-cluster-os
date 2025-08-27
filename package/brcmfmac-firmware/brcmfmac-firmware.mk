BRCMFMAC_FIRMWARE_VERSION := 20250311
BRCMFMAC_FIRMWARE_SOURCE := linux-firmware-$(BRCMFMAC_FIRMWARE_VERSION).tar.gz
BRCMFMAC_FIRMWARE_SITE := https://www.kernel.org/pub/linux/kernel/firmware

define BRCMFMAC_FIRMWARE_INSTALL_TARGET_CMDS
  $(INSTALL) -D -m 0644 $(@D)/cypress/cyfmac43455-sdio.bin $(TARGET_DIR)/lib/firmware/brcm/brcmfmac43455-sdio.bin

  $(INSTALL) -D -m 0644 $(@D)/cypress/cyfmac43455-sdio.clm_blob $(TARGET_DIR)/lib/firmware/brcm/brcmfmac43455-sdio.clm_blob

  $(INSTALL) -D -m 0644 $(@D)/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt $(TARGET_DIR)/lib/firmware/brcm/brcmfmac43455-sdio.txt

  $(INSTALL) -D -m 0644 $(@D)/cypress/cyfmac43455-sdio.bin $(TARGET_DIR)/lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,5-model-b.bin

  $(INSTALL) -D -m 0644 $(@D)/cypress/cyfmac43455-sdio.clm_blob $(TARGET_DIR)/lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,5-model-b.clm_blob

  $(INSTALL) -D -m 0644 $(@D)/brcm/brcmfmac43455-sdio.raspberrypi,4-model-b.txt $(TARGET_DIR)/lib/firmware/brcm/brcmfmac43455-sdio.raspberrypi,5-model-b.txt
endef

$(eval $(generic-package))
