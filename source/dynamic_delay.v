module rgmii_delay_calib (
    input  wire       clk,          // 慢一点的时钟（比如分频后的）
    input  wire       rst_n,

    input  wire       start,        // 开始扫描
    input  wire       error_en,     // =1表示当前delay错误

    output reg  [7:0] delay_step_b, // 输出给IODELAY
    output reg  [7:0] best_delay,   // 最优delay
    output reg        done          // 扫描完成
);

    // ============================
    // 状态定义
    // ============================
    localparam IDLE  = 0;
    localparam SCAN  = 1;
    localparam DONE  = 2;

    reg [1:0] state;

    // ============================
    // 区间记录
    // ============================
    reg [7:0] cur_start;
    reg [7:0] cur_len;

    reg [7:0] best_start;
    reg [7:0] best_len;

    reg       in_good;

    // ============================
    // 主状态机
    // ============================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            delay_step_b <= 0;
            best_delay   <= 0;
            done         <= 0;

            cur_start    <= 0;
            cur_len      <= 0;
            best_start   <= 0;
            best_len     <= 0;
            in_good      <= 0;
        end else begin
            case (state)

            // ====================
            // 等待开始
            // ====================
            IDLE: begin
                done <= 0;
                if (start) begin
                    delay_step_b <= 0;

                    cur_start  <= 0;
                    cur_len    <= 0;
                    best_start <= 0;
                    best_len   <= 0;
                    in_good    <= 0;

                    state <= SCAN;
                end
            end

            // ====================
            // 扫描
            // ====================
            SCAN: begin

                // 当前是“好点”
                if (error_en == 0) begin
                    if (!in_good) begin
                        // 新区间开始
                        in_good   <= 1;
                        cur_start <= delay_step_b;
                        cur_len   <= 1;
                    end else begin
                        cur_len <= cur_len + 1;
                    end
                end else begin
                    // 当前是“坏点”
                    if (in_good) begin
                        // 一个区间结束，比较是否最好
                        if (cur_len > best_len) begin
                            best_len   <= cur_len;
                            best_start <= cur_start;
                        end
                        in_good <= 0;
                    end
                end

                // 扫描递增
                delay_step_b <= delay_step_b + 1;

                // 扫完
                if (delay_step_b == 8'd247) begin
                    // 如果最后停在good区，也要更新
                    if (in_good && cur_len > best_len) begin
                        best_len   <= cur_len;
                        best_start <= cur_start;
                    end

                    state <= DONE;
                end
            end

            // ====================
            // 计算最优点
            // ====================
            DONE: begin
                best_delay <= best_start + (best_len >> 1);
                delay_step_b <= best_start + (best_len >> 1); // 直接锁定

                done <= 1;
                state <= DONE; // 停住
            end

            endcase
        end
    end

endmodule