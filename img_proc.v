`timescale 1ns / 1ps

//==============================================================================
// img_proc.v  --  RGB565 像素处理（纯组合逻辑，无存储）
//
//   mode = 0 原始         1 灰度        2 反色        3 二值化
//   mode = 4 只留红色     5 红蓝互换    6 提亮 1.5x   7 伪彩色（热力图）
//
// 接在帧缓冲输出与 LCD 之间：din/dout 都是 RGB565
//==============================================================================

module img_proc (
    input  wire [2:0]  mode,
    input  wire [15:0] din,
    output reg  [15:0] dout
);

    wire [4:0] r = din[15:11];
    wire [5:0] g = din[10:5];
    wire [4:0] b = din[4:0];

    wire [7:0] r8 = {r, 3'b000};
    wire [7:0] g8 = {g, 2'b00};
    wire [7:0] b8 = {b, 3'b000};

    // 亮度 Y = 0.299R + 0.587G + 0.114B
    wire [15:0] ysum = r8 * 8'd77 + g8 * 8'd150 + b8 * 8'd29;
    wire [7:0]  y8   = ysum[15:8];

    wire [15:0] gray    = {y8[7:3], y8[7:2], y8[7:3]};
    wire [15:0] inv     = ~din;
    wire [15:0] binary  = (y8 > 8'd128) ? 16'hFFFF : 16'h0000;
    wire [15:0] redonly = {r, 6'd0, 5'd0};
    wire [15:0] swaprb  = {b, g, r};

    // 提亮 1.5 倍，带饱和
    wire [5:0] r15 = {1'b0, r} + {2'b00, r[4:1]};
    wire [6:0] g15 = {1'b0, g} + {2'b00, g[5:1]};
    wire [5:0] b15 = {1'b0, b} + {2'b00, b[4:1]};
    wire [15:0] bright = { (r15 > 6'd31) ? 5'd31 : r15[4:0],
                           (g15 > 6'd63) ? 6'd63 : g15[5:0],
                           (b15 > 6'd31) ? 5'd31 : b15[4:0] };

    // 伪彩色：黑→蓝→青→绿→黄→红
    wire [1:0] seg  = y8[7:6];
    wire [4:0] half = y8[5:1];
    wire [4:0] fc_r = (seg == 2'd2) ? half :
                      (seg == 2'd3) ? 5'd31 : 5'd0;
    wire [5:0] fc_g = (seg == 2'd0) ? {1'b0, half} :
                      (seg == 2'd3) ? (6'd31 - {1'b0, half}) : 6'd31;
    wire [4:0] fc_b = (seg == 2'd0) ? 5'd31 :
                      (seg == 2'd1) ? (5'd31 - half) : 5'd0;
    wire [15:0] falsecolor = {fc_r, fc_g, fc_b};

    always @(*) begin
        case (mode)
            3'd1:    dout = gray;
            3'd2:    dout = inv;
            3'd3:    dout = binary;
            3'd4:    dout = redonly;
            3'd5:    dout = swaprb;
            3'd6:    dout = bright;
            3'd7:    dout = falsecolor;
            default: dout = din;
        endcase
    end

endmodule
