`timescale 1ns / 1ps

//==============================================================================
// img_filter.v  --  2x3 邻域滤波（三种算子，运行时切换）
//
//   sel = 0 : 均值模糊   avg = (u0+u1+u2+c0+c1+c2) * 42 / 256
//   sel = 1 : 锐化       sharp = 2*c1 - avg      （反锐化掩膜，带上下限）
//   sel = 2 : 中值滤波   med3(c2, c1, c0)        （去孤立噪点）
//
//   只用 1 个 800x8 行缓存（读无条件、写用 de 控制，便于推断 BSRAM）
//==============================================================================

module img_filter (
    input  wire        clk,       // video_clk
    input  wire        rst_n,
    input  wire        frame,     // 帧起始（高有效）
    input  wire        de,        // 像素有效
    input  wire [15:0] din,       // RGB565
    input  wire [1:0]  sel,       // 0 均值 / 1 锐化 / 2 中值
    output wire [15:0] dout
);

    reg [9:0] x;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      x <= 10'd0;
        else if (frame)  x <= 10'd0;
        else if (de)     x <= (x == 10'd799) ? 10'd0 : x + 10'd1;
    end

    // RGB565 -> 亮度
    wire [7:0] r8 = {din[15:11], 3'b000};
    wire [7:0] g8 = {din[10:5],  2'b00};
    wire [7:0] b8 = {din[4:0],   3'b000};
    wire [15:0] ysum = r8 * 8'd77 + g8 * 8'd150 + b8 * 8'd29;
    wire [7:0]  y8   = ysum[15:8];

    // 单行缓存
    reg [7:0] line0 [0:799];
    reg [7:0] u_q;

    always @(posedge clk) begin
        u_q <= line0[x];
        if (de) line0[x] <= y8;
    end

    // 2x3 窗口
    reg [7:0] c0, c1, c2;
    reg [7:0] u0, u1, u2;

    always @(posedge clk) begin
        if (de) begin
            c0 <= y8;   c1 <= c0;   c2 <= c1;
            u0 <= u_q;  u1 <= u0;   u2 <= u1;
        end
    end

    // ---- 均值 ----
    wire [10:0] sum = {3'b000, u0} + {3'b000, u1} + {3'b000, u2}
                    + {3'b000, c0} + {3'b000, c1} + {3'b000, c2};
    wire [17:0] prod = sum * 8'd42;      // 42/256 ≈ 1/6，最大 251 不溢出
    wire [7:0]  avg  = prod[15:8];

    // ---- 锐化：2*c1 - avg ----
    wire [9:0]  d_c1  = {1'b0, c1, 1'b0};              // 2*c1
    wire [9:0]  diff  = d_c1 - {2'b00, avg};
    wire [7:0]  sharp = diff[9]        ? 8'd0 :
                        (diff > 10'd255) ? 8'd255 : diff[7:0];

    // ---- 中值（3 点）----
    function [7:0] med3;
        input [7:0] a;
        input [7:0] b;
        input [7:0] c;
        reg   [7:0] mx;
        reg   [7:0] mn;
        begin
            mx  = (a > b) ? a : b;
            mn  = (a > b) ? b : a;
            med3 = (c > mx) ? mx : ((c < mn) ? mn : c);
        end
    endfunction

    wire [7:0] med = med3(c2, c1, c0);

    // ---- 输出选择 ----
    reg [7:0] v;
    always @(*) begin
        case (sel)
            2'd1:    v = sharp;
            2'd2:    v = med;
            default: v = avg;
        endcase
    end

    assign dout = {v[7:3], v[7:2], v[7:3]};

endmodule
