`timescale 1ns / 1ps

//==============================================================================
// img_track.v  --  颜色阈值 + 目标包围盒跟踪（目标颜色可运行时切换）
//
//   sel   = 0 : 阈值图（命中目标颜色显示白色，其余全黑）
//   sel   = 1 : 跟踪框（原图 + 在目标包围盒上画 2 像素黄框）
//
//   color = 0 红   1 绿   2 蓝   3 品红/粉
//           由 T3 按键循环切换
//
//   三通道统一扩到 6 位后比较，保证公平
//==============================================================================

module img_track (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame,     // 帧起始（高有效）
    input  wire        de,        // 像素有效
    input  wire [15:0] din,       // RGB565
    input  wire        sel,       // 0 阈值图 / 1 跟踪框
    input  wire [3:0]  color,     // 目标颜色 0..9
    output wire [15:0] dout
);

    // ---------------- 坐标 ----------------
    reg [9:0] x;
    reg [9:0] y;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= 10'd0;
            y <= 10'd0;
        end
        else if (frame) begin
            x <= 10'd0;
            y <= 10'd0;
        end
        else if (de) begin
            if (x == 10'd799) begin
                x <= 10'd0;
                y <= (y == 10'd599) ? 10'd0 : y + 10'd1;
            end
            else begin
                x <= x + 10'd1;
            end
        end
    end

    // ---- 三通道统一扩到 6 位 ----
    wire [5:0] r6 = {din[15:11], 1'b0};      // 0..62
    wire [5:0] g6 = din[10:5];               // 0..63
    wire [5:0] b6 = {din[4:0],   1'b0};      // 0..62

    // ---------------- 颜色判据（10 色，色相 + 饱和度 + 明暗） ----------------
    wire [5:0] mx = (r6 > g6) ? ((r6 > b6) ? r6 : b6)
                              : ((g6 > b6) ? g6 : b6);
    wire [5:0] mn = (r6 < g6) ? ((r6 < b6) ? r6 : b6)
                              : ((g6 < b6) ? g6 : b6);
    wire [5:0] sat = mx - mn;

    wire [5:0] rg_d = (r6 > g6) ? (r6 - g6) : (g6 - r6);
    wire [5:0] gb_d = (g6 > b6) ? (g6 - b6) : (b6 - g6);
    wire [5:0] rb_d = (r6 > b6) ? (r6 - b6) : (b6 - r6);

    // 0 红（严格：R 要明显压倒 G、B）
    wire is_red    = (sat >= 6'd14) && (r6 >= mx) &&
                     ((r6 - g6) >= 6'd9) && ((r6 - b6) >= 6'd15);

    // 1 绿（G 明显最高）
    wire is_green  = (sat >= 6'd9) && (g6 >= mx) &&
                     ((g6 - r6) >= 6'd7) && ((g6 - b6) >= 6'd6);

    // 2 蓝（B 明显最高）
    wire is_blue   = (sat >= 6'd12) && (b6 >= mx) &&
                     ((b6 - r6) >= 6'd9) && ((b6 - g6) >= 6'd6);

    // 3 品红 / 粉（G 最低，R≈B）
    wire is_pink   = (sat >= 6'd6) && (r6 >= 6'd12) && (b6 >= 6'd10) &&
                     (rb_d <= 6'd8) && ((g6 + 6'd6) < b6) && ((g6 + 6'd6) < r6);

    // 4 黄
    wire is_yellow = (sat >= 6'd12) && (r6 >= 6'd20) && (g6 >= 6'd20) &&
                     (rg_d <= 6'd6) && ((g6 - b6) >= 6'd12);

    // 5 青
    wire is_cyan   = (sat >= 6'd12) && (g6 >= 6'd18) && (b6 >= 6'd16) &&
                     (gb_d <= 6'd6) && ((r6 + 6'd12) < g6);

    // 6 橙
    wire is_orange = (sat >= 6'd12) && (r6 >= mx) &&
                     ((r6 - g6) >= 6'd5) && ((r6 - g6) <= 6'd14) &&
                     ((g6 - b6) >= 6'd6);

    // 7 紫
    wire is_purple = (sat >= 6'd6) && (r6 >= 6'd12) && (b6 >= 6'd14) &&
                     (b6 > r6) && (rb_d <= 6'd8) && ((g6 + 6'd6) < r6);

    // 8 黑：三通道都低
    wire is_black  = (r6 < 6'd16) && (g6 < 6'd16) && (b6 < 6'd16);

    // 9 白：三通道都高且接近
    wire is_white  = (r6 > 6'd44) && (g6 > 6'd44) && (b6 > 6'd42) &&
                     (rg_d <= 6'd6) && (gb_d <= 6'd8);

    wire is_target = (color == 4'd0) ? is_red    :
                     (color == 4'd1) ? is_green  :
                     (color == 4'd2) ? is_blue   :
                     (color == 4'd3) ? is_pink   :
                     (color == 4'd4) ? is_yellow :
                     (color == 4'd5) ? is_cyan   :
                     (color == 4'd6) ? is_orange :
                     (color == 4'd7) ? is_purple :
                     (color == 4'd8) ? is_black  : is_white;

    // ---- 3 抽头滤波：连续 3 个像素都命中才算有效 ----
    // 目的：去掉孤立噪点（1~2 像素宽的亮点），否则包围盒会被噪点撑到满屏
    reg t_d1, t_d2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            t_d1 <= 1'b0;
            t_d2 <= 1'b0;
        end
        else if (de) begin
            t_d1 <= is_target;
            t_d2 <= t_d1;
        end
    end
    wire is_target_f = is_target & t_d1 & t_d2;

    // ---------------- 帧起始：只用 VS 上升沿（VS 高电平持续数行） ----------------
    reg vs_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) vs_d <= 1'b0;
        else        vs_d <= frame;
    end
    wire fstart = frame & ~vs_d;

    // ---------------- 包围盒统计（带命中数门限） ----------------
    // 一帧内命中像素数 >= MIN_PIX 才认为真的存在目标，
    // 避免孤立噪点把包围盒撑到满屏、框乱飘。
    localparam [19:0] MIN_PIX = 20'd600;

    reg [9:0]  bx0, bx1, by0, by1;     // 本帧包围盒
    reg [9:0]  sx0, sx1, sy0, sy1;     // 上一帧结果（用于画框）
    reg [19:0] cnt;                    // 本帧命中像素数
    reg        svalid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bx0 <= 10'd1023; bx1 <= 10'd0; by0 <= 10'd1023; by1 <= 10'd0;
            sx0 <= 10'd1023; sx1 <= 10'd0; sy0 <= 10'd1023; sy1 <= 10'd0;
            cnt <= 20'd0; svalid <= 1'b0;
        end
        else if (fstart) begin
            if (cnt >= MIN_PIX) begin
                sx0 <= bx0; sx1 <= bx1; sy0 <= by0; sy1 <= by1;
                svalid <= 1'b1;
            end
            else begin
                svalid <= 1'b0;
            end
            bx0 <= 10'd1023; bx1 <= 10'd0; by0 <= 10'd1023; by1 <= 10'd0;
            cnt <= 20'd0;
        end
        else if (de && is_target_f &&
                 (x >= 10'd120) && (x <= 10'd680) &&
                 (y >= 10'd40)  && (y <= 10'd440)) begin
            if (cnt != 20'hFFFFF) cnt <= cnt + 20'd1;
            if (x < bx0) bx0 <= x;
            if (x > bx1) bx1 <= x;
            if (y < by0) by0 <= y;
            if (y > by1) by1 <= y;
        end
    end

    // ---------------- 画框（2 像素宽，黄色） ----------------
    // 包围盒大到接近满屏时，说明命中的是背景而不是目标 → 不画框
    wire [9:0] box_w = sx1 - sx0;
    wire [9:0] box_h = sy1 - sy0;
    wire too_big = (box_w > 10'd716) || (box_h > 10'd456);

    wire in_box  = svalid && !too_big &&
                   (x >= sx0) && (x <= sx1) && (y >= sy0) && (y <= sy1);
    wire near_lr = (x - sx0 < 10'd2) || (sx1 - x < 10'd2);
    wire near_tb = (y - sy0 < 10'd2) || (sy1 - y < 10'd2);
    wire on_edge = in_box && (near_lr || near_tb);

    assign dout = sel ? (on_edge ? 16'hFFE0 : din)      // 黄色跟踪框
                      : (is_target_f ? 16'hFFFF : 16'h0000);

endmodule
