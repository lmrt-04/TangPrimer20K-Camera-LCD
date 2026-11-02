module top(
	input                       clk,
	input                       key_n,    // T2 用户按键，切换图像处理模式
	input                       key2_n,   // T3 用户按键，切换追踪颜色
	input                       rst_n,
	inout                       cmos_scl,          //cmos i2c clock
	inout                       cmos_sda,          //cmos i2c data
	input                       cmos_vsync,        //cmos vsync
	input                       cmos_href,         //cmos hsync refrence,data valid
	input                       cmos_pclk,         //cmos pxiel clock
    output                      cmos_xclk,         //cmos externl clock 
	input   [7:0]               cmos_db,           //cmos data
	output                      cmos_rst_n,        //cmos reset 
	output                      cmos_pwdn,         //cmos power down
	
	output [3:0] 				state_led,

	output [14-1:0]             ddr_addr,       //ROW_WIDTH=14
	output [3-1:0]              ddr_bank,       //BANK_WIDTH=3
	output                      ddr_cs,
	output                      ddr_ras,
	output                      ddr_cas,
	output                      ddr_we,
	output                      ddr_ck,
	output                      ddr_ck_n,
	output                      ddr_cke,
	output                      ddr_odt,
	output                      ddr_reset_n,
	output [2-1:0]              ddr_dm,         //DM_WIDTH=2
	inout [16-1:0]              ddr_dq,         //DQ_WIDTH=16
	inout [2-1:0]               ddr_dqs,        //DQS_WIDTH=2
	inout [2-1:0]               ddr_dqs_n,      //DQS_WIDTH=2

	output                      lcd_dclk,	
	output                      lcd_hs,            //lcd horizontal synchronization
	output                      lcd_vs,            //lcd vertical synchronization        
	output                      lcd_de,            //lcd data enable     
	output[4:0]                 lcd_r,             //lcd red
	output[5:0]                 lcd_g,             //lcd green
	output[4:0]                 lcd_b	           //lcd blue
);

//memory interface
wire                   memory_clk         ;
wire                   dma_clk         	  ;
wire                   pll_lock           ;
wire                   cmd_ready          ;
wire[2:0]              cmd                ;
wire                   cmd_en             ;
wire[5:0]              app_burst_number   ;
wire[ADDR_WIDTH-1:0]   addr               ;
wire                   wr_data_rdy        ;
wire                   wr_data_en         ;//
wire                   wr_data_end        ;//
wire[DATA_WIDTH-1:0]   wr_data            ;   
wire[DATA_WIDTH/8-1:0] wr_data_mask       ;   
wire                   rd_data_valid      ;  
wire                   rd_data_end        ;//unused 
wire[DATA_WIDTH-1:0]   rd_data            ;   
wire                   init_calib_complete;

//According to IP parameters to choose
`define	    WR_VIDEO_WIDTH_16
`define	DEF_WR_VIDEO_WIDTH 16

`define	    RD_VIDEO_WIDTH_16
`define	DEF_RD_VIDEO_WIDTH 16

`define	USE_THREE_FRAME_BUFFER

`define	DEF_ADDR_WIDTH 28 
`define	DEF_SRAM_DATA_WIDTH 128
//
//=========================================================
//SRAM parameters
parameter ADDR_WIDTH          = `DEF_ADDR_WIDTH;    //瀛樺偍鍗曞厓鏄痓yte锛屾�诲閲?2^27*16bit = 2Gbit,澧炲姞1浣峳ank鍦板潃锛寋rank[0],bank[2:0],row[13:0],cloumn[9:0]}
parameter DATA_WIDTH          = `DEF_SRAM_DATA_WIDTH;   //涓庣敓鎴怐DR3IP鏈夊叧锛屾ddr3 2Gbit, x16锛?鏃堕挓姣斾緥1:4 锛屽垯鍥哄畾128bit
parameter WR_VIDEO_WIDTH      = `DEF_WR_VIDEO_WIDTH;  
parameter RD_VIDEO_WIDTH      = `DEF_RD_VIDEO_WIDTH;  

wire                            video_clk;         //video pixel clock
//-------------------
//syn_code
wire                      syn_off0_re;  // ofifo read enable signal
wire                      syn_off0_vs;
wire                      syn_off0_hs;
                          
wire                      off0_syn_de  ;
wire [RD_VIDEO_WIDTH-1:0] off0_syn_data;

wire[15:0]                      cmos_16bit_data;
wire                            cmos_16bit_clk;
wire[15:0] 						write_data;

wire[9:0]                       lut_index;
wire[31:0]                      lut_data;

assign cmos_xclk = cmos_clk;
assign cmos_pwdn = 1'b0;
assign cmos_rst_n = 1'b1;
assign write_data = {cmos_16bit_data[4:0],cmos_16bit_data[10:5],cmos_16bit_data[15:11]};

//鐘舵�佹寚绀虹伅
// assign state_led[3] = 
// assign state_led[2] = 
assign state_led[1] = rst_n; //澶嶄綅鎸囩ず鐏?assign state_led[0] = init_calib_complete; //DDR3鍒濆鍖栨寚绀虹伅

//generate the CMOS sensor clock and the SDRAM controller clock
sys_pll sys_pll_m0(
	.clkin                     (cmos_clk                  ),
	.clkout                    (video_clk 	              )
	);
cmos_pll cmos_pll_m0(
	.clkin                     (clk                      		),
	.clkout                    (cmos_clk 	              		)
	);

mem_pll mem_pll_m0(
	.clkin                     (cmos_clk                        ),
	.clkout                    (memory_clk 	              		),
	.lock 					   (pll_lock 						)
	);

//I2C master controller
	// power-on delay before camera config (~620ms)
	reg [23:0] cam_por = 24'd0;
	always @(posedge clk or negedge rst_n)
		if (!rst_n)            cam_por <= 24'd0;
		else if (!cam_por[23]) cam_por <= cam_por + 24'd1;
	wire cam_cfg_en = cam_por[23];

		// I2C ? 5 ??????(??????),??? 3 ??????
	reg [27:0] cfg_stop;
	always @(posedge clk or negedge rst_n)
		if (!rst_n) cfg_stop <= 28'd0;
		else if (cfg_stop != 28'hFFFFFFF) cfg_stop <= cfg_stop + 28'd1;
	wire i2c_rst = ~rst_n | cfg_stop[27];

	i2c_config i2c_config_m0(
	.rst                        (i2c_rst                 ),
	.clk                        (clk                      ),
	.clk_div_cnt                (16'd500                  ),
	.i2c_addr_2byte             (1'b1                     ),
	.lut_index                  (lut_index                ),
	.lut_dev_addr               (lut_data[31:24]          ),
	.lut_reg_addr               (lut_data[23:8]           ),
	.lut_reg_data               (lut_data[7:0]            ),
	.error                      (                         ),
	.done                       (                         ),
	.i2c_scl                    (cmos_scl                 ),
	.i2c_sda                    (cmos_sda                 )
);
//configure look-up table
lut_ov5640_rgb565_800_480 lut_ov5640_rgb565_800_480_m0(
	.lut_index                  (lut_index                ),
	.lut_data                   (lut_data                 )
);
//CMOS sensor 8bit data is converted to 16bit data
cmos_8_16bit cmos_8_16bit_m0(
	.rst                        (~rst_n                   ),
	.pclk                       (cmos_pclk                ),
	.pdata_i                    (cmos_db                  ),
	.de_i                       (cmos_href                ),
	.pdata_o                    (cmos_16bit_data          ),
	.hblank                     (cmos_16bit_wr            ),
	.de_o                       (cmos_16bit_clk           )
);

//The video output timing generator and generate a frame read data request
wire out_de;
syn_gen syn_gen_inst
(                                   
    .I_pxl_clk   (video_clk       ),//40MHz      //65MHz      //74.25MHz    //148.5
    .I_rst_n     (rst_n           ),//800x600    //1024x768   //1280x720    //1920x1080    
    .I_h_total   (16'd1056        ),// 16'd1056  // 16'd1344  // 16'd1650   // 16'd2200  
    .I_h_sync    (16'd128          ),// 16'd128   // 16'd136   // 16'd40     // 16'd44   
    .I_h_bporch  (16'd88          ),// 16'd88    // 16'd160   // 16'd220    // 16'd148   
    .I_h_res     (16'd800         ),// 16'd800   // 16'd1024  // 16'd1280   // 16'd1920  
    .I_v_total   (16'd628         ),// 16'd628   // 16'd806   // 16'd750    // 16'd1125   
    .I_v_sync    (16'd4           ),// 16'd4     // 16'd6     // 16'd5      // 16'd5      
    .I_v_bporch  (16'd23          ),// 16'd23    // 16'd29    // 16'd20     // 16'd36      
    .I_v_res     (16'd600         ),// 16'd600   // 16'd768   // 16'd720    // 16'd1080   
    .I_rd_hres   (16'd800         ),
    .I_rd_vres   (16'd600         ),
    .I_hs_pol    (1'b1            ),
    .I_vs_pol    (1'b1            ),
    .O_rden      (syn_off0_re     ),
    .O_de        (out_de          ),   
    .O_hs        (syn_off0_hs     ),
    .O_vs        (syn_off0_vs     )
);

/*//娴嬭瘯鍥?//--------------------------
wire        tp0_vs_in  ;
wire        tp0_hs_in  ;
wire        tp0_de_in ;
wire [ 7:0] tp0_data_r;
wire [ 7:0] tp0_data_g;
wire [ 7:0] tp0_data_b;
testpattern testpattern_inst
(
    .I_pxl_clk   (video_clk              ),//pixel clock
    .I_rst_n     (rst_n             ),//low active 
    .I_mode      (3'b000 ),//data select
    .I_single_r  (8'd255               ),
    .I_single_g  (8'd255             ),
    .I_single_b  (8'd255               ),                  //800x600    //1024x768   //1280x720   //1920x1080 
    .I_h_total   (16'd1056        ),//hor total time  // 12'd1056  // 12'd1344  // 12'd1650  // 12'd2200
    .I_h_sync    (16'd128         ),//hor sync time   // 12'd128   // 12'd136   // 12'd40    // 12'd44  
    .I_h_bporch  (16'd88          ),//hor back porch  // 12'd88    // 12'd160   // 12'd220   // 12'd148 
    .I_h_res     (16'd800         ),//hor resolution  // 12'd800   // 12'd1024  // 12'd1280  // 12'd1920
    .I_v_total   (16'd628         ),//ver total time  // 12'd628   // 12'd806   // 12'd750   // 12'd1125 
    .I_v_sync    (16'd4           ),//ver sync time   // 12'd4     // 12'd6     // 12'd5     // 12'd5   
    .I_v_bporch  (16'd23          ),//ver back porch  // 12'd23    // 12'd29    // 12'd20    // 12'd36  
    .I_v_res     (16'd600         ),//ver resolution  // 12'd600   // 12'd768   // 12'd720   // 12'd1080 
    .I_hs_pol    (1'b1               ),//0,璐熸瀬鎬?1,姝ｆ瀬鎬?    .I_vs_pol    (1'b1               ),//0,璐熸瀬鎬?1,姝ｆ瀬鎬?    .O_de        (tp0_de_in          ),   
    .O_hs        (tp0_hs_in          ),
    .O_vs        (tp0_vs_in          ),
    .O_data_r    (tp0_data_r         ),   
    .O_data_g    (tp0_data_g         ),
    .O_data_b    (tp0_data_b         )
);*/

Video_Frame_Buffer_Top Video_Frame_Buffer_Top_inst
( 
    .I_rst_n              (init_calib_complete ),//rst_n            ),
    .I_dma_clk            (dma_clk          ),   //sram_clk         ),
`ifdef USE_THREE_FRAME_BUFFER 
    .I_wr_halt            (1'd0             ), //1:halt,  0:no halt
    .I_rd_halt            (1'd0             ), //1:halt,  0:no halt
`endif
    // video data input             
    .I_vin0_clk           (cmos_16bit_clk   ),
    .I_vin0_vs_n          (~cmos_vsync      ),
        .I_vin0_de            (cmos_16bit_wr    ),
	.I_vin0_data          (write_data       ),   // BGR→RGB 修正后的数据
    .O_vin0_fifo_full     (                 ),
    // video data output            
    .I_vout0_clk          (video_clk        ),
    .I_vout0_vs_n         (~syn_off0_vs     ),
        .I_vout0_de           (syn_off0_re      ),
    .O_vout0_den          (off0_syn_de      ),
    .O_vout0_data         (off0_syn_data    ),
    .O_vout0_fifo_empty   (                 ),
    // ddr write request
    .I_cmd_ready          (cmd_ready          ),
    .O_cmd                (cmd                ),//0:write;  1:read
    .O_cmd_en             (cmd_en             ),
    .O_app_burst_number   (app_burst_number   ),
    .O_addr               (addr               ),//[ADDR_WIDTH-1:0]
    .I_wr_data_rdy        (wr_data_rdy        ),
    .O_wr_data_en         (wr_data_en         ),//
    .O_wr_data_end        (wr_data_end        ),//
    .O_wr_data            (wr_data            ),//[DATA_WIDTH-1:0]
    .O_wr_data_mask       (wr_data_mask       ),
    .I_rd_data_valid      (rd_data_valid      ),
    .I_rd_data_end        (rd_data_end        ),//unused 
    .I_rd_data            (rd_data            ),//[DATA_WIDTH-1:0]
    .I_init_calib_complete(init_calib_complete)
); 


localparam N = 7; //delay N clocks
                          
reg  [N-1:0]  Pout_hs_dn   ;
reg  [N-1:0]  Pout_vs_dn   ;
reg  [N-1:0]  Pout_de_dn   ;

always@(posedge video_clk or negedge rst_n)
begin
    if(!rst_n)
        begin                          
            Pout_hs_dn  <= {N{1'b1}};
            Pout_vs_dn  <= {N{1'b1}}; 
            Pout_de_dn  <= {N{1'b0}}; 
        end
    else 
        begin                          
            Pout_hs_dn  <= {Pout_hs_dn[N-2:0],syn_off0_hs};
            Pout_vs_dn  <= {Pout_vs_dn[N-2:0],syn_off0_vs}; 
            Pout_de_dn  <= {Pout_de_dn[N-2:0],out_de}; 
        end
end

//---------------------------------------------
`ifdef RD_VIDEO_WIDTH_16     
//==== 按键消抖 + 模式切换（0..4 循环）====
	reg [2:0]  key_s;
	reg        key_d;
	reg [19:0] db_div;
	reg [3:0]  mode_r;
	always @(posedge video_clk or negedge rst_n) begin
		if (!rst_n) begin
			key_s  <= 3'b111;
			key_d  <= 1'b1;
			db_div <= 20'd0;
			mode_r <= 3'd0;
		end
		else begin
			key_s <= {key_s[1:0], key_n};
			if (db_div == 20'd640_000) begin        // ~20ms @32MHz
				db_div <= 20'd0;
				key_d  <= key_s[2];
				if (key_d && !key_s[2])             // 下降沿 = 按下
					mode_r <= (mode_r == 4'd14) ? 4'd0 : mode_r + 4'd1;
			end
			else db_div <= db_div + 20'd1;
		end
	end

	// T3 按键：循环切换追踪颜色（8 色：红 绿 蓝 品红 黄 青 橙 紫）
	reg [2:0]  key2_s;
	reg        key2_d;
	reg [19:0] db2_div;
	reg [3:0]  color_r;

	always @(posedge video_clk or negedge rst_n) begin
		if (!rst_n) begin
			key2_s  <= 3'b111;
			key2_d  <= 1'b1;
			db2_div <= 20'd0;
			color_r <= 4'd0;
		end
		else begin
			key2_s <= {key2_s[1:0], key2_n};
			if (db2_div == 20'd640_000) begin
				db2_div <= 20'd0;
				key2_d  <= key2_s[2];
				if (key2_d && !key2_s[2])
					color_r <= (color_r == 4'd9) ? 4'd0 : color_r + 4'd1;
			end
			else db2_div <= db2_div + 20'd1;
		end
	end

	// 白平衡校正：画面白色偏红，先补 G、B 通道
	wire [15:0] wb_data;
	img_wb u_img_wb (
		.din  (off0_syn_data[15:0]),
		.dout (wb_data)
	);

	wire [15:0] proc_data;
	img_proc u_img_proc (
		.mode (mode_r[3] ? 3'd0 : mode_r[2:0]),   // 8 档及以上时 img_proc 直通
		.din  (wb_data),
		.dout (proc_data)
	);
	wire [15:0] edge_data;
	img_sobel u_img_sobel (
		.clk   (video_clk),
		.rst_n (rst_n),
		.frame (syn_off0_vs),
		.de    (off0_syn_de),
		.din   (wb_data),
		.dout  (edge_data)
	);

	wire [15:0] sel_data = (mode_r == 4'd8) ? edge_data : proc_data;
	wire [15:0] osd_data;
	img_osd u_img_osd (
		.clk   (video_clk),
		.rst_n (rst_n),
		.frame (syn_off0_vs),
		.de    (off0_syn_de),
		.din   (sel_data),
		.dout  (osd_data)
	);

	wire [15:0] flt_data;
	img_filter u_img_filter (
		.clk   (video_clk),
		.rst_n (rst_n),
		.frame (syn_off0_vs),
		.de    (off0_syn_de),
		.din   (sel_data),
		.sel   ((mode_r == 4'd13) ? 2'd1 : (mode_r == 4'd14) ? 2'd2 : 2'd0),
		.dout  (flt_data)
	);

	wire [15:0] trk_data;
	img_track u_img_track (
		.clk   (video_clk),
		.rst_n (rst_n),
		.frame (syn_off0_vs),
		.de    (off0_syn_de),
		.din   (sel_data),
		.sel   (mode_r == 4'd12),
		.color (color_r),
		.dout  (trk_data)
	);

	wire [15:0] sel_osd = (mode_r == 4'd9)  ? osd_data :
	                      (mode_r == 4'd10) ? flt_data :
	                      (mode_r == 4'd13) ? flt_data :
	                      (mode_r == 4'd14) ? flt_data :
	                      (mode_r == 4'd11) ? trk_data :
	                      (mode_r == 4'd12) ? trk_data : sel_data;
	wire [15:0] text_data;
	img_text u_img_text (
		.clk   (video_clk),
		.rst_n (rst_n),
		.frame (syn_off0_vs),
		.de    (off0_syn_de),
		.din   (sel_osd),
		.num   (mode_r[3:0]),
		.color (color_r),
		.dout  (text_data)
	);

	assign {lcd_r,lcd_g,lcd_b}    = off0_syn_de ? text_data : 16'h0000;//{r,g,b}
    assign lcd_vs      			  = Pout_vs_dn[4];//syn_off0_vs;
    assign lcd_hs      			  = Pout_hs_dn[4];//syn_off0_hs;
    assign lcd_de      			  = Pout_de_dn[4];//off0_syn_de;
    assign lcd_dclk    			  = video_clk;//video_clk_phs;
`endif

`ifdef RD_VIDEO_WIDTH_24 
    assign {lcd_r,lcd_g,lcd_b}    = off0_syn_de ? off0_syn_data[23:0] : 24'h0000;//{r,g,b}
    assign lcd_vs      			  = Pout_vs_dn[4];//syn_off0_vs;
    assign lcd_hs      			  = Pout_hs_dn[4];//syn_off0_hs;
    assign lcd_de      			  = Pout_de_dn[4];//off0_syn_de;
    assign lcd_dclk    			  = video_clk;//video_clk_phs;
`endif

`ifdef RD_VIDEO_WIDTH_32 
    assign {lcd_r,lcd_g,lcd_b}    = off0_syn_de ? off0_syn_data[23:0] : 24'h0000;//{r,g,b}
    assign lcd_vs      			  = Pout_vs_dn[4];//syn_off0_vs;
    assign lcd_hs      			  = Pout_hs_dn[4];//syn_off0_hs;
    assign lcd_de      			  = Pout_de_dn[4];//off0_syn_de;
    assign lcd_dclk    			  = video_clk;//video_clk_phs;
`endif

DDR3MI DDR3_Memory_Interface_Top_inst 
(
    .clk                (video_clk          ),
    .memory_clk         (memory_clk         ),
    .pll_lock           (pll_lock           ),
    .rst_n              (rst_n              ), //rst_n
    .app_burst_number   (app_burst_number   ),
    .cmd_ready          (cmd_ready          ),
    .cmd                (cmd                ),
    .cmd_en             (cmd_en             ),
    .addr               (addr               ),
    .wr_data_rdy        (wr_data_rdy        ),
    .wr_data            (wr_data            ),
    .wr_data_en         (wr_data_en         ),
    .wr_data_end        (wr_data_end        ),
    .wr_data_mask       (wr_data_mask       ),
    .rd_data            (rd_data            ),
    .rd_data_valid      (rd_data_valid      ),
    .rd_data_end        (rd_data_end        ),
    .sr_req             (1'b0               ),
    .ref_req            (1'b0               ),
    .sr_ack             (                   ),
    .ref_ack            (                   ),
    .init_calib_complete(init_calib_complete),
    .clk_out            (dma_clk            ),
    .burst              (1'b1               ),
    // mem interface
    .ddr_rst            (                 ),
    .O_ddr_addr         (ddr_addr         ),
    .O_ddr_ba           (ddr_bank         ),
    .O_ddr_cs_n         (ddr_cs         ),
    .O_ddr_ras_n        (ddr_ras        ),
    .O_ddr_cas_n        (ddr_cas        ),
    .O_ddr_we_n         (ddr_we         ),
    .O_ddr_clk          (ddr_ck          ),
    .O_ddr_clk_n        (ddr_ck_n        ),
    .O_ddr_cke          (ddr_cke          ),
    .O_ddr_odt          (ddr_odt          ),
    .O_ddr_reset_n      (ddr_reset_n      ),
    .O_ddr_dqm          (ddr_dm           ),
    .IO_ddr_dq          (ddr_dq           ),
    .IO_ddr_dqs         (ddr_dqs          ),
    .IO_ddr_dqs_n       (ddr_dqs_n        )
);

endmodule