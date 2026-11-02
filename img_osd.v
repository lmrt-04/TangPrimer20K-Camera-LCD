`timescale 1ns / 1ps

//==============================================================================
// img_osd.v  --  在画面上叠加图形（十字线 + 边框）
//
//   纯组合逻辑，只用两个坐标计数器，不占任何存储
//   中心十字：(400, 240)；四周 2 像素绿色边框
//   叠加用绿色 16'h07E0，其余像素原样输出
//==============================================================================

module img_osd (
    input  wire        clk,       // video_clk
    input  wire        rst_n,
    input  wire        frame,     // 帧起始（高有效）
    input  wire        de,        // 像素有效
    input  wire [15:0] din,       // RGB565
    output wire [15:0] dout       // 叠加后的 RGB565
);

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

    wire cross_v = (x == 10'd400);                       // 竖线
    wire cross_h = (y == 10'd240);                       // 横线
    wire border  = (x < 10'd2) || (x > 10'd797) || (y < 10'd2);   // 边框

    wire on = cross_v || cross_h || border;

    assign dout = on ? 16'h07E0 : din;                   // 绿色

endmodule
