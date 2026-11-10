# SPDX-License-Identifier: GPL-2.0
#
# Sophgo SG200x (cv181x) vendor drivers, imported in-tree.

# The vendor ION Kconfig symbols. They are not Kconfig symbols of this tree:
# they select the vendor ABI of the imported allocator (struct ion_buffer
# grows paddr/name, ion_alloc() takes the extra out pointer, the carveout
# heap is mandatory). ion/ and every osdrv module must see the *same*
# values: a mismatch silently changes struct ion_buffer between ion.ko and
# its users. subdir-ccflags-y covers this Makefile and every subdirectory.
subdir-ccflags-y += -DCONFIG_ION=1 -DCONFIG_ION_CARVEOUT_HEAP=1 \
		    -DCONFIG_ION_CVITEK=1

obj-$(CONFIG_SOPHGO_ION) += ion/
obj-$(CONFIG_SOPHGO_VENDOR) += osdrv/
