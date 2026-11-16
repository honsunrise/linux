# SPDX-License-Identifier: GPL-2.0
#
# The Sophgo/Cvitek ION allocator: the Android staging ION of the Sophgo 5.10
# kernel (sophgo/linux_5.10 @ d0486a96, drivers/staging/android/ion) with the
# cvitek carveout heap and /dev/ion glue, ported in-tree. Only what the osdrv
# multimedia stack uses: the ION core, the carveout heap and the cvitek glue.
# Left out (as upstream): the system/CMA/chunk heaps, 32-bit compat, ashmem.

obj-$(CONFIG_SOPHGO_ION) += cvi_ion.o
cvi_ion-y := ion/ion.o \
	ion/ion_heap.o \
	ion/ion_carveout_heap.o \
	ion/cvitek/cvitek_ion.o \
	ion/cvitek/cvitek_ion_alloc.o \
	ion/cvitek/cvitek_ion_debugfs.o

ccflags-y += -I$(src)/ion -I$(src)/uapi
