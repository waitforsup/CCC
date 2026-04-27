module video_process(
    input  wire        pix_clk,        // 视频处理模块时钟
    input  wire        rst_n,          //  新增：复位信号
    input  wire        vs_in,          // 场同步
    input  wire        hs_in,          // 行同步
    input  wire        de_in,          // 数据有效
    input  wire [7:0]  r_in,           // R输入
    input  wire [7:0]  g_in,           // G输入
    input  wire [7:0]  b_in,           // B输入
    
    // RGB输出
    output wire        vs_out,         // 场同步输出
    output wire        hs_out,         // 行同步输出
    output wire        de_out,         // 数据有效输出
    output wire [7:0]  r_out,          // R输出
    output wire [7:0]  g_out,          // G输出
    output wire [7:0]  b_out,          // B输出

    input  wire [7:0]  video_enhance_lightdown_num,
    input  wire        video_enhance_lightdown_sw,
    input  wire [7:0]  video_enhance_darkup_num,
    input  wire        video_enhance_darkup_sw
);

//========================================================================
// 参数定义
//========================================================================
parameter IMG_WIDTH  = 1920;
parameter IMG_HEIGHT = 1080;

//========================================================================
// RGB转YUV中间信号
//========================================================================
wire [7:0]  yuv_y_out;
wire [7:0]  yuv_u_out;
wire [7:0]  yuv_v_out;
wire        yuv_vs_out;
wire        yuv_hs_out;
wire        yuv_de_out;

//========================================================================
// 模块1: RGB转YUV（带图像增强）
//========================================================================
rgb2yuv u_rgb2yuv(
    .clk                           (pix_clk),
    .r_in                          (r_in),
    .g_in                          (g_in),
    .b_in                          (b_in),
    .vs_in                         (vs_in),
    .hs_in                         (hs_in),
    .de_in                         (de_in),
    .y_out                         (yuv_y_out),
    .u_out                         (yuv_u_out),
    .v_out                         (yuv_v_out),
    .vs_out                        (yuv_vs_out),
    .hs_out                        (yuv_hs_out),
    .de_out                        (yuv_de_out),
    .video_enhance_lightdown_num   (video_enhance_lightdown_num),
    .video_enhance_lightdown_sw    (video_enhance_lightdown_sw),
    .video_enhance_darkup_num      (video_enhance_darkup_num),
    .video_enhance_darkup_sw       (video_enhance_darkup_sw)
);

//========================================================================
// Y通道：3x3矩阵化 + 中值滤波
//========================================================================
wire [7:0] matrix11_y, matrix12_y, matrix13_y;
wire [7:0] matrix21_y, matrix22_y, matrix23_y;
wire [7:0] matrix31_y, matrix32_y, matrix33_y;
wire        matrix_de_y;
wire [7:0]  y_median;
wire        y_median_vs;
wire        y_median_hs;
wire        y_median_de;

matrix_3x3 #(
    .IMG_WIDTH  (IMG_WIDTH),
    .IMG_HEIGHT (IMG_HEIGHT)
) u_matrix_3x3_y (
    .video_clk  (pix_clk),
    .rst_n      (rst_n),
    .video_vs   (yuv_vs_out),
    .video_de   (yuv_de_out),
    .video_data (yuv_y_out),     
    .matrix_de  (matrix_de_y),
    .matrix11   (matrix11_y),
    .matrix12   (matrix12_y),
    .matrix13   (matrix13_y),
    .matrix21   (matrix21_y),
    .matrix22   (matrix22_y),
    .matrix23   (matrix23_y),
    .matrix31   (matrix31_y),
    .matrix32   (matrix32_y),
    .matrix33   (matrix33_y)
);

median_filter_3x3 u_median_filter_y (
    .clk         (pix_clk),
    .rst_n       (rst_n),
    .vsync_in    (yuv_vs_out),
    .hsync_in    (matrix_de_y),
    .de_in       (matrix_de_y),
    .data11      (matrix11_y),
    .data12      (matrix12_y),
    .data13      (matrix13_y),
    .data21      (matrix21_y),
    .data22      (matrix22_y),
    .data23      (matrix23_y),
    .data31      (matrix31_y),
    .data32      (matrix32_y),
    .data33      (matrix33_y),
    .target_data (y_median),
    .vsync_out   (y_median_vs),
    .hsync_out   (y_median_hs),
    .de_out      (y_median_de)
);

//========================================================================
// U通道(Cb)：3x3矩阵化 + 中值滤波
//========================================================================
wire [7:0] matrix11_u, matrix12_u, matrix13_u;
wire [7:0] matrix21_u, matrix22_u, matrix23_u;
wire [7:0] matrix31_u, matrix32_u, matrix33_u;
wire        matrix_de_u;
wire [7:0]  u_median;
wire        u_median_vs;
wire        u_median_hs;
wire        u_median_de;

matrix_3x3 #(
    .IMG_WIDTH  (IMG_WIDTH),
    .IMG_HEIGHT (IMG_HEIGHT)
) u_matrix_3x3_u (
    .video_clk  (pix_clk),
    .rst_n      (rst_n),
    .video_vs   (yuv_vs_out),
    .video_de   (yuv_de_out),
    .video_data (yuv_u_out),      //  修正：U通道
    .matrix_de  (matrix_de_u),
    .matrix11   (matrix11_u),
    .matrix12   (matrix12_u),
    .matrix13   (matrix13_u),
    .matrix21   (matrix21_u),
    .matrix22   (matrix22_u),
    .matrix23   (matrix23_u),
    .matrix31   (matrix31_u),
    .matrix32   (matrix32_u),
    .matrix33   (matrix33_u)
);

median_filter_3x3 u_median_filter_u (
    .clk         (pix_clk),
    .rst_n       (rst_n),
    .vsync_in    (yuv_vs_out),
    .hsync_in    (matrix_de_u),
    .de_in       (matrix_de_u),
    .data11      (matrix11_u),
    .data12      (matrix12_u),
    .data13      (matrix13_u),
    .data21      (matrix21_u),
    .data22      (matrix22_u),
    .data23      (matrix23_u),
    .data31      (matrix31_u),
    .data32      (matrix32_u),
    .data33      (matrix33_u),
    .target_data (u_median),
    .vsync_out   (u_median_vs),
    .hsync_out   (u_median_hs),
    .de_out      (u_median_de)
);

//========================================================================
// V通道(Cr)：3x3矩阵化 + 中值滤波
//========================================================================
wire [7:0] matrix11_v, matrix12_v, matrix13_v;
wire [7:0] matrix21_v, matrix22_v, matrix23_v;
wire [7:0] matrix31_v, matrix32_v, matrix33_v;
wire        matrix_de_v;
wire [7:0]  v_median;
wire        v_median_vs;
wire        v_median_hs;
wire        v_median_de;

matrix_3x3 #(
    .IMG_WIDTH  (IMG_WIDTH),
    .IMG_HEIGHT (IMG_HEIGHT)
) u_matrix_3x3_v (
    .video_clk  (pix_clk),
    .rst_n      (rst_n),
    .video_vs   (yuv_vs_out),
    .video_de   (yuv_de_out),
    .video_data (yuv_v_out),     
    .matrix_de  (matrix_de_v),
    .matrix11   (matrix11_v),
    .matrix12   (matrix12_v),
    .matrix13   (matrix13_v),
    .matrix21   (matrix21_v),
    .matrix22   (matrix22_v),
    .matrix23   (matrix23_v),
    .matrix31   (matrix31_v),
    .matrix32   (matrix32_v),
    .matrix33   (matrix33_v)
);

median_filter_3x3 u_median_filter_v (
    .clk         (pix_clk),
    .rst_n       (rst_n),
    .vsync_in    (yuv_vs_out),
    .hsync_in    (matrix_de_v),
    .de_in       (matrix_de_v),
    .data11      (matrix11_v),
    .data12      (matrix12_v),
    .data13      (matrix13_v),
    .data21      (matrix21_v),
    .data22      (matrix22_v),
    .data23      (matrix23_v),
    .data31      (matrix31_v),
    .data32      (matrix32_v),
    .data33      (matrix33_v),
    .target_data (v_median),
    .vsync_out   (v_median_vs),
    .hsync_out   (v_median_hs),
    .de_out      (v_median_de)
);

//========================================================================
// YUV转RGB（使用滤波后的Y/U/V数据）
//========================================================================
yuv2rgb u_yuv2rgb(
    .clk    (pix_clk),
    .y_in   (y_median),           //  修正：使用滤波后的Y
    .u_in   (u_median),           //  修正：使用滤波后的U
    .v_in   (v_median),           //  修正：使用滤波后的V
    .vs_in  (y_median_vs),        //  使用Y通道的同步信号
    .hs_in  (y_median_hs),
    .de_in  (y_median_de),
    .r_out  (r_out),
    .g_out  (g_out),
    .b_out  (b_out),
    .vs_out (vs_out),
    .hs_out (hs_out),
    .de_out (de_out)
);

endmodule