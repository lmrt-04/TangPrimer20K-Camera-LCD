`timescale 1ns / 1ps

//==============================================================================
// img_text.v  --  OSD 标签：左上角显示「档位 + 中文功能名 + 追踪颜色色块」
//
//   布局（y = 20..35）：
//     x 20..35   档位字符（8x8 点阵放大 2 倍，10/11/12/13/14 显示 A/B/C/D/E）
//     x 40..55   第 1 个汉字（16x16）
//     x 56..71   第 2 个汉字（16x16）
//     x 78..98   当前追踪颜色的小色块
//
//   汉字来自 font_cn 字模 ROM（黑体 16x16，自动生成）
//==============================================================================

module img_text (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame,     // 帧起始（高有效）
    input  wire        de,        // 像素有效
    input  wire [15:0] din,       // RGB565 输入
    input  wire [3:0]  num,       // 档位 0..15
    input  wire [3:0]  color,     // 追踪颜色 0..9
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

    wire in_label  = (x >= 10'd20) && (x < 10'd72) &&
                     (y >= 10'd20) && (y < 10'd36);
    wire in_digit  = (x >= 10'd20) && (x < 10'd36);
    wire in_cn0    = (x >= 10'd40) && (x < 10'd56);
    wire in_cn1    = (x >= 10'd56) && (x < 10'd72);
    wire in_swatch = (x >= 10'd78) && (x < 10'd100) &&
                     (y >= 10'd22) && (y < 10'd36);

    wire [3:0] px = x - 10'd20;
    wire [3:0] py = y - 10'd20;

    // ---------------- 档位字符（8x8 放大 2 倍） ----------------
    wire [2:0] col = px[3:1];
    wire [2:0] row = py[3:1];

    reg [63:0] glyph;
    always @(*) begin
        case (num)
            4'd0:  glyph = 64'h3C66_6E76_6666_3C00;
            4'd1:  glyph = 64'h1838_1818_1818_7E00;
            4'd2:  glyph = 64'h3C66_060C_1830_7E00;
            4'd3:  glyph = 64'h3C66_061C_0666_3C00;
            4'd4:  glyph = 64'h0C1C_3C6C_7E0C_0C00;
            4'd5:  glyph = 64'h7E60_7C06_0666_3C00;
            4'd6:  glyph = 64'h1C30_607C_6666_3C00;
            4'd7:  glyph = 64'h7E06_0C18_3030_3000;
            4'd8:  glyph = 64'h3C66_663C_6666_3C00;
            4'd9:  glyph = 64'h3C66_663E_060C_3800;
            4'd10: glyph = 64'h183C_6666_7E66_6600;   // A
            4'd11: glyph = 64'h7C66_667C_6666_7C00;   // B
            4'd12: glyph = 64'h3C66_6060_6066_3C00;   // C
            4'd13: glyph = 64'h7C66_6666_6666_7C00;   // D
            4'd14: glyph = 64'h7E60_607C_6060_7E00;   // E
            default: glyph = 64'h0000_0000_0000_0000;
        endcase
    end

    reg [7:0] row_bits;
    always @(*) begin
        case (row)
            3'd0: row_bits = glyph[63:56];
            3'd1: row_bits = glyph[55:48];
            3'd2: row_bits = glyph[47:40];
            3'd3: row_bits = glyph[39:32];
            3'd4: row_bits = glyph[31:24];
            3'd5: row_bits = glyph[23:16];
            3'd6: row_bits = glyph[15:8];
            default: row_bits = glyph[7:0];
        endcase
    end

    wire lit_digit = row_bits[3'd7 - col];

    // ---------------- 汉字（16x16） ----------------
    reg [7:0] ch0, ch1;
    always @(*) begin
        case (num)
            4'd0:  begin ch0 = 8'd0;  ch1 = 8'd1;  end   // 原始
            4'd1:  begin ch0 = 8'd2;  ch1 = 8'd3;  end   // 灰度
            4'd2:  begin ch0 = 8'd4;  ch1 = 8'd5;  end   // 反色
            4'd3:  begin ch0 = 8'd6;  ch1 = 8'd7;  end   // 二值
            4'd4:  begin ch0 = 8'd8;  ch1 = 8'd9;  end   // 红显
            4'd5:  begin ch0 = 8'd10; ch1 = 8'd5;  end   // 换色
            4'd6:  begin ch0 = 8'd11; ch1 = 8'd12; end   // 提亮
            4'd7:  begin ch0 = 8'd13; ch1 = 8'd14; end   // 伪彩
            4'd8:  begin ch0 = 8'd15; ch1 = 8'd16; end   // 边缘
            4'd9:  begin ch0 = 8'd17; ch1 = 8'd18; end   // 十字
            4'd10: begin ch0 = 8'd19; ch1 = 8'd20; end   // 模糊
            4'd11: begin ch0 = 8'd21; ch1 = 8'd7;  end   // 阈值
            4'd12: begin ch0 = 8'd22; ch1 = 8'd23; end   // 跟踪
            4'd13: begin ch0 = 8'd24; ch1 = 8'd25; end   // 锐化
            4'd14: begin ch0 = 8'd26; ch1 = 8'd7;  end   // 中值
            default: begin ch0 = 8'd0; ch1 = 8'd0; end
        endcase
    end

    wire [3:0] cn_col0 = x - 10'd40;
    wire [3:0] cn_col1 = x - 10'd56;

    wire [15:0] cn_bits0, cn_bits1;

    font_cn u_font0 (
        .ch   (ch0),
        .row  (py),
        .bits (cn_bits0)
    );

    font_cn u_font1 (
        .ch   (ch1),
        .row  (py),
        .bits (cn_bits1)
    );

    wire lit_cn0 = cn_bits0[4'd15 - cn_col0];
    wire lit_cn1 = cn_bits1[4'd15 - cn_col1];

    wire pixel_on = (in_digit && lit_digit) ||
                    (in_cn0   && lit_cn0)   ||
                    (in_cn1   && lit_cn1);

    // ---------------- 追踪颜色色块 ----------------
    wire [15:0] swatch = (color == 4'd0) ? 16'hF800 :   // 红
                         (color == 4'd1) ? 16'h07E0 :   // 绿
                         (color == 4'd2) ? 16'h001F :   // 蓝
                         (color == 4'd3) ? 16'hF81F :   // 品红/粉
                         (color == 4'd4) ? 16'hFFE0 :   // 黄
                         (color == 4'd5) ? 16'h07FF :   // 青
                         (color == 4'd6) ? 16'hFD20 :   // 橙
                         (color == 4'd7) ? 16'h8010 :   // 紫
                         (color == 4'd8) ? 16'h0000 :   // 黑
                                           16'hFFFF;    // 白

    assign dout = in_label  ? (pixel_on ? 16'hFFFF : 16'h0000) :
                  in_swatch ? swatch : din;

endmodule
