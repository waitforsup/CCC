`timescale 1ns/1ps
`define DDR3
/**
 * HDMI DDR OV5640 视频处理顶层模块
 * 功能：接收HDMI输入和两个OV5640摄像头输入，通过DDR3缓存，实现四宫格缩放输出
 */
module hdmi_ddr_ov5640_top#(
  parameter VIDEO_LENGTH         = 1920                 ,
  parameter VIDEO_HIGTH          = 1080                 ,
  parameter ZOOM_VIDEO_LENGTH    = VIDEO_LENGTH/2           ,
  parameter ZOOM_VIDEO_HIGTH     = VIDEO_HIGTH/2                 ,
  parameter PIXEL_WIDTH          = 32                   ,  // 像素位宽
  parameter MEM_ROW_ADDR_WIDTH   = 15                   ,  // DDR行地址宽度
  parameter MEM_COL_ADDR_WIDTH   = 10                   ,  // DDR列地址宽度
  parameter MEM_BADDR_WIDTH      = 3                    ,  // DDR Bank地址宽度
  parameter MEM_DQ_WIDTH         = 32                   ,  // DDR数据宽度
  parameter MEM_DQS_WIDTH        = MEM_DQ_WIDTH/8       ,  // DQS宽度
  parameter MEM_DM_WIDTH         = MEM_DQ_WIDTH/8       ,  // DM宽度
  parameter M_AXI_BRUST_LEN      = 8                    ,  // AXI突发长度
  parameter RW_ADDR_MIN          = 20'b0                ,  // DDR读写最小地址
  parameter RW_ADDR_MAX          = ZOOM_VIDEO_LENGTH*ZOOM_VIDEO_HIGTH*PIXEL_WIDTH/MEM_DQ_WIDTH,  // DDR读写最大地址
  parameter CTRL_ADDR_WIDTH      = MEM_ROW_ADDR_WIDTH + MEM_BADDR_WIDTH + MEM_COL_ADDR_WIDTH,// 控制器地址宽度: 15+3+10=28
  parameter       LOCAL_MAC = 48'ha0_b1_c2_d3_e1_e1,
  parameter       LOCAL_IP  = 32'hC0_A8_01_6E,//192.168.1.110
  parameter       LOCL_PORT = 16'd8080,

  parameter       DEST_IP   = 32'hC0_A8_01_69,//192.168.1.105
  parameter       DEST_PORT = 16'd8080, 
  parameter       DEST_MAC   = 48'h74_5d_22_00_d0_6e
  
)(
  // 系统时钟
  input                                sys_clk              ,  // 50MHz系统时钟
  input                                clk_p                ,  // DDR参考时钟正端
  input                                clk_n                ,  // DDR参考时钟负端
  
  // DDR接口
  output reg                           heart_beat_led       ,  // 心跳指示灯
  output                               ddr_init_done        ,  // DDR初始化完成标志

  output                               mem_rst_n            ,  // DDR复位
  output                               mem_ck               ,  // DDR时钟正端
  output                               mem_ck_n             ,  // DDR时钟负端
  output                               mem_cke              ,  // DDR时钟使能
  output                               mem_cs_n             ,  // DDR片选
  output                               mem_ras_n            ,  // DDR行选通
  output                               mem_cas_n            ,  // DDR列选通
  output                               mem_we_n             ,  // DDR写使能
  output                               mem_odt              ,  // DDR片内端接
  output      [MEM_ROW_ADDR_WIDTH-1:0] mem_a                ,  // DDR地址
  output      [MEM_BADDR_WIDTH-1:0]    mem_ba               ,  // DDR Bank地址
  inout       [MEM_DQ_WIDTH/8-1:0]     mem_dqs              ,  // DDR数据选通
  inout       [MEM_DQ_WIDTH/8-1:0]     mem_dqs_n            ,  // DDR数据选通负端
  inout       [MEM_DQ_WIDTH-1:0]       mem_dq               ,  // DDR数据总线
  output      [MEM_DQ_WIDTH/8-1:0]     mem_dm               ,  // DDR数据掩码
  
  // MS72xx HDMI收发器接口
  output wire                          hdmi_rst             ,  // HDMI芯片复位
  output                               iic_tx_scl           ,  // HDMI I2C时钟
  inout                                iic_tx_sda           ,  // HDMI I2C数据
  output                               hdmi_int_led         ,  // HDMI初始化完成指示灯
  output wire                          fram0_done           ,  // 帧0写入完成
  output wire                          fram1_done           ,  // 帧1写入完成
  output wire                          fram2_done           ,  // 帧2写入完成
  output wire                          fram3_done           ,  // 帧3写入完成
  
  // HDMI输入接口
  input wire                           pix_clk_in           ,  // HDMI输入像素时钟(1080p@148.5MHz)
  input wire                           vs_in                ,  // HDMI输入场同步
  input wire                           hs_in                ,  // HDMI输入行同步
  input wire                           de_in                ,  // HDMI输入数据使能
  input wire [7 : 0]                   r_in                 ,  // HDMI输入红色分量
  input wire [7 : 0]                   g_in                 ,  // HDMI输入绿色分量
  input wire [7 : 0]                   b_in                 ,  // HDMI输入蓝色分量
  
  // HDMI输出接口
  output                               pix_clk_out          ,  // HDMI输出像素时钟
  output reg                           r_vs_out          ,  // HDMI输出场同步
  output reg                           r_hs_out          ,  // HDMI输出行同步
  output reg                           r_de_out          ,  // HDMI输出数据使能
  output reg  [7 : 0]                  r_r_out           ,  // HDMI输出红色分量
  output reg  [7 : 0]                  r_g_out           ,  // HDMI输出绿色分量
  output reg  [7 : 0]                  r_b_out           ,  // HDMI输出蓝色分量
  
  // OV5640摄像头接口
  output  [1:0]                        cmos_init_done       ,  // 摄像头初始化完成标志
  // 摄像头1
  inout                                cmos1_scl            ,  // 摄像头1 I2C时钟
  inout                                cmos1_sda            ,  // 摄像头1 I2C数据
  input                                cmos1_vsync          ,  // 摄像头1场同步
  input                                cmos1_href           ,  // 摄像头1行参考/数据有效
  input                                cmos1_pclk           ,  // 摄像头1像素时钟
  input   [7:0]                        cmos1_data           ,  // 摄像头1数据
  output                               cmos1_reset          ,  // 摄像头1复位
  // 摄像头2
  inout                                cmos2_scl            ,  // 摄像头2 I2C时钟
  inout                                cmos2_sda            ,  // 摄像头2 I2C数据
  input                                cmos2_vsync          ,  // 摄像头2场同步
  input                                cmos2_href           ,  // 摄像头2行参考/数据有效
  input                                cmos2_pclk           ,  // 摄像头2像素时钟
  input   [7:0]                        cmos2_data           ,  // 摄像头2数据
  output                               cmos2_reset          , // 摄像头2复位

  //ETH
    input        rgmii_rxc,
    input        rgmii_rx_ctl,
    input [3:0]  rgmii_rxd,
                 
    output       rgmii_txc,
    output       rgmii_tx_ctl,
    output [3:0] rgmii_txd, 
    output reg   ETH_led,
	output 		     led_test
);

/////////////////////////////////////////////////////////////////////////////////////
// 参数定义
/////////////////////////////////////////////////////////////////////////////////////
parameter TH_1S = 27'd33000000;  // 1秒计数值(33MHz时钟)

// DE输入状态机状态
/******************************PARAMETER********************************************/
parameter DE_IN_WAIT  = 4'd0;
parameter DE_IN_CNT   = 4'd1;
parameter DE_IN_END   = 4'd2;

// DE输出状态机状态
parameter DE_OUT_WAIT = 4'd0;
parameter DE_OUT_CNT  = 4'd1;
parameter DE_OUT_END  = 4'd2;

// 像素输入状态机状态
parameter PIX_IN_WAIT = 3'd0;
parameter PIX_IN_CNT  = 3'd1;
parameter PIX_IN_END  = 3'd2;

// 像素输出状态机状态
parameter PIX_OUT_WAIT = 3'd0;
parameter PIX_OUT_CNT  = 3'd1;
parameter PIX_OUT_END  = 3'd2;



/////////////////////////////////////////////////////////////////////////////////////
// 内部信号定义
/////////////////////////////////////////////////////////////////////////////////////
// DDR IP核时钟和复位
wire                                   ddr_ip_clk           ;
wire                                   ddr_ip_rst_n         ;

// AXI写地址通道
wire [3 : 0]                           M_AXI_AWID           ;
wire [CTRL_ADDR_WIDTH-1 : 0]           M_AXI_AWADDR         ;
wire                                   M_AXI_AWUSER         ;
wire                                   M_AXI_AWVALID        ;
wire                                   M_AXI_AWREADY        ;

// AXI写数据通道
wire [MEM_DQ_WIDTH*8-1 : 0]            M_AXI_WDATA          ;
wire [MEM_DQ_WIDTH-1 : 0]              M_AXI_WSTRB          ;
wire                                   M_AXI_WLAST          ;
wire [3 : 0]                           M_AXI_WUSER          ;
wire                                   M_AXI_WREADY         ;

// AXI读地址通道
wire [3 : 0]                           M_AXI_ARID           ;
wire                                   M_AXI_ARUSER         ;
wire [CTRL_ADDR_WIDTH-1 : 0]           M_AXI_ARADDR         ;
wire                                   M_AXI_ARVALID        ;
wire                                   M_AXI_ARREADY        ;

// AXI读数据通道
wire [3 : 0]                           M_AXI_RID            ;
wire [MEM_DQ_WIDTH*8-1 : 0]            M_AXI_RDATA          ;
wire                                   M_AXI_RLAST          ;
wire                                   M_AXI_RVALID         ;

// DDR调试信号
wire [1 : 0]                           init_read_clk_ctrl   ;
wire [3 : 0]                           init_slip_step       ;
wire                                   force_read_clk_ctrl  ;

// 视频FIFO信号
wire [31 : 0]                          rgb_in               ;  // HDMI输入RGB数据
wire [31 : 0]                          video0_data_out      ;  // 四宫格0输出数据
wire [31 : 0]                          video1_data_out      ;  // 四宫格1输出数据
wire [31 : 0]                          video2_data_out      ;  // 四宫格2输出数据
wire [31 : 0]                          video3_data_out      ;  // 四宫格3输出数据

// I2C和PLL信号
wire                                   iic_clk              ;  // 10MHz I2C时钟
wire                                   pll_init_done        ;
wire [11 : 0]                          x_act                ;  // 当前有效像素X坐标
wire [11 : 0]                          y_act                ;  // 当前有效像素Y坐标

// 视频同步信号
wire                                   vs_out/* synthesis PAP_MARK_DEBUG="1" */               ;
wire                                   hs_out/* synthesis PAP_MARK_DEBUG="1" */               ;
wire                                   de_out /* synthesis PAP_MARK_DEBUG="1" */              ;

// 缩放视频信号
wire                                   zoom_de_out          ;
wire [PIXEL_WIDTH - 1: 0]              zoom_data_out        ;

// DE输入计数和状态
reg [11 : 0]              de_in_cnt     ;
reg                       de_in_d0      ;
reg                       de_in_d1      ;
reg                       vs_in_d0      ;
reg                       vs_in_d1      ;
reg [3 : 0]               de_in_state   ;

// 缩放DE输入计数和状态
reg                       zoom_vs_in_d0 ;
reg                       zoom_vs_in_d1 ;
reg                       zoom_de_in_d0 ;
reg                       zoom_de_in_d1 ;
reg [11 : 0]              zoom_de_in_cnt;
reg [3 : 0]               zoom_de_in_state;

// DE输出计数和状态
reg [11 : 0]              de_out_cnt    ;
reg                       r_de_out_d0   ;
reg                       r_vs_out_d0   ;
reg                       de_out_d0     ;
reg                       de_out_d1     ;
reg                       vs_out_d0     ;
reg                       vs_out_d1     ;
reg [3 : 0]               de_out_state  ;
reg [11 : 0]              r_x_act_d0    ;
reg [11 : 0]              r_x_act       ;

// 视频FIFO读控制
reg                       video0_rd_en  ;
reg                       video1_rd_en  ;
reg                       video2_rd_en  ;
reg                       video3_rd_en  ;
reg                       video_pre_rd_flag;
wire                      w_video_pre_rd_flag;
assign w_video_pre_rd_flag = video_pre_rd_flag;
reg                       v_sync_flag    ;
reg [15:0]                rstn_1ms       ;

// 时钟信号
wire                      clk_25M        ;  // 25MHz时钟

// 摄像头信号
wire                      cmos_scl       ;
wire                      cmos_sda       ;
wire                      cmos_vsync     ;
wire                      cmos_href      ;
wire                      cmos_pclk      ;
wire   [7:0]              cmos_data      ;
wire                      cmos_reset     ;
wire                      initial_en     ;  // 初始化使能

// 摄像头1 16位数据
wire[15:0]                cmos1_d_16bit  ;
wire                      cmos1_href_16bit;
wire                      cmos1_pclk_16bit;
reg [7:0]                 cmos1_d_d0     ;
reg                       cmos1_href_d0  ;
reg                       cmos1_vsync_d0 ;

// 摄像头2 16位数据
wire[15:0]                cmos2_d_16bit  ;
wire                      cmos2_href_16bit;
wire                      cmos2_pclk_16bit;
reg [7:0]                 cmos2_d_d0     ;
reg                       cmos2_href_d0  ;
reg                       cmos2_vsync_d0 ;

// 输出状态机
reg [2:0]                 out_state      ;

// RGB数据组合
assign rgb_in[31:24] = r_in;
assign rgb_in[23:22] = 2'd0;
assign rgb_in[21:14] = g_in;
assign rgb_in[13:12] = 2'd0;
assign rgb_in[11: 4] = b_in;
assign rgb_in[3 : 2] = 2'd0;
assign rgb_in[1 : 0] = 2'd0;

// AXI总线信号
wire [CTRL_ADDR_WIDTH-1:0]  axi_awaddr  ;
wire                        axi_awuser_ap;
wire [3:0]                  axi_awuser_id;
wire [3:0]                  axi_awlen    ;
wire                        axi_awready  ;
wire                        axi_awvalid  ;
wire [MEM_DQ_WIDTH*8-1:0]   axi_wdata    ;
wire [MEM_DQ_WIDTH*8/8-1:0] axi_wstrb    ;
wire                        axi_wready   ;
wire [3:0]                  axi_wusero_id;
wire                        axi_wusero_last;
wire [CTRL_ADDR_WIDTH-1:0]  axi_araddr   ;
wire                        axi_aruser_ap;
wire [3:0]                  axi_aruser_id;
wire [3:0]                  axi_arlen    ;
wire                        axi_arready  ;
wire                        axi_arvalid  ;
wire [MEM_DQ_WIDTH*8-1:0]   axi_rdata    ;
wire                        axi_rvalid   ;
wire [3:0]                  axi_rid      ;
wire                        axi_rlast    ;

// 计数信号
reg  [26:0]                 cnt          ;
reg  [15:0]                 cnt_1        ;
/////////////////////////////////////////////////////////////////////////////////////
// 摄像头1 DE输入计数模块
// 统计摄像头1输入视频的有效行数
/////////////////////////////////////////////////////////////////////////////////////
reg [11 : 0]              cmos1_de_in_cnt    ;
reg [11 : 0]              cmos1_h_cnt        ;
reg                       cmos1_de_in_d0     ;
reg                       cmos1_de_in_d1     ;
reg                       cmos1_vs_in_d0     ;
reg                       cmos1_vs_in_d1     ;
reg [3 : 0]               cmos1_de_in_state  ;

always @(posedge cmos1_pclk_16bit) begin
  if(!ddr_ip_rst_n) begin  
    cmos1_vs_in_d0     <= 'd0;
    cmos1_vs_in_d1     <= 'd0;
    cmos1_de_in_d0     <= 'd0;
    cmos1_de_in_d1     <= 'd0;
    cmos1_de_in_cnt    <= 'd0; 
    cmos1_de_in_state  <= 'd0;
    cmos1_h_cnt        <= 'd0;
  end else begin
    case(cmos1_de_in_state) 
      DE_IN_WAIT: begin
        cmos1_vs_in_d0 <= cmos1_vsync;
        cmos1_vs_in_d1 <= cmos1_vs_in_d0;
        if(!cmos1_vs_in_d0 && cmos1_vs_in_d1) begin
          cmos1_de_in_state <= DE_IN_CNT;  // 检测到场同步下降沿，开始计数
        end
      end
      DE_IN_CNT: begin
        cmos1_de_in_d0 <= cmos1_href_16bit;
        cmos1_de_in_d1 <= cmos1_de_in_d0;
        if(cmos1_de_in_d0 && !cmos1_de_in_d1) begin
          cmos1_de_in_cnt <= cmos1_de_in_cnt + 1'd1;  // 每检测到一个DE上升沿，行数加1
        end
        if(cmos1_href_16bit) begin
          cmos1_h_cnt <= cmos1_h_cnt + 'd1;  // 行内像素计数
        end else begin
          cmos1_h_cnt <= 'd0;
        end
        cmos1_vs_in_d0 <= cmos1_vsync;
        cmos1_vs_in_d1 <= cmos1_vs_in_d0;
        if(cmos1_vs_in_d0 && !cmos1_vs_in_d1) begin
          cmos1_de_in_cnt   <= 'd0;
          cmos1_de_in_state <= DE_IN_WAIT;  // 检测到场同步上升沿，开始下一帧
        end
      end
    endcase  
  end
end
/////////////////////////////////////////////////////////////////////////////////////
// DE输入计数模块 - 统计输入视频的有效行数
// 用于检测输入视频的分辨率
/////////////////////////////////////////////////////////////////////////////////////
always @(posedge pix_clk_in) begin
  if(!ddr_ip_rst_n) begin  
    vs_in_d0     <= 'd0;
    vs_in_d1     <= 'd0;
    de_in_d0     <= 'd0;
    de_in_d1     <= 'd0;
    de_in_cnt    <= 'd0; 
    de_in_state  <= 0;
  end else begin
    case(de_in_state) 
      DE_IN_WAIT: begin
        vs_in_d0 <= vs_in;
        vs_in_d1 <= vs_in_d0;
        if(!vs_in_d0 && vs_in_d1) begin
          de_in_state <= DE_IN_CNT;  // 检测到场同步下降沿，开始计数
        end
      end
      DE_IN_CNT: begin
        de_in_d0 <= de_in;
        de_in_d1 <= de_in_d0;
        if(de_in_d0 && !de_in_d1) begin
          de_in_cnt <= de_in_cnt + 1'd1;  // 每检测到一个DE上升沿，行数加1
        end
        else if(de_in_cnt == VIDEO_HIGTH) begin
          de_in_state <= DE_IN_END;  // 计数达到视频高度，结束
        end
      end
      DE_IN_END: begin
        vs_in_d0 <= vs_in;
        vs_in_d1 <= vs_in_d0;
        if(vs_in_d0 && !vs_in_d1) begin
          de_in_cnt   <= 'd0;
          de_in_state <= DE_IN_WAIT;  // 检测到场同步上升沿，开始下一帧
        end
      end
    endcase  
  end
end

/////////////////////////////////////////////////////////////////////////////////////
// 缩放DE输入计数模块 - 统计缩放后视频的有效行数
/////////////////////////////////////////////////////////////////////////////////////
always @(posedge pix_clk_in) begin
  if(!ddr_ip_rst_n) begin  
    zoom_vs_in_d0     <= 'd0;
    zoom_vs_in_d1     <= 'd0;
    zoom_de_in_d0     <= 'd0;
    zoom_de_in_d1     <= 'd0;
    zoom_de_in_cnt    <= 'd0; 
    zoom_de_in_state  <= 0;
  end else begin
    case(zoom_de_in_state) 
      DE_IN_WAIT: begin
        zoom_vs_in_d0 <= vs_in;
        zoom_vs_in_d1 <= zoom_vs_in_d0;
        if(!zoom_vs_in_d0 && zoom_vs_in_d1) begin
          zoom_de_in_state <= DE_IN_CNT;  // 检测到场同步下降沿，开始计数
        end
      end
      DE_IN_CNT: begin
        zoom_de_in_d0 <= zoom_de_out;
        zoom_de_in_d1 <= zoom_de_in_d0;
        if(zoom_de_in_d0 && !zoom_de_in_d1) begin
          zoom_de_in_cnt <= zoom_de_in_cnt + 1'd1;  // 每检测到一个DE上升沿，行数加1
        end
        else if(zoom_de_in_cnt == ZOOM_VIDEO_HIGTH) begin
          zoom_de_in_state <= DE_IN_END;  // 计数达到缩放视频高度，结束
        end
      end
      DE_IN_END: begin
        zoom_vs_in_d0 <= vs_in;
        zoom_vs_in_d1 <= zoom_vs_in_d0;
        if(vs_in_d0 && !vs_in_d1) begin
          zoom_de_in_cnt   <= 'd0;
          zoom_de_in_state <= DE_IN_WAIT;  // 检测到场同步上升沿，开始下一帧
        end
      end
    endcase  
  end
end

/////////////////////////////////////////////////////////////////////////////////////
// DE输出计数模块 - 统计输出视频的有效行数
/////////////////////////////////////////////////////////////////////////////////////
always @(posedge pix_clk_out) begin
  if(!ddr_ip_rst_n) begin  
    vs_out_d0    <= 'd0;
    vs_out_d1    <= 'd0;
    de_out_d0    <= 'd0;
    de_out_d1    <= 'd0;
    de_out_cnt   <= 'd0; 
    de_out_state <= 'd0;
  end else begin
    case(de_out_state) 
      DE_OUT_WAIT: begin
        vs_out_d0 <= vs_out;
        vs_out_d1 <= vs_out_d0;
        if(!vs_out_d0 && vs_out_d1) begin
          de_out_state <= DE_OUT_CNT;  // 检测到场同步下降沿，开始计数
        end
      end
      DE_OUT_CNT: begin
        de_out_d0 <= de_out;
        de_out_d1 <= de_out_d0;
        if(de_out_d0 && !de_out_d1) begin
          de_out_cnt <= de_out_cnt + 1'd1;  // 每检测到一个DE上升沿，行数加1
        end
        else if(de_out_cnt == VIDEO_HIGTH) begin
          de_out_state <= DE_OUT_END;  // 计数达到视频高度，结束
        end
      end
      DE_OUT_END: begin
        vs_out_d0 <= vs_out;
        vs_out_d1 <= vs_out_d0;
        if(vs_out_d0 && !vs_out_d1) begin
          de_out_cnt   <= 'd0;
          de_out_state <= DE_OUT_WAIT;  // 检测到场同步上升沿，开始下一帧
        end
      end
    endcase  
  end
end


/////////////////////////////////////////////////////////////////////////////////////
// PLL时钟生成模块
/////////////////////////////////////////////////////////////////////////////////////
wire cfg_clk;
wire rst_board = ddr_ip_rst_n;

pll u_pll (
  .clkin1   (sys_clk     ),  // 27MHz输入
  .clkout0  (pix_clk_out ),  // 
  // .clkout1(cfg_clk),    // output10M
  // .clkout2(clk_25M),    // output25M
  .lock     (locked      )
);

cmos_pll cmos_pll (
  .clkin1(sys_clk),       // input
  .clkout0(cfg_clk),    // output10M
  .clkout1(clk_25M),    // output25M
  .lock()         // output

);
// HDMI复位延时
always @(posedge cfg_clk) begin
  if(!locked)
    rstn_1ms <= 16'd0;
  else begin
    if(rstn_1ms == 16'h2710)  // 10ms延时
      rstn_1ms <= rstn_1ms;
    else
      rstn_1ms <= rstn_1ms + 1'b1;
  end
end

assign hdmi_rst = (rstn_1ms == 16'h2710);

// MS72xx HDMI收发器配置
wire init_over_rx;
wire pll_lock;
wire core_clk;
wire phy_pll_lock, gpll_lock, rst_gpll_lock, ddrphy_cpd_lock;
wire init_over_tx;

ms72xx_ctl ms72xx_ctl(
  .clk          (cfg_clk     ),
  .rst_n        (hdmi_rst    ),
  .init_over    (init_over_tx),
  .init_over_rx (init_over_rx),
  .iic_scl      (iic_tx_scl  ),
  .iic_sda      (iic_tx_sda  )
);

/////////////////////////////////////////////////////////////////////////////////////
// OV5640摄像头配置模块
/////////////////////////////////////////////////////////////////////////////////////
// 上电延时模块，产生摄像头初始化使能信号
power_on_delay power_on_delay_inst(
  .clk_50M      (sys_clk        ),
  .reset_n      (1'b1           ),
  .camera1_rstn (cmos1_reset    ),
  .camera2_rstn (cmos2_reset    ),
  .camera_pwnd  (               ),
  .initial_en   (initial_en     )
);

// 摄像头1 I2C寄存器配置
reg_config coms1_reg_config(
  .clk_25M       (clk_25M            ),
  .camera_rstn   (cmos1_reset        ),
  .initial_en    (initial_en         ),
  .i2c_sclk      (cmos1_scl          ),
  .i2c_sdat      (cmos1_sda          ),
  .reg_conf_done (cmos_init_done[0]  ),
  .reg_index     (                   ),
  .clock_20k     (                   )
);

// 摄像头2 I2C寄存器配置
reg_config coms2_reg_config(
  .clk_25M       (clk_25M            ),
  .camera_rstn   (cmos2_reset        ),
  .initial_en    (initial_en         ),
  .i2c_sclk      (cmos2_scl          ),
  .i2c_sdat      (cmos2_sda          ),
  .reg_conf_done (cmos_init_done[1]  ),
  .reg_index     (                   ),
  .clock_20k     (                   )
);

/////////////////////////////////////////////////////////////////////////////////////
// 摄像头8位转16位模块
// 将8位RGB565数据转换为16位RGB565数据
/////////////////////////////////////////////////////////////////////////////////////
// 摄像头1
always@(posedge cmos1_pclk) begin
  cmos1_d_d0     <= cmos1_data;
  cmos1_href_d0  <= cmos1_href;
  cmos1_vsync_d0 <= cmos1_vsync;
end

cmos_8_16bit cmos1_8_16bit(
  .pclk      (cmos1_pclk       ),
  .rst_n     (cmos_init_done[0]),
  .pdata_i   (cmos1_d_d0       ),
  .de_i      (cmos1_href_d0    ),
  .vs_i      (cmos1_vsync_d0   ),
  .pixel_clk (cmos1_pclk_16bit ),
  .pdata_o   (cmos1_d_16bit    ),
  .de_o      (cmos1_href_16bit )
);

// 摄像头2
always@(posedge cmos2_pclk) begin
  cmos2_d_d0     <= cmos2_data;
  cmos2_href_d0  <= cmos2_href;
  cmos2_vsync_d0 <= cmos2_vsync;
end

cmos_8_16bit cmos2_8_16bit(
  .pclk      (cmos2_pclk       ),
  .rst_n     (cmos_init_done[1]),
  .pdata_i   (cmos2_d_d0       ),
  .de_i      (cmos2_href_d0    ),
  .vs_i      (cmos2_vsync_d0   ),
  .pixel_clk (cmos2_pclk_16bit ),
  .pdata_o   (cmos2_d_16bit    ),
  .de_o      (cmos2_href_16bit )
);

/////////////////////////////////////////////////////////////////////////////////////
// 复位同步器
/////////////////////////////////////////////////////////////////////////////////////
reg rstn_sync1, rstn_sync2;
always @(posedge core_clk or negedge locked) begin
  if(!locked) begin
    rstn_sync1 <= 1'b0;
    rstn_sync2 <= 1'b0;
  end else begin
    rstn_sync1 <= 1'b1;
    rstn_sync2 <= rstn_sync1;
  end
end

assign ddr_ip_rst_n = rstn_sync2;  // DDR IP核复位信号

/////////////////////////////////////////////////////////////////////////////////////
// AXI主控制器仲裁模块
// 负责DDR读写控制和视频FIFO管理
/////////////////////////////////////////////////////////////////////////////////////
parameter DQ_WIDTH = MEM_DQ_WIDTH;
axi_m_arbitration #(
  .VIDEO_LENGTH      (VIDEO_LENGTH     ),
  .VIDEO_HIGTH       (VIDEO_HIGTH      ),
  .ZOOM_VIDEO_LENGTH (ZOOM_VIDEO_LENGTH),
  .ZOOM_VIDEO_HIGTH  (ZOOM_VIDEO_HIGTH ),
  .PIXEL_WIDTH       (PIXEL_WIDTH      ),
  .CTRL_ADDR_WIDTH   (CTRL_ADDR_WIDTH  ),
  .DQ_WIDTH          (DQ_WIDTH         ),
  .M_AXI_BRUST_LEN   (M_AXI_BRUST_LEN  )
)
user_axi_m_arbitration (
  .DDR_INIT_DONE     (ddr_init_done   ),
  .M_AXI_ACLK        (core_clk        ),
  .M_AXI_ARESETN     (ddr_ip_rst_n && ddr_init_done),
  .pix_clk_out       (pix_clk_out     ),
  
  // AXI写地址通道
  .M_AXI_AWID        (M_AXI_AWID      ),
  .M_AXI_AWADDR      (M_AXI_AWADDR    ),
  .M_AXI_AWUSER      (M_AXI_AWUSER    ),
  .M_AXI_AWVALID     (M_AXI_AWVALID   ),
  .M_AXI_AWREADY     (M_AXI_AWREADY   ),
  
  // AXI写数据通道
  .M_AXI_WDATA       (M_AXI_WDATA     ),
  .M_AXI_WSTRB       (M_AXI_WSTRB     ),
  .M_AXI_WLAST       (M_AXI_WLAST     ),
  .M_AXI_WUSER       (M_AXI_WUSER     ),
  .M_AXI_WREADY      (M_AXI_WREADY    ),
  
  // AXI读地址通道
  .M_AXI_ARID        (M_AXI_ARID      ),
  .M_AXI_ARUSER      (M_AXI_ARUSER    ),
  .M_AXI_ARADDR      (M_AXI_ARADDR    ),
  .M_AXI_ARVALID     (M_AXI_ARVALID   ),
  .M_AXI_ARREADY     (M_AXI_ARREADY   ),
  
  // AXI读数据通道
  .M_AXI_RID         (M_AXI_RID       ),
  .M_AXI_RDATA       (M_AXI_RDATA     ),
  .M_AXI_RLAST       (M_AXI_RLAST     ),
  .M_AXI_RVALID      (M_AXI_RVALID    ),
  
  // 视频同步信号
  .vs_in             (vs_in           ),
  .vs_out            (vs_out          ),
  
  // FIFO0 - 四宫格左上角(缩放后的HDMI输入)
  .video0_clk_in     (pix_clk_in      ),
  .video0_de_in      (zoom_de_out     ),
  .video0_data_in    (zoom_data_out   ),
  .video0_rd_en      (video0_rd_en    ),
  .video0_data_out   (video0_data_out ),
  .fram0_done        (fram0_done      ),
  .video0_vs_in      (vs_in           ),
  
  // FIFO1 - 四宫格右上角(缩放后的HDMI输入)
  .video1_clk_in           (rgmii_clk_0    ),    
  .video1_de_in            (eth0_rx_de     ),
  .video1_data_in          ({eth0_rx_data[15:11],5'b0,eth0_rx_data[10:5],4'b0,eth0_rx_data[4:0],7'b0} ),
  .video1_rd_en            (video1_rd_en   ),
  .video1_data_out         (video1_data_out),
  .fram1_done              (fram1_done     ),
  .video1_vs_in            (eth0_rx_vs     ),//用于抓取复位
  
  // FIFO2 - 四宫格左下角(摄像头1输入)
  .video2_clk_in     (cmos1_pclk_16bit),
  .video2_de_in      (cmos1_href_16bit),
  .video2_data_in    ({cmos1_d_16bit[4:0], 5'b0, cmos1_d_16bit[10:5], 4'b0, cmos1_d_16bit[15:11], 7'b0}),
  .video2_rd_en      (video2_rd_en    ),
  .video2_data_out   (video2_data_out ),
  .fram2_done        (fram2_done      ),
  .video2_vs_in      (cmos1_vsync_d0  ),
  
  // FIFO3 - 四宫格右下角(摄像头2输入)
  .video3_clk_in     (cmos2_pclk_16bit),
  .video3_de_in      (cmos2_href_16bit),
  .video3_data_in    ({cmos2_d_16bit[4:0], 5'b0, cmos2_d_16bit[10:5], 4'b0, cmos2_d_16bit[15:11], 7'b0}),
  .video3_rd_en      (video3_rd_en    ),
  .video3_data_out   (video3_data_out ),
  .fram3_done        (fram3_done      ),
  .video3_vs_in      (cmos2_vsync_d0  ),
  
  // DDR地址范围配置
  .wr_addr_min       (RW_ADDR_MIN     ),  // DDR写起始地址
  .wr_addr_max       (RW_ADDR_MAX     ),  // DDR写结束地址
  .y_act             (y_act           ),  // 当前有效像素Y坐标
  .x_act             (x_act           )   // 当前有效像素X坐标
);





/////////////////////////////////////////////////////////////////////////////////////
// DDR参考时钟生成
// 使用GTP差分缓冲器将差分时钟转换为单端时钟
/////////////////////////////////////////////////////////////////////////////////////
wire clk_125Mhz;

GTP_INBUFGDS #(
  .IOSTANDARD("DEFAULT"),
  .TERM_DIFF("ON")
) u_gtp (
  .O  (clk_125Mhz),  // 单端时钟输出
  .I  (clk_p     ),  // 差分时钟正端输入
  .IB (clk_n     )   // 差分时钟负端输入
);

/////////////////////////////////////////////////////////////////////////////////////
// DDR3控制器模块
// 例化DDR3 IP核，实现DDR3存储器读写控制
/////////////////////////////////////////////////////////////////////////////////////
ddr3_test u_ddr3_test_h(
  // 时钟和复位
  .ref_clk                   (clk_125Mhz            ),
  .resetn                    (hdmi_rst              ),
  .ddr_init_done             (ddr_init_done         ),
  
  // PLL状态输出
  .pll_lock                  (pll_lock              ),
  .core_clk                  (core_clk              ),
  .phy_pll_lock              (phy_pll_lock          ),
  .gpll_lock                 (gpll_lock             ),
  .rst_gpll_lock             (rst_gpll_lock         ),
  .ddrphy_cpd_lock           (ddrphy_cpd_lock       ),
  
  // AXI写地址通道
  .axi_awaddr                (M_AXI_AWADDR          ),
  .axi_awuser_ap             (M_AXI_AWUSER          ),
  .axi_awuser_id             (M_AXI_AWID            ),
  .axi_awlen                 (M_AXI_BRUST_LEN       ),
  .axi_awready               (M_AXI_AWREADY         ),
  .axi_awvalid               (M_AXI_AWVALID         ),
  
  // AXI写数据通道
  .axi_wdata                 (M_AXI_WDATA           ),
  .axi_wstrb                 (M_AXI_WSTRB           ),
  .axi_wready                (M_AXI_WREADY          ),
  .axi_wusero_id             (M_AXI_WUSER           ),
  .axi_wusero_last           (M_AXI_WLAST           ),
  
  // AXI读地址通道
  .axi_araddr                (M_AXI_ARADDR          ),
  .axi_aruser_ap             (M_AXI_ARUSER          ),
  .axi_aruser_id             (M_AXI_ARID            ),
  .axi_arlen                 (M_AXI_BRUST_LEN       ),
  .axi_arready               (M_AXI_ARREADY         ),
  .axi_arvalid               (M_AXI_ARVALID         ),
  
  // AXI读数据通道
  .axi_rdata                 (M_AXI_RDATA           ),
  .axi_rid                   (M_AXI_RID             ),
  .axi_rlast                 (M_AXI_RLAST           ),
  .axi_rvalid                (M_AXI_RVALID          ),
  
  // APB配置接口(未使用)
  .apb_clk                   (1'b0                  ),
  .apb_rst_n                 (1'b1                  ),
  .apb_sel                   (1'b0                  ),
  .apb_enable                (1'b0                  ),
  .apb_addr                  (8'b0                  ),
  .apb_write                 (1'b0                  ),
  .apb_ready                 (                      ),
  .apb_wdata                 (16'b0                 ),
  .apb_rdata                 (                      ),
  
  // DDR3物理接口
  .mem_rst_n                 (mem_rst_n             ),
  .mem_ck                    (mem_ck                ),
  .mem_ck_n                  (mem_ck_n              ),
  .mem_cke                   (mem_cke               ),
  .mem_cs_n                  (mem_cs_n              ),
  .mem_ras_n                 (mem_ras_n             ),
  .mem_cas_n                 (mem_cas_n             ),
  .mem_we_n                  (mem_we_n              ),
  .mem_odt                   (mem_odt               ),
  .mem_a                     (mem_a                 ),
  .mem_ba                    (mem_ba                ),
  .mem_dqs                   (mem_dqs               ),
  .mem_dqs_n                 (mem_dqs_n             ),
  .mem_dq                    (mem_dq                ),
  .mem_dm                    (mem_dm                ),
  
  // 调试接口
  .dbg_gate_start            (1'b0                  ),
  .dbg_cpd_start             (1'b0                  ),
  .dbg_ddrphy_rst_n          (1'b1                  ),
  .dbg_gpll_scan_rst         (1'b0                  ),
  .samp_position_dyn_adj     (1'b0                  ),
  .init_samp_position_even   (32'd0                 ),
  .init_samp_position_odd    (32'd0                 ),
  .wrcal_position_dyn_adj    (1'b0                  ),
  .init_wrcal_position       (32'd0                 ),
  .force_read_clk_ctrl       (1'b0                  ),
  .init_slip_step            (16'd0                 ),
  .init_read_clk_ctrl        (12'd0                 ),
  .debug_calib_ctrl          (                      ),
  .dbg_slice_status          (                      ),
  .dbg_slice_state           (                      ),
  .debug_data                (                      ),
  .dbg_dll_upd_state         (                      ),
  .debug_gpll_dps_phase      (                      ),
  .dbg_rst_dps_state         (                      ),
  .dbg_tran_err_rst_cnt      (                      ),
  .dbg_ddrphy_init_fail      (                      ),
  .debug_cpd_offset_adj      (1'b0                  ),
  .debug_cpd_offset_dir      (1'b0                  ),
  .debug_cpd_offset          (10'd0                 ),
  .debug_dps_cnt_dir0        (                      ),
  .debug_dps_cnt_dir1        (                      ),
  .ck_dly_en                 (1'b0                  ),
  .init_ck_dly_step          (8'h0                  ),
  .ck_dly_set_bin            (                      ),
  .align_error               (                      ),
  .debug_rst_state           (                      ),
  .debug_cpd_state           (                      )
);

/////////////////////////////////////////////////////////////////////////////////////
// 视频时序生成模块
// 产生HDMI输出的VS、HS、DE时序信号
/////////////////////////////////////////////////////////////////////////////////////
sync_vg sync_vg(
  .clk       (pix_clk_out             ),  // 像素时钟输出
  .rstn      (ddr_ip_rst_n && ddr_init_done),
  .vs_out    (vs_out                  ),
  .hs_out    (hs_out                  ),
  .de_out    (de_out                  ),
  .de_re     (                        ),
  .x_act     (x_act                   ),  // 当前有效像素X坐标
  .y_act     (y_act                   )   // 当前有效像素Y坐标
);
/////////////////////////////////////////////////////////////////////////////////////
// 视频缩放模块
// 将1080p输入视频缩放为540p
/////////////////////////////////////////////////////////////////////////////////////
video_zoom hdmi_video_zoom(
  .clk            (pix_clk_in         ),
  .rstn           (ddr_ip_rst_n && ddr_init_done),
  .vs_in          (vs_in              ),
  .hs_in          (hs_in              ),
  .de_in          (de_in              ),
  .video_data_in  (rgb_in             ),
  .de_out         (zoom_de_out        ),
  .video_data_out (zoom_data_out      )
);


// reg                           r_vs_out; 
// reg                           r_hs_out;
// reg                           r_de_out;
// reg  [7 : 0]                  r_r_out;
// reg  [7 : 0]                  r_g_out;
// reg  [7 : 0]                  r_b_out;
  


/////////////////////////////////////////////////////////////////////////////////////
// 视频输出模块 - 实现四宫格显示
// 将四个视频源(DDR0/1/2/3)按照四宫格布局输出到HDMI
/////////////////////////////////////////////////////////////////////////////////////
always @(posedge pix_clk_out) begin
  if(!ddr_ip_rst_n) begin
    r_vs_out          <= 'd0;
    r_hs_out          <= 'd0;
    r_de_out          <= 'd0;
    r_r_out           <= 'd0;
    r_g_out           <= 'd0;
    r_b_out           <= 'd0;
    v_sync_flag       <= 'd0;
    video0_rd_en      <= 1'b0; 
    video1_rd_en      <= 1'b0; 
    video2_rd_en      <= 1'b0; 
    video3_rd_en      <= 1'b0; 
    video_pre_rd_flag <= 1'b0;
    out_state         <= 'd0;
  end else if(ddr_init_done) begin 
    r_vs_out_d0 <= vs_out;
    r_vs_out    <= r_vs_out_d0;
    r_hs_out    <= hs_out;
    r_de_out_d0 <= de_out;
    r_de_out    <= r_de_out_d0;
    r_x_act_d0  <= x_act;
    r_x_act     <= r_x_act_d0;

    // 场同步结束，开始预读FIFO
    if(vs_out_d0 && !vs_out_d1) begin
      video_pre_rd_flag <= 'd0;
    end else if(!vs_out_d0 && vs_out_d1 && !video_pre_rd_flag && (fram0_done || fram1_done || fram2_done || fram3_done)) begin
      video0_rd_en      <= 'd1;
      video1_rd_en      <= 'd1;
      video2_rd_en      <= 'd1;
      video3_rd_en      <= 'd1;
      video_pre_rd_flag <= 'd1;
      out_state         <= 'd1;
    end else begin
      // 四宫格显示 - 左上角(视频源0)
      if(fram0_done && (r_x_act >= 0) && (r_x_act < ZOOM_VIDEO_LENGTH - 1) && (y_act < ZOOM_VIDEO_HIGTH) && (y_act >= 0)) begin
        r_r_out        <= video0_data_out[31:24];
        r_g_out        <= video0_data_out[21:14];
        r_b_out        <= video0_data_out[11:4];  
        video0_rd_en   <= de_out;
        video1_rd_en   <= 'd0; 
        video2_rd_en   <= 'd0; 
        video3_rd_en   <= 'd0;
        out_state      <= 'd2;
        if(r_x_act == ZOOM_VIDEO_LENGTH - 2) begin
          video1_rd_en <= de_out;
          video0_rd_en <= 'd0;
        end
      end
      
      // 四宫格显示 - 右上角(视频源1)
      if(fram1_done && (r_x_act >= ZOOM_VIDEO_LENGTH - 1) && (r_x_act < VIDEO_LENGTH - 1) && (y_act < ZOOM_VIDEO_HIGTH) && (y_act >= 0)) begin
        r_r_out        <= video1_data_out[31:24];
        r_g_out        <= video1_data_out[21:14];
        r_b_out        <= video1_data_out[11:4];
        video0_rd_en   <= 'd0; 
        video1_rd_en   <= de_out; 
        video2_rd_en   <= 'd0; 
        video3_rd_en   <= 'd0; 
        out_state      <= 'd3;
      end  
      
      // 四宫格显示 - 左下角(视频源2 - 摄像头1)
      if(fram2_done && (r_x_act >= 0) && (r_x_act < ZOOM_VIDEO_LENGTH - 1) && (y_act < VIDEO_HIGTH) && (y_act >= ZOOM_VIDEO_HIGTH)) begin
        r_r_out        <= video2_data_out[31:24];
        r_g_out        <= video2_data_out[21:14];
        r_b_out        <= video2_data_out[11:4];  
        video0_rd_en   <= 'd0; 
        video1_rd_en   <= 'd0; 
        video2_rd_en   <= de_out; 
        video3_rd_en   <= 'd0; 
        out_state      <= 'd4;
        if(r_x_act == ZOOM_VIDEO_LENGTH - 2) begin
          video3_rd_en <= de_out;
          video2_rd_en <= 'd0;
        end
      end    
      
      // 四宫格显示 - 右下角(视频源3 - 摄像头2)
      if(fram3_done && (r_x_act >= ZOOM_VIDEO_LENGTH - 1) && (r_x_act < VIDEO_LENGTH - 1) && (y_act < VIDEO_HIGTH) && (y_act >= ZOOM_VIDEO_HIGTH)) begin
        r_r_out        <= video3_data_out[31:24];
        r_g_out        <= video3_data_out[21:14];
        r_b_out        <= video3_data_out[11:4];     
        video0_rd_en   <= 'd0; 
        video1_rd_en   <= 'd0; 
        video2_rd_en   <= 'd0; 
        video3_rd_en   <= de_out; 
        out_state      <= 'd5;
      end 
    end         
  end else begin
    // DDR未初始化完成，输出白色测试画面
    r_vs_out     <= 'd0;
    r_hs_out     <= 'd0;
    r_de_out     <= 'd0;
    r_r_out      <= 8'hff;
    r_g_out      <= 8'hff;
    r_b_out      <= 8'hff;
    video0_rd_en <= 1'b0; 
    video1_rd_en <= 1'b0; 
    video2_rd_en <= 1'b0; 
    video3_rd_en <= 1'b0; 
    out_state    <= 'd7; 
  end            
end
/////////////////////////////////////////////////////////////////////////////////////
// 视频处理模块信号定义
/////////////////////////////////////////////////////////////////////////////////////
wire         video_process_vs_out;
wire         video_process_hs_out;
wire         video_process_de_out;
wire [7 : 0] video_process_r_out;
wire [7 : 0] video_process_g_out;
wire [7 : 0] video_process_b_out;

wire [7  : 0] video_enhance_lightdown_num;
wire          video_enhance_lightdown_sw ;
wire [7  : 0] video_enhance_darkup_num   ;
wire          video_enhance_darkup_sw    ;
/////////////////////////////////////////////////////////////////////////////////////
// 视频处理模块
// 实现亮度、对比度等图像增强功能
/////////////////////////////////////////////////////////////////////////////////////
video_process u_video_process(
  .pix_clk                     (pix_clk_out                 ),
  .rst_n                       (ddr_ip_rst_n && ddr_init_done),
  .vs_in                       (r_vs_out                    ),  // 使用延迟后的同步信号
  .hs_in                       (r_hs_out                    ),  // 使用延迟后的同步信号
  .de_in                       (r_de_out                    ),  // 使用延迟后的数据使能
  .r_in                        (r_r_out                     ),  // 使用四宫格输出
  .g_in                        (r_g_out                     ),
  .b_in                        (r_b_out                     ),
  
  .vs_out                      (video_process_vs_out        ),
  .hs_out                      (video_process_hs_out        ),
  .de_out                      (video_process_de_out        ),
  .r_out                       (video_process_r_out         ),
  .g_out                       (video_process_g_out         ),
  .b_out                       (video_process_b_out         ),
  
  // 图像增强参数配置
  .video_enhance_lightdown_num (video_enhance_lightdown_num ),
  .video_enhance_lightdown_sw  (video_enhance_lightdown_sw  ),
  .video_enhance_darkup_num    (video_enhance_darkup_num    ),
  .video_enhance_darkup_sw     (video_enhance_darkup_sw     )
);



// /////////////////////////////////////////////////////////////////////////////////////
// // 最终HDMI输出：使用增强后的视频数据
// /////////////////////////////////////////////////////////////////////////////////////
// always @(posedge pix_clk_out) begin
//   if(!ddr_ip_rst_n) begin
//     hdmi_vs_out <= 1'b0;
//     hdmi_hs_out <= 1'b0;
//     hdmi_de_out <= 1'b0;
//     hdmi_r_out  <= 8'd0;
//     hdmi_g_out  <= 8'd0;
//     hdmi_b_out  <= 8'd0;
//   end else if(ddr_init_done) begin
//     // 使用增强后的数据作为HDMI输出
//     hdmi_vs_out <= video_process_vs_out;
//     hdmi_hs_out <= video_process_hs_out;
//     hdmi_de_out <= video_process_de_out;
//     hdmi_r_out  <= video_process_r_out;
//     hdmi_g_out  <= video_process_g_out;
//     hdmi_b_out  <= video_process_b_out;
//   end else begin
//     // DDR未初始化完成，输出白色测试画面
//     hdmi_vs_out <= 1'b0;
//     hdmi_hs_out <= 1'b0;
//     hdmi_de_out <= 1'b0;
//     hdmi_r_out  <= 8'hff;
//     hdmi_g_out  <= 8'hff;
//     hdmi_b_out  <= 8'hff;
//   end
// end
/////////////////////////////////////////////////////////////////////////////////////
// 心跳信号生成模块
// 用于指示DDR初始化状态和系统运行状态
/////////////////////////////////////////////////////////////////////////////////////
always @(posedge core_clk) begin
  if (!ddr_init_done)
    cnt <= 27'd0;
  else if (cnt >= TH_1S)
    cnt <= 27'd0;
  else
    cnt <= cnt + 27'd1;
end

always @(posedge core_clk) begin
  if (!ddr_init_done)
    heart_beat_led <= 1'd1;  // DDR未初始化完成，LED常亮
  else if (cnt >= TH_1S)
    heart_beat_led <= ~heart_beat_led;  // DDR初始化完成，LED每秒翻转一次
end

/////////////////////////////////////////////////////////////////////////////////////
// HDMI初始化完成指示灯
// 当HDMI收发器初始化完成后点亮
/////////////////////////////////////////////////////////////////////////////////////
assign hdmi_int_led = init_over_tx;


//以太网传输

wire [15 : 0] eth0_img_data;
wire          eth0_img_de  ;
//assign eth0_img_de = zoom_de_out;
//assign eth0_img_data[15 : 11] = zoom_data_out[31 : 27];//r5 
//assign eth0_img_data[10 :  5] = zoom_data_out[21 : 16];//g6 
//assign eth0_img_data[4  :  0] = zoom_data_out[11 :  7];//b5 



wire             rgmii_clk_0/* synthesis PAP_MARK_DEBUG="1" */;
wire             eth0_img_de/* synthesis PAP_MARK_DEBUG="1" */;
wire [15 : 0]    eth0_img_data/* synthesis PAP_MARK_DEBUG="1" */;
wire             tx_req/* synthesis PAP_MARK_DEBUG="1" */;
wire             udp_tx_done/* synthesis PAP_MARK_DEBUG="1" */;
wire             tx_start_en/* synthesis PAP_MARK_DEBUG="1" */;
wire [31 : 0]    tx_data    /* synthesis PAP_MARK_DEBUG="1" */;
wire [15 : 0]    tx_byte_num/* synthesis PAP_MARK_DEBUG="1" */;
wire             mac_tx_data_valid_0/* synthesis PAP_MARK_DEBUG="1" */;
wire [7  : 0]    mac_tx_data_0      /* synthesis PAP_MARK_DEBUG="1" */;
wire             mac_rx_error_0     /* synthesis PAP_MARK_DEBUG="1" */;
wire             mac_rx_data_valid_0/* synthesis PAP_MARK_DEBUG="1" */;
wire [7  : 0]    mac_rx_data_0      /* synthesis PAP_MARK_DEBUG="1" */;
wire             rec_pkt_done/* synthesis PAP_MARK_DEBUG="1" */;
wire             rec_en      /* synthesis PAP_MARK_DEBUG="1" */;
wire [31 : 0]    rec_data    /* synthesis PAP_MARK_DEBUG="1" */;
wire [15 : 0]    rec_byte_num/* synthesis PAP_MARK_DEBUG="1" */;

wire [15 : 0]    eth0_rx_data/* synthesis PAP_MARK_DEBUG="1" */;
wire [15 : 0]    vesa_debug_data/* synthesis PAP_MARK_DEBUG="1" */;
wire             eth0_rx_de  /* synthesis PAP_MARK_DEBUG="1" */;
wire             eth0_rx_vs  /* synthesis PAP_MARK_DEBUG="1" */;
//将图像封装为ip帧格式
/*vesa_debug 
#(
.PIX_WIGHT(16)
)
eth_vesa_debug(
.pix_clk  (pixclk_in   ),//input wire    
.rstn     (rstn_out    ),//input wire    
.vs       (vs_in        ),//input wire    
.de       (zoom_de_out  ),//input wire    
.vesa_data(vesa_debug_data) //output reg [15 : 0]   
);*/
	ref_clock ref_clock (
	  .clkout0(rgmii_clk_90p),    // output。90度相移时钟，用于DDR双沿采样
	  .lock(rst_eth),          // output
	  .clkin1(rgmii_rxc)       // input=rgmii_clk。PHY芯片接收时钟
	);

  	watch_clk watch_clock (
	  .clkout0(rgmii_clk_watch),    // 250M时钟
	  .lock(),          // output
	  .clkin1(rgmii_rxc)       // input=rgmii_clk。PHY芯片接收时钟
	);
	

eth_img_rec
#(
	. PIXEL_WIDTH 	(  32   )                             ,
	.  VIDEO_LENGTH (16'd960)                             ,
	.  VIDEO_HIGTH  (16'd540)                             
)
eth0_img_rec(
.eth_rx_clk   (rgmii_clk_0  ),//input wire                         
.rstn         (rst_eth    ),//input wire                         
.udp_date_rcev(rec_data     ),//input wire [31: 0]   
.udp_date_en  (rec_en       ),//input wire                         
.img_data_en  (eth0_rx_de  ),//output reg                         
.img_data_vs  (eth0_rx_vs  ),//output reg                         
.img_data     (eth0_rx_data) //output reg [15: 0]   
 );
  
wire [15:0] rgb565 = {r_r_out[7:3], r_g_out[7:2], r_b_out[7:3]};


eth_img_pkt eth0_img_pkt(    
    .rst_n              (rst_eth       ), //input                    
    ////图像相关信号              
    .cam_pclk           (pix_clk_out      ), //input  图像时钟             
    .img_vsync          (r_vs_out           ), //input  帧同步               
    .img_data_en        (r_de_out     ), //input  de               
    .img_data           ({rgb565[15 : 11],rgb565[10 : 5],rgb565[4 : 0]}), //input  [15:0]   //vesa_debug_data //eth0_img_data
    .transfer_flag      (1               ), //input                                        
    ////以太网相关信号
    .eth_tx_clk         (rgmii_clk_0     ), //input                          
    .udp_tx_req         (tx_req          ), //input                
    .udp_tx_done        (udp_tx_done     ), //input                
    .udp_tx_start_en    (tx_start_en     ), //output  reg          
    .udp_tx_data        (tx_data         ), //output       [31:0]  
    .udp_tx_byte_num    (tx_byte_num     )  //output  reg  [15:0]  
    ); 

wire [8:0] delay_step_b;
wire error_en;  
wire [8:0] best_delay;
wire done;
wire start;

rgmii_interface 
#(
    .delay_step_c       (8'd220),
    .delay_step_b       (8'd220)

)
u_rgmii_interface(//外部PHY-4bit双沿采样RGMII转为FPGA内部协议栈的8bit-单采样GMII接口
	.rst                       (  ~rst_eth              ),//input        rst,
	.rgmii_clk                 (  rgmii_clk_0          ),//output       rgmii_clk,
	.rgmii_clk_90p             (       ),//input        rgmii_clk_90p,这个信号没有用上
//MAC发送
	.mac_tx_data_valid         (  mac_tx_data_valid_0     ),//input        mac_tx_data_valid,
	.mac_tx_data               (  mac_tx_data_0        ),//input [7:0]  mac_tx_data,
//MAC接收
	.mac_rx_error              (  mac_rx_error_0  ),//output       mac_rx_error,
	.mac_rx_data_valid         (  mac_rx_data_valid_0  ),//output       mac_rx_data_valid,
	.mac_rx_data               (  mac_rx_data_0        ),//output [7:0] mac_rx_data,

// PHY RX													 
	.rgmii_rxc                 (  rgmii_clk_90p         ),//input   //或许不一样     rgmii_rxc,查询后这个信号确实应该是clk_90p，我确信
	.rgmii_rx_ctl              (  rgmii_rx_ctl       ),//input        rgmii_rx_ctl,
	.rgmii_rxd                 (  rgmii_rxd          ),//input [3:0]  rgmii_rxd,

// PHY TX													 
	.rgmii_txc                 (  rgmii_txc          ),//output       rgmii_txc,
	.rgmii_tx_ctl              (  rgmii_tx_ctl       ),//output       rgmii_tx_ctl,
	.rgmii_txd                 (  rgmii_txd          ) //output [3:0] rgmii_txd 
); 

//ETH0_GMII_RGMII
/*gmii_to_rgmii eth0_gmii_to_rgmii(
   .rgmii_clk             (rgmii_clk_0       ),    // output GMII时钟，供数据使用      
   .rst                   (rst_eth         ),    // input        
    //mac输入的数据由gmii转化为rgmii，时钟为rgmii_clk
   .mac_tx_data_valid     (mac_tx_data_valid_0),    // input        
   .mac_tx_data           (mac_tx_data_0      ),    // input [7:0]  
    //eth输入的数据由rgmii转化为gmii，时钟为rgmii_clk
   .mac_rx_error          (mac_rx_error_0     ),    //output reg       
   .mac_rx_data_valid     (mac_rx_data_valid_0),    //output reg       
   .mac_rx_data           (mac_rx_data_0      ),    //output reg [7:0] 
   //eth接收                
	.rgmii_rxc                 (  rgmii_clk_90p         ),//input   //或许不一样     rgmii_rxc,查询后这个信号确实应该是clk_90p，我确信
	.rgmii_rx_ctl              (  rgmii_rx_ctl       ),//input        rgmii_rx_ctl,
	.rgmii_rxd                 (  rgmii_rxd          ),//input [3:0]  rgmii_rxd,

// PHY TX													 
	.rgmii_txc                 (  rgmii_txc          ),//output       rgmii_txc,
	.rgmii_tx_ctl              (  rgmii_tx_ctl       ),//output       rgmii_tx_ctl,
	.rgmii_txd                 (  rgmii_txd          ) //output [3:0] rgmii_txd 
);*/
//UDP通信
udp_top                                             
   #(
    .BOARD_MAC     (LOCAL_MAC),      //参数例化
    .BOARD_IP      (LOCAL_IP ),
    .DES_MAC       (DEST_MAC  ),
    .DES_IP        (DEST_IP   )
    )
u_udp(
    .rst_n         (rst_eth   ),  //input       复位信号，低电平有效            
    //GMII接口                                
    .gmii_rx_clk   (rgmii_clk_0         ),  //input       GMII接收数据时钟                    
    .gmii_rx_dv    (mac_rx_data_valid_0 ),  //input       GMII输入数据有效信号                
    .gmii_rxd      (mac_rx_data_0       ),  //input [7:0] GMII输入数据                              
    .gmii_tx_clk   (rgmii_clk_0         ),  //input       GMII发送数据时钟            
    .gmii_tx_en    (mac_tx_data_valid_0 ),  //output      GMII输出数据有效信号                  
    .gmii_txd      (mac_tx_data_0       ),  //output[7:0] GMII输出数据              
    //用户接口                                  
    .rec_pkt_done  (rec_pkt_done        ),  //output      以太网单包数据接收完成信号          
    .rec_en        (rec_en              ),  //output      以太网接收的数据使能信号            
    .rec_data      (rec_data            ),  //output[31:0]以太网接收的数据                    
    .rec_byte_num  (rec_byte_num        ),  //output[15:0]以太网接收的有效字节数 单位:byte  
    
    .tx_start_en   (tx_start_en         ),  //input       以太网开始发送信号                  
    .tx_data       (tx_data             ),  //input [31:0]以太网待发送数据                    
    .tx_byte_num   (tx_byte_num         ),  //input [15:0]以太网发送的有效字节数 单位:byte   
    .des_mac       (DEST_MAC             ),  //input [47:0]发送的目标MAC地址            
    .des_ip        (DEST_IP              ),  //input [31:0]发送的目标IP地址              
    .tx_done       (udp_tx_done         ),  //output      以太网发送完成信号                  
    .tx_req        (tx_req              )  , //output      读数据请求信号     
    .error_en      (error_en    )                       
    ); 
	
rgmii_delay_calib u_rgmii_delay_calib(
.clk(rgmii_clk_0),
.rst_n(rst_eth),
.start(1),
.error_en(error_en),

.delay_step_b(delay_step_b),
.best_delay(best_delay),
.done(done)

);

//test led
reg[31:0] cnt_timer;
  always @(posedge rgmii_clk_watch)begin
  cnt_timer<=cnt_timer+1'b1;
if( cnt_timer==32'h1_fff_fff)
begin
   ETH_led=~ETH_led;
    cnt_timer<=32'h0;
end
  end     
/////////////////////////////////////////////////////////////////////////////////////
endmodule