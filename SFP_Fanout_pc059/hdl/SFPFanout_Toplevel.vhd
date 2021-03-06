-------------------------------------------------------------------------------
--! @file
--! @brief Top level of firmware for DUNE SFO FANOUT (PC059A)
-------------------------------------------------------------------------------
-- File name: SFPFanout_Toplevel.vhd
-- Version: 0.1
-- Date: 16/02/2018
-- Paolo Baesso
--
-- Changes
--
-------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.ipbus_decode_fanout.all;
use work.ipbus.all;
use work.ipbus_reg_types.all;


entity SFPFanout is
    generic(
        constant FW_VERSION : unsigned(31 downto 0):= X"59a0000d" -- Firmware revision. Remember to change this as needed.
    );
	port(
		sysclk: in std_logic; -- 50MHz board crystal clock
		clk_ipb_o: out std_logic; -- IPbus clock
		rst_ipb_o: out std_logic;
		clk125_o: out std_logic;
		rst125_o: out std_logic;
		clk_aux_o: out std_logic; -- 50MHz clock
		rst_aux_o: out std_logic;
		--nuke: in std_logic; -- The signal of doom
		--soft_rst: in std_logic; -- The signal of lesser doom
		leds: out std_logic_vector(1 downto 0); -- status LEDs
		rgmii_txd: out std_logic_vector(3 downto 0);
		rgmii_tx_ctl: out std_logic;
		rgmii_txc: out std_logic;
		rgmii_rxd: in std_logic_vector(3 downto 0);
		rgmii_rx_ctl: in std_logic;
		rgmii_rxc: in std_logic;
		mac_addr: in std_logic_vector(47 downto 0); -- MAC address
		ip_addr: in std_logic_vector(31 downto 0); -- IP address
		ipb_in: in ipb_rbus; -- ipbus
		ipb_out: out ipb_wbus;
		phy_rstn: out std_logic 
	);

end SFPFanout;

architecture rtl of SFPFanout is

	signal clk125_fr, clk125, clk125_90, clk200, clk_ipb, clk_ipb_i, locked, rst125, rst_ipb, rst_ipb_ctrl, rst_eth, onehz, pkt: std_logic;
	signal mac_tx_data, mac_rx_data: std_logic_vector(7 downto 0);
	signal mac_tx_valid, mac_tx_last, mac_tx_error, mac_tx_ready, mac_rx_valid, mac_rx_last, mac_rx_error: std_logic;
	signal led_p: std_logic_vector(0 downto 0);
	
	signal ipbww: ipb_wbus_array(N_SLAVES - 1 downto 0);
    signal ipbrr: ipb_rbus_array(N_SLAVES - 1 downto 0);
    signal ctrl, stat: ipb_reg_v(0 downto 0);
    signal nuke: std_logic;
    signal soft_rst: std_logic;
    signal phy_rst_e: std_logic;
    signal inf_leds: std_logic_vector(1 downto 0);
	
begin

--	DCM clock generation for internal bus, ethernet

	clocks: entity work.clocks_7s_extphy_se
		port map(
			sysclk => sysclk,
			clko_125 => clk125,
			clko_125_90 => clk125_90,
			clko_200 => clk200,
			clko_ipb => clk_ipb_i,
			locked => locked,
			nuke => nuke,
			soft_rst => soft_rst,
			rsto_125 => rst125,
			rsto_ipb => rst_ipb,
			rsto_ipb_ctrl => rst_ipb_ctrl,
			onehz => onehz
		);

	clk_ipb <= clk_ipb_i; -- Best to align delta delays on all clocks for simulation
	clk_ipb_o <= clk_ipb_i;
	rst_ipb_o <= rst_ipb;
	clk125_o <= clk125;	
	rst125_o <= rst125;
	
	stretch: entity work.led_stretcher
		generic map(
			WIDTH => 1
		)
		port map(
			clk => clk125,
			d(0) => pkt,
			q => led_p
		);

	leds <= (led_p(0), locked and onehz);
	
-- Ethernet MAC core and PHY interface
	
	eth: entity work.eth_7s_rgmii
		port map(
			clk125 => clk125,
			clk125_90 => clk125_90,
			clk200 => clk200,
			rst => rst125,
			rgmii_txd => rgmii_txd,
			rgmii_tx_ctl => rgmii_tx_ctl,
			rgmii_txc => rgmii_txc,
			rgmii_rxd => rgmii_rxd,
			rgmii_rx_ctl => rgmii_rx_ctl,
			rgmii_rxc => rgmii_rxc,
			tx_data => mac_tx_data,
			tx_valid => mac_tx_valid,
			tx_last => mac_tx_last,
			tx_error => mac_tx_error,
			tx_ready => mac_tx_ready,
			rx_data => mac_rx_data,
			rx_valid => mac_rx_valid,
			rx_last => mac_rx_last,
			rx_error => mac_rx_error
		);
	
-- ipbus control logic

	ipbus: entity work.ipbus_ctrl
		port map(
			mac_clk => clk125,
			rst_macclk => rst125,
			ipb_clk => clk_ipb,
			rst_ipb => rst_ipb_ctrl,
			mac_rx_data => mac_rx_data,
			mac_rx_valid => mac_rx_valid,
			mac_rx_last => mac_rx_last,
			mac_rx_error => mac_rx_error,
			mac_tx_data => mac_tx_data,
			mac_tx_valid => mac_tx_valid,
			mac_tx_last => mac_tx_last,
			mac_tx_error => mac_tx_error,
			mac_tx_ready => mac_tx_ready,
			ipb_out => ipb_out,
			ipb_in => ipb_in,
			mac_addr => mac_addr,
			ip_addr => ip_addr,
			pkt => pkt
		);
		
 -- ipbus control register
    I1 : entity work.ipbus_ctrlreg_v
        port map(
            clk => clk_ipb,
            reset => rst_ipb,
            ipbus_in => ipbww(N_SLV_CTRL_REG),
            ipbus_out => ipbrr(N_SLV_CTRL_REG),
            d => stat,
            q => ctrl
        );
    stat(0) <= std_logic_vector(FW_VERSION);-- <-Let's use this as firmware revision number
    soft_rst <= ctrl(0)(0);
    nuke <= ctrl(0)(1);
	
	infra: entity work.enclustra_ax3_pm3_infra
        port map(
            sysclk => sysclk,
            clk_ipb_o => clk_ipb,
            rst_ipb_o => rst_ipb,
            rst125_o => phy_rst_e,
            --clk_200_o => clk_200,
            nuke => nuke,
            soft_rst => soft_rst,
            leds => inf_leds,
            rgmii_txd => rgmii_txd,
            rgmii_tx_ctl => rgmii_tx_ctl,
            rgmii_txc => rgmii_txc,
            rgmii_rxd => rgmii_rxd,
            rgmii_rx_ctl => rgmii_rx_ctl,
            rgmii_rxc => rgmii_rxc,
            mac_addr => mac_addr,
            ip_addr => ip_addr,
            ipb_in => ipb_in,
            ipb_out => ipb_out
        );
            
        --leds <= not ('0' & userled & inf_leds); -- Check this.
        phy_rstn <= not phy_rst_e;	

end rtl;