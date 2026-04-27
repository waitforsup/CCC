`timescale 1ns / 1ps
`define UD #1
module gmii_to_rgmii(
    input        rst,
    input        sys_clk,
    output       rgmii_clk,
    //mac输入的数据由gmii转化为rgmii，时钟为rgmii_clk
    input        mac_tx_data_valid,
    input [7:0]  mac_tx_data,
    //eth输入的数据由rgmii转化为gmii，时钟为rgmii_clk
    output reg       mac_rx_error,
    output reg       mac_rx_data_valid,
    output reg [7:0] mac_rx_data,
    //eth接收
    input        rgmii_rxc,
    input        rgmii_rx_ctl,
    input [3:0]  rgmii_rxd,
    //eth发送        
    output       rgmii_txc,
    output       rgmii_tx_ctl,
    output [3:0] rgmii_txd 
);

    //=============================================================
    //  RGMII TX cccc
    //=============================================================
    wire       rgmii_txc_obuf;
    wire       rgmii_txc_tbuf;
    wire       rgmii_tx_ctl_obuf;
    wire       rgmii_tx_ctl_tbuf;
    wire [3:0] rgmii_txd_obuf;
    wire [3:0] rgmii_txd_tbuf;

    generate 
        genvar i;
        for (i=0; i<4; i=i+1) 
        begin : rgmii_tx_data            
           /* GTP_OSERDE #(
                .OSERDES_MODE("ODDR"),  //"ODDR","OMDDR","OGSER4","OMSER4","OGSER7","OGSER8",OMSER8"
                .WL_EXTEND   ("FALSE"),     //"TRUE"; "FALSE"
                .GRS_EN      ("TRUE"),         //"TRUE"; "FALSE"
                .LRS_EN      ("TRUE"),          //"TRUE"; "FALSE"
                .TSDDR_INIT  (1'b0)         //1'b0;1'b1
            ) tx_data_oddr(
                .DO    (rgmii_txd_obuf[i]),                        //数据输出  output
                .TQ    (rgmii_txd_tbuf[i]),                        //选通输出  output
                .DI    ({6'd0,mac_tx_data[i+4],mac_tx_data[i]}),   //数据输入  input
                .TI    (4'd0),                                     //选通输入  input
                .RCLK  (rgmii_clk),                                //输出时钟  input
                .SERCLK(rgmii_clk),                                //串行时钟  input
                .OCLK  (1'd0),                                     //输出时钟  input
                .RST   (1'b0)                                      //复位     input
            );     */                                     
            // 时钟 DDR 输出

            GTP_OSERDES_E2 #(
                .GRS_EN("TRUE"),
                .OSERDES_MODE("DDR2TO1_OPPOSITE_EDGE"),//双边沿输出
                .TSERDES_MODE("DDR2TO1_OPPOSITE_EDGE"),
                .TRI_EN("FALSE"),
                .TSERDES_EN("FALSE")
            ) tx_data_oddr (
                .RST   (1'b0),

                .OCE   (1'b1),
                .TCE   (1'b1),

                .OCLKDIV(rgmii_clk),
                .SERCLK (rgmii_clk),
                .OCLK   (rgmii_clk),

                .DI({6'd0, mac_tx_data[i+4], mac_tx_data[i]}),
                .TI(2'b00),

                .TBYTE_IN(1'b0),

                .DO(rgmii_txd_obuf[i]),
                .TQ(rgmii_txd_tbuf[i]),

                .MIPI_CTRL(1'b0),
                .UPD0_SHIFT(1'b0),
                .UPD1_SHIFT(1'b0),
                .OSHIFTIN0(1'b0),
                .OSHIFTIN1(1'b0)
            );
            GTP_OUTBUFT  gtp_outbuft1(
                .I(rgmii_txd_obuf[i]),     
                .T(rgmii_txd_tbuf[i])  ,
                .O(rgmii_txd[i])        
            );
        end
    endgenerate

    /*GTP_OSERDES #(
        .OSERDES_MODE("ODDR"),  //"ODDR","OMDDR","OGSER4","OMSER4","OGSER7","OGSER8",OMSER8"
        .WL_EXTEND   ("FALSE"),     //"TRUE"; "FALSE"
        .GRS_EN      ("TRUE"),         //"TRUE"; "FALSE"
        .LRS_EN      ("TRUE"),          //"TRUE"; "FALSE"
        .TSDDR_INIT  (1'b0)         //1'b0;1'b1
    ) tx_ctl_oddr(
        .DO    (rgmii_tx_ctl_obuf),
        .TQ    (rgmii_tx_ctl_tbuf),
        .DI    ({6'd0,mac_tx_data_valid ^ 1'b0,mac_tx_data_valid}),
        .TI    (4'd0),
        .RCLK  (rgmii_clk),
        .SERCLK(rgmii_clk),
        .OCLK  (1'd0),
        .RST   (tx_reset_sync)
    );           */                              
    // TX_CTL DDR 输出
    GTP_OSERDES_E2 #(
        .GRS_EN("TRUE"),
        .OSERDES_MODE("DDR2TO1_OPPOSITE_EDGE"),
        .TSERDES_MODE("DDR2TO1_OPPOSITE_EDGE"),
        .TRI_EN("FALSE"),
        .TSERDES_EN("FALSE")
    ) tx_ctl_oddr (
        .RST   (tx_reset_sync),

        .OCE   (1'b1),
        .TCE   (1'b1),

        .OCLKDIV(rgmii_clk),
        .SERCLK (rgmii_clk),
        .OCLK   (rgmii_clk),

        .DI({6'd0, mac_tx_data_valid, mac_tx_data_valid}),
        .TI(2'b00),

        .TBYTE_IN(1'b0),

        .DO(rgmii_tx_ctl_obuf),
        .TQ(rgmii_tx_ctl_tbuf),

        // 以下不用的全部绑死
        .MIPI_CTRL(1'b0),
        .UPD0_SHIFT(1'b0),
        .UPD1_SHIFT(1'b0),
        .OSHIFTIN0(1'b0),
        .OSHIFTIN1(1'b0)
    );
    GTP_OUTBUFT  gtp_outbuft1(
        .I(rgmii_tx_ctl_obuf),     
        .T(rgmii_tx_ctl_tbuf)  ,
        .O(rgmii_tx_ctl)        
    );

    //DDR数据输出转换模块
   /* GTP_OSERDES #(
     .OSERDES_MODE("ODDR"),  //"ODDR","OMDDR","OGSER4","OMSER4","OGSER7","OGSER8",OMSER8"
     .WL_EXTEND   ("FALSE"),     //"TRUE"; "FALSE"
     .GRS_EN      ("TRUE"),         //"TRUE"; "FALSE"
     .LRS_EN      ("TRUE"),          //"TRUE"; "FALSE"
     .TSDDR_INIT  (1'b0)         //1'b0;1'b1
    ) tx_clk_oddr(
       .DO    (rgmii_txc_obuf),
       .TQ    (rgmii_txc_tbuf),
       .DI    ({7'd0,1'b1}),
       .TI    (4'd0),
       .RCLK  (rgmii_clk),
       .SERCLK(rgmii_clk),
       .OCLK  (1'd0),
       .RST   (tx_reset_sync)
    ); */
// 时钟 DDR 输出
    GTP_OSERDES_E2 #(
        .GRS_EN("TRUE"),
        .OSERDES_MODE("DDR2TO1_OPPOSITE_EDGE"),
        .TSERDES_MODE("DDR2TO1_OPPOSITE_EDGE"),
        .TRI_EN("FALSE"),
        .TSERDES_EN("FALSE")
    ) tx_clk_oddr (
        .RST   (tx_reset_sync),

        .OCE   (1'b1),
        .TCE   (1'b1),

        .OCLKDIV(rgmii_clk),
        .SERCLK (rgmii_clk),
        .OCLK   (rgmii_clk),

        .DI({7'd0,1'b1}),
        .TI(2'b00),

        .TBYTE_IN(1'b0),

        .DO(rgmii_txc_obuf),
        .TQ(rgmii_txc_tbuf),

        .MIPI_CTRL(1'b0),
        .UPD0_SHIFT(1'b0),
        .UPD1_SHIFT(1'b0),
        .OSHIFTIN0(1'b0),
        .OSHIFTIN1(1'b0)
    );
    
    GTP_OUTBUFT  gtp_outbuft6
    (
        
        .I(rgmii_txc_obuf),     
        .T(rgmii_txc_tbuf)  ,
        .O(rgmii_txc)        
    );                                                                                                            
    

    
    //=============================================================
    //  RGMII RX 
    //=============================================================
    wire        rgmii_rxc_ibuf;
    wire        rgmii_rxc_bufio;
    wire        rgmii_rx_ctl_ibuf;
    wire [3:0]  rgmii_rxd_ibuf;


    wire [7:0] delay_step_gray ;
    



    wire [7:0] delay_step_45;  // 新增，可不用
    wire lock;

    GTP_DLL_E2 #(
        .GRS_EN("TRUE"),
        .FAST_LOCK("TRUE"),          // 建议保持
        .DELAY_STEP_OFFSET(0),
        .FDIV(2'b10),                // ? 推荐默认
        .INT_CLK(1'b0),              // 使用外部SYS_CLK
        .UPD_DLY(2'b01),
        .HPIO("FALSE")
    ) clk_dll (
        .CLKIN    (rgmii_rxc),
        .SYS_CLK  (rgmii_rxc),   // ? 关键：先直接这样用（后面可优化）
        .UPDATE_N (1'b1),
        .RST      (1'b0),        // ?? 注意：Logos2是低有效（后面说）
        .PWD      (1'b0),

        .DELAY_STEP  (delay_step_gray),
        .DELAY_STEP1 (delay_step_45), // 可不使用
        .LOCK        (lock)
    );

        wire rgmii_rxc_delay;

        GTP_IODELAY_E2 #(
            .DELAY_STEP_SEL("PORT"),     // ? 使用DLL输出
            .DELAY_STEP_VALUE(8'h00),    // 无效（因为用PORT）
            .TDELAY_EN("FALSE")
        ) rgmii_clk_delay (
            .EN_N      (1'b0),           // 使能（低有效）
            .DI        (rgmii_rxc),
            .DELAY_SEL (1'b1),           // ? 推荐10ps/step
            .DELAY_STEP(delay_step_gray),
            .DO        (rgmii_rxc_delay)
        );
/*
    GTP_IOCLKDELAY #(
        .DELAY_STEP_VALUE   (  'd127           ),
        .DELAY_STEP_SEL     (  "PARAMETER"     ),
        .SIM_DEVICE         (  "LOGOS"         ) 
    ) rgmii_clk_delay (
        .DELAY_STEP         (  delay_step_gray ),// INPUT[7:0]     
        .CLKOUT             (  rgmii_rxc_ibuf  ),// OUTPUT         
        .DELAY_OB           (                  ),// OUTPUT         
        .CLKIN              (  rgmii_rxc       ),// INPUT          
        .DIRECTION          (  1'b0            ),// INPUT          
        .LOAD               (  1'b0            ),// INPUT          
        .MOVE               (  1'b0            ) // INPUT          
    );*/

    GTP_CLKBUFG GTP_CLKBUFG_RXSHFT(
        .CLKIN     (rgmii_rxc_delay),
        .CLKOUT    (rgmii_clk)
    );


    GTP_INBUF #(
        .IOSTANDARD("DEFAULT"),
        .TERM_DDR("ON")
    ) u_rgmii_rx_ctl_ibuf (
        .O(rgmii_rx_ctl_ibuf),// OUTPUT  
        .I(rgmii_rx_ctl) // INPUT  
    );
    
   


wire  rgmii_rx_ctl_delay;
parameter DELAY_STEP = 8'h0F;

wire [5:0] rx_ctl_nc;
wire       gmii_ctl;
wire       rgmii_rx_valid_xor_error;

// ===================== 修正：RX_CTL 输入 IDDR =====================
GTP_ISERDES_E2 #(
    .ISERDES_MODE("DDR1TO2_OPPOSITE_EDGE"), // ?关键
    .GRS_EN("TRUE"),
    .BITSLIP_EN("FALSE"),
    .NUM_ICE(1'b0)
) gmii_ctl_in (
    .RST(1'b0),

    .ICE0(1'b1),
    .ICE1(1'b1),

    .DESCLK(rgmii_clk),   // 高速采样时钟
    .ICLK(rgmii_clk),     // 同源即可
    .ICLKB(~rgmii_clk),   // ?关键：反相信号（DDR必须）
    .ICLKDIV(rgmii_clk),  // 低速输出时钟

    .OCLK(1'b0),

    .DI(rgmii_rx_ctl_ibuf),

    .BITSLIP(1'b0),
    .ISHIFTIN0(1'b0),
    .ISHIFTIN1(1'b0),

    .IFIFO_WADDR(3'd0),
    .IFIFO_RADDR(3'd0),

    .DO({rgmii_rx_valid_xor_error, gmii_ctl, rx_ctl_nc[5:0]})
);

wire [3:0] rgmii_rxd_delay;
wire [23:0] rxd_nc;
wire [7:0]  gmii_rxd;

always @(posedge rgmii_clk) begin
    mac_rx_data         <= gmii_rxd;
    mac_rx_data_valid   <= gmii_ctl;
    mac_rx_error        <= gmii_ctl ^ rgmii_rx_valid_xor_error;
end

generate 
    genvar j;
    for (j=0; j<4; j=j+1)
    begin : rgmii_rx_data

        // =========================
        // 1. 输入Buffer（保持不变）
        // =========================
        GTP_INBUF #(
            .IOSTANDARD("DEFAULT"),
            .TERM_DDR("ON")
        ) u_rgmii_rxd_ibuf (
            .O(rgmii_rxd_ibuf[j]),
            .I(rgmii_rxd[j])
        );

        // =========================
        // 2. ISERDES（Logos2版本）
        // =========================
        GTP_ISERDES_E2 #(
            .ISERDES_MODE("DDR1TO2_OPPOSITE_EDGE"), // ?关键
            .GRS_EN("TRUE"),
            .BITSLIP_EN("FALSE"),
            .NUM_ICE(1'b0)
        ) gmii_rxd_in (
            .RST(1'b0),

            .ICE0(1'b1),
            .ICE1(1'b1),

            .DESCLK(rgmii_clk),
            .ICLK(rgmii_clk),
            .ICLKB(~rgmii_clk),   // ?必须加！
            .ICLKDIV(rgmii_clk),

            .OCLK(1'b0),

            .DI(rgmii_rxd_ibuf[j]),

            .BITSLIP(1'b0),
            .ISHIFTIN0(1'b0),
            .ISHIFTIN1(1'b0),

            .IFIFO_WADDR(3'd0),
            .IFIFO_RADDR(3'd0),

            // ?保持你原来的bit拼接方式
            .DO({gmii_rxd[j+4], gmii_rxd[j], rxd_nc[j*6 +: 6]})
        );

    end
endgenerate

endmodule