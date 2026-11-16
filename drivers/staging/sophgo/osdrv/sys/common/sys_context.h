#ifndef __SYS_CONTEXT_H__
#define __SYS_CONTEXT_H__

#include <linux/types.h>
#include <linux/cvi_comm_sys.h>
#include "base.h"

struct sys_info {
	char version[VERSION_NAME_MAXLEN];
	CVI_U32 chip_id;
};

struct sys_mode_cfg {
	VI_VPSS_MODE_S vivpss_mode;
	VPSS_MODE_S vpss_mode;
};

struct sys_ctx_info {
	struct sys_info sys_info;
	struct sys_mode_cfg mode_cfg;
	atomic_t sys_inited;
};

struct mem_mapping {
	CVI_U64 phy_addr;
	CVI_S32 dmabuf_fd;
	void *vir_addr;
	void *dmabuf;
	pid_t fd_pid;
	void *ionbuf;
	/* reCamera: the /dev/cvi-sys file of a userspace allocation (NULL for
	 * the kernel's own); SYS_ION_ORPHAN once that file is released */
	void *owner;
};

CVI_S32 sys_ctx_init(void);
struct sys_ctx_info *sys_get_ctx(void);
CVI_S32 sys_ctx_mem_put(struct mem_mapping *mem_config);
CVI_S32 sys_ctx_mem_get(struct mem_mapping *mem_config);
CVI_S32 sys_ctx_mem_dump(void);
CVI_S32 sys_ctx_mem_get_owned(void *owner, struct mem_mapping *mem_config);
CVI_S32 sys_ctx_mem_set_owner(void *owner, void *new_owner);

CVI_U32 sys_ctx_get_chipid(void);
CVI_U8 *sys_ctx_get_version(void);
void *sys_ctx_get_sysinfo(void);

VPSS_MODE_E sys_ctx_get_vpssmode(void);

void sys_ctx_release_bind(void);
CVI_S32 sys_ctx_bind(MMF_CHN_S *pstSrcChn, MMF_CHN_S *pstDestChn);
CVI_S32 sys_ctx_unbind(MMF_CHN_S *pstSrcChn, MMF_CHN_S *pstDestChn);

CVI_S32 sys_ctx_get_bindbysrc(MMF_CHN_S *pstSrcChn, MMF_BIND_DEST_S *pstBindDest);
CVI_S32 sys_ctx_get_bindbydst(MMF_CHN_S *pstDestChn, MMF_CHN_S *pstSrcChn);



#endif  /* __SYS_CONTEXT_H__ */

