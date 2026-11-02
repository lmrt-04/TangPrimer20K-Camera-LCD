`timescale 1ns / 1ps

//==============================================================================
// img_sobel.v  --  边缘检测（2x3 邻域，单行缓存）
//
//   输入：RGB565 像素流 + de（像素有效）+ frame（帧起始）
//   输出：边缘强度（白线黑底）
//
//   只用 1 个 800x8 行缓存（保存上一行），资源比 3x3 版本少一半：
//     Gx = (u0 + c0) - (u2 + c2)          列间差异 → 垂直边缘
//     Gy = (u0 + u1 + u2) - (c0 + c1 + c2) 行间差异 → 水平边缘
//     强度 = |Gx| + |Gy|
//==============================================================================

module img_sobel (
    input  wire        clk,       // video_clk
    input  wire        rst_n,
    input  wire        frame,     // 帧起始（高有效）
    input  wire        de,        // 像素有效
    input  wire [15:0] din,       // RGB565
    output wire [15:0] dout       // RGB565 边缘图
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

    // 单行缓存：读无条件（便于推断 BSRAM），写只用 de 控制
    reg [7:0] line0 [0:799];
    reg [7:0] u_q;

    always @(posedge clk) begin
        u_q <= line0[x];
        if (de) line0[x] <= y8;
    end

    // 2x3 窗口寄存器
    reg [7:0] c0, c1, c2;
    reg [7:0] u0, u1, u2;

    always @(posedge clk) begin
        if (de) begin
            c0 <= y8;   c1 <= c0;   c2 <= c1;
            u0 <= u_q;  u1 <= u0;   u2 <= u1;
        end
    end

    // 梯度
    wire [8:0] su0 = {1'b0, u0} + {1'b0, c0};
    wire [8:0] su2 = {1'b0, u2} + {1'b0, c2};
    wire [8:0] gx  = (su0 > su2) ? (su0 - su2) : (su2 - su0);

    wire [9:0] ru  = {2'b00, u0} + {2'b00, u1} + {2'b00, u2};
    wire [9:0] rc  = {2'b00, c0} + {2'b00, c1} + {2'b00, c2};
    wire [9:0] gy  = (ru > rc) ? (ru - rc) : (rc - ru);

    wire [10:0] mag = {2'b00, gx} + {1'b0, gy};
    wire [7:0]  m8  = (mag > 11'd255) ? 8'd255 : mag[7:0];

    assign dout = {m8[7:3], m8[7:2], m8[7:3]};

endmodule
