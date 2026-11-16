// SPDX-License-Identifier: GPL-2.0
/*
 * CVITEK (Sophgo SG200x) DWMAC glue layer.
 *
 * Ported from the vendor BSP glue (dwmac-cvitek.c) to the mainline stmmac API.
 * The vendor glue is what makes the internal ePHY reachable on this board: it
 * programs the ePHY PHY_ID (0x00435649) before stmmac probes the MDIO bus, and
 * it keeps the MAC clocks enabled instead of letting runtime PM gate them.
 */
#include <linux/clk.h>
#include <linux/etherdevice.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/gpio/consumer.h>
#include <linux/of_net.h>
#include <linux/phy.h>
#include <linux/platform_device.h>
#include <linux/stmmac.h>

#include "stmmac_platform.h"

static u64 cvitek_dma_mask = DMA_BIT_MASK(40);

/*
 * Bring up the internal ePHY. The values and their order are the vendor's
 * (bm_eth_reset_phy in dwmac-cvitek.c): APB access on, release
 * shutdown/dig_rst_n/ana_rst_n, ANA init, program the PHY_ID, then hand the
 * MDIO back to the MAC.
 */
static void cvitek_eth_ephy_init(struct platform_device *pdev)
{
	struct device_node *np = pdev->dev.of_node;
	void __iomem *ephy_base = NULL;
	void __iomem *ephy_top = NULL;
	u32 base_addr = 0, top_addr = 0;
	struct gpio_desc *phy_reset_gpio;

	if (!np)
		return;

	of_property_read_u32(np, "ephy_base_reg", &base_addr);
	of_property_read_u32(np, "ephy_top_reg", &top_addr);

	if (base_addr && top_addr) {
		ephy_base = ioremap(base_addr, 0x80);
		ephy_top = ioremap(top_addr, 0x10);

		if (ephy_base && ephy_top) {
			/* MDIO through the APB interface (0x0804[0]=1) */
			writel(0x0001, ephy_top + 0x4);
			/* release 0x0800[0]=0/shutdown */
			writel(0x0900, ephy_top);
			/* release 0x0800[2]=1/dig_rst_n: MII regs become accessible */
			writel(0x0904, ephy_top);
			/* ANA init (PD/EN), switch to MII-page5 */
			writel(0x0500, ephy_base + 0x7c);
			/* release ANA_PD p5.0x10@[13:8] = 6'b001100 */
			writel(0x0c00, ephy_base + 0x40);
			/* release ANA_EN p5.0x10@[7:0] = 8'b01111110 */
			writel(0x0c7e, ephy_base + 0x40);
			/* release 0x0800[1] = 1/ana_rst_n */
			writel(0x0906, ephy_top);
			/* ANA init, then the PHY_ID */
			writel(0x0500, ephy_base + 0x7c);
			writel(0x0043, ephy_base + 0x8);
			writel(0x5649, ephy_base + 0xc);
			/* switch to MDIO control by the ETH_MAC */
			writel(0x0000, ephy_top + 0x4);
		}
	}

	if (ephy_base)
		iounmap(ephy_base);
	if (ephy_top)
		iounmap(ephy_top);

	/*
	 * Optional external PHY reset line. Not wired on this board: the vendor DT
	 * has phy-reset-gpios commented out, so this normally resolves to NULL.
	 */
	phy_reset_gpio = devm_gpiod_get_optional(&pdev->dev, "phy-reset",
						 GPIOD_OUT_LOW);
	if (IS_ERR(phy_reset_gpio))
		return;

	if (!phy_reset_gpio)
		return;

	mdelay(20);
	gpiod_set_value_cansleep(phy_reset_gpio, 1);
	mdelay(60);
}

static void cvitek_clk_disable(void *data)
{
	clk_disable_unprepare(data);
}

/*
 * The board MAC is burned in the SoC efuse (shadow 0x03050100 + 0x40/0x44,
 * little endian; OUI 2c:f7:f1 on reCamera).  The vendor U-Boot reads it only
 * when "cvi_otp" is run; otherwise it makes up a random (locally administered)
 * MAC and passes that through the DT, so both the vendor kernel and this one
 * got a new MAC at every boot.  Use the efuse unless a real (globally
 * administered) MAC came from the DT.  The efuse
 * clock must be on for the access (reading the shadow with it gated hangs the
 * bus), the same pattern as the ePHY calibration read in the PHY driver.
 */
#define CVITEK_EFUSE_SHADOW_MAC	0x03050140

static void dwmac_cvitek_efuse_mac(struct device *dev, u8 *mac)
{
	struct clk *clk;
	void __iomem *reg;
	u8 fuse[ETH_ALEN];
	u32 lo, hi;

	clk = clk_get_sys(NULL, "clk_efuse");
	if (IS_ERR(clk) || clk_prepare_enable(clk)) {
		dev_warn(dev, "efuse clock unavailable, no efuse MAC\n");
		if (!IS_ERR(clk))
			clk_put(clk);
		return;
	}

	reg = ioremap(CVITEK_EFUSE_SHADOW_MAC, 8);
	if (reg) {
		lo = readl(reg);
		hi = readl(reg + 4);
		iounmap(reg);
		fuse[0] = lo;
		fuse[1] = lo >> 8;
		fuse[2] = lo >> 16;
		fuse[3] = lo >> 24;
		fuse[4] = hi;
		fuse[5] = hi >> 8;
		if (is_valid_ether_addr(fuse)) {
			ether_addr_copy(mac, fuse);
			dev_info(dev, "MAC from efuse %pM\n", mac);
		}
	}

	clk_disable_unprepare(clk);
	clk_put(clk);
}

static int dwmac_cvitek_probe(struct platform_device *pdev)
{
	struct plat_stmmacenet_data *plat_dat;
	struct stmmac_resources stmmac_res;
	struct clk *clk;
	int ret;

	pdev->dev.dma_mask = &cvitek_dma_mask;
	pdev->dev.coherent_dma_mask = cvitek_dma_mask;

	cvitek_eth_ephy_init(pdev);

	ret = stmmac_get_platform_resources(pdev, &stmmac_res);
	if (ret)
		return ret;

	plat_dat = devm_stmmac_probe_config_dt(pdev, stmmac_res.mac);
	if (IS_ERR(plat_dat))
		return PTR_ERR(plat_dat);

	/*
	 * Nothing valid, or a locally administered address: U-Boot without
	 * ethaddr makes up a random one and passes it on.  Prefer the efuse.
	 */
	if (!is_valid_ether_addr(stmmac_res.mac) ||
	    (stmmac_res.mac[0] & 0x02))
		dwmac_cvitek_efuse_mac(&pdev->dev, stmmac_res.mac);

	/*
	 * Keep the MAC clock running. The stmmac core calls pm_runtime_put() at
	 * the end of its probe to let runtime PM gate the clocks; holding a
	 * reference here keeps the gate on, which is what the vendor glue does
	 * (clk_prepare_enable() and no runtime PM of its own).
	 */
	clk = devm_clk_get(&pdev->dev, "stmmaceth");
	if (IS_ERR(clk)) {
		dev_warn(&pdev->dev, "cannot get stmmaceth clock\n");
	} else {
		ret = clk_prepare_enable(clk);
		if (ret)
			return ret;

		ret = devm_add_action_or_reset(&pdev->dev, cvitek_clk_disable, clk);
		if (ret)
			return ret;
	}

	/*
	 * E o segundo clock do MAC, pelo mesmo motivo. O sistema que funciona
	 * nunca abre o MAC com um clock fechado: em clk-cv181x.c as duas entradas
	 * de ETH0 (clk_500m_eth0 e clk_axi4_eth0) sao CLK_IS_CRITICAL, e o glue do
	 * fabricante ainda pede clk_500m_eth/clk_axi4_eth (nomes que o DT dele nao
	 * tem, entao os pedidos so' avisam). No nosso DT os mesmos dois clocks sao
	 * os gates do CCF CLK_AXI4_ETH0 ("stmmaceth") e CLK_ETH0_500M ("ptp_ref"),
	 * e o stmmac so' liga ptp_ref em stmmac_setup_ptp(), depois de init_phy()
	 * e de stmmac_hw_setup(). Medido em repouso: clk_eth0_500m enable_cnt=0.
	 */
	clk = devm_clk_get(&pdev->dev, "ptp_ref");
	if (IS_ERR(clk)) {
		dev_warn(&pdev->dev, "cannot get ptp_ref clock\n");
	} else {
		ret = clk_prepare_enable(clk);
		if (ret)
			return ret;

		ret = devm_add_action_or_reset(&pdev->dev, cvitek_clk_disable, clk);
		if (ret)
			return ret;
	}

	return devm_stmmac_pltfr_probe(pdev, plat_dat, &stmmac_res);
}

static const struct of_device_id dwmac_cvitek_match[] = {
	{ .compatible = "cvitek,ethernet" },
	{ }
};
MODULE_DEVICE_TABLE(of, dwmac_cvitek_match);

static struct platform_driver dwmac_cvitek_driver = {
	.probe = dwmac_cvitek_probe,
	.driver = {
		.name = "dwmac-cvitek",
		.of_match_table = dwmac_cvitek_match,
	},
};
module_platform_driver(dwmac_cvitek_driver);

MODULE_AUTHOR("CVITEK");
MODULE_DESCRIPTION("CVITEK (Sophgo SG200x) DWMAC glue");
MODULE_LICENSE("GPL v2");
