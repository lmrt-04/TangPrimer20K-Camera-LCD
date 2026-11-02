# 基于 FPGA 的实时视觉感知与处理系统

Tang Primer 20K（GW2A-LV18PG256C8/I7）平台上的摄像头实时显示与图像处理工程。
OV5640 采集 → DDR3 三帧缓冲（跨时钟域）→ 实时图像处理流水线 → 800×480 RGB 屏显示。

![系统实物](docs/images/system.jpg)

工程文件：**`Camera_LCD.gprj`**（IDE 直接打开它）
已编译位流：**`bitstream/Camera_LCD.fs`**

## 功能特性

**15 档实时图像处理**，按 T2 键循环切换：

| 档位 | 显示 | 功能 | 模块 |
| --- | --- | --- | --- |
| 0 | 0 原始 | 直通 | — |
| 1 | 1 灰度 | 亮度 | img_proc |
| 2 | 2 反色 | 底片 | img_proc |
| 3 | 3 二值 | 阈值 128 | img_proc |
| 4 | 4 红显 | 只留红 | img_proc |
| 5 | 5 换色 | 红蓝互换 | img_proc |
| 6 | 6 提亮 | 1.5 倍 | img_proc |
| 7 | 7 伪彩 | 热力图 | img_proc |
| 8 | 8 边缘 | 边缘检测 | img_sobel |
| 9 | 9 十字 | 十字+边框 | img_osd |
| 10 | A 模糊 | 均值滤波 | img_filter(0) |
| 11 | B 阈值 | 颜色分割 | img_track(0) |
| 12 | C 跟踪 | 目标画框 | img_track(1) |
| 13 | D 锐化 | 反锐化 | img_filter(1) |
| 14 | E 中值 | 中值滤波 | img_filter(2) |

![15 档效果](docs/images/modes.jpg)

**10 种颜色目标跟踪**，按 T3 键循环切换：红 / 绿 / 蓝 / 粉 / 黄 / 青 / 橙 / 紫 / 黑 / 白

![目标跟踪](docs/images/tracking.jpg)

**屏上中文 OSD**：左上角实时显示「档位字符 + 中文功能名 + 追踪颜色色块」（16×16 汉字字模，27 字）。

全部逻辑用纯 Verilog 实现，无 CPU 参与，逐拍流水线处理。

## 硬件平台

| 部件 | 型号 / 规格 |
| --- | --- |
| FPGA | GW2A-LV18PG256C8/I7（Tang Primer 20K Dock） |
| 摄像头 | OV5640，DVP 24P，RGB565 输出 |
| 显示屏 | 800×480 RGB 接口，40P FPC，RGB565 |
| 内存 | 板载 128M DDR3（三帧缓冲） |
| 晶振 | 27 MHz |

![接口标注](docs/images/board.jpg)

## 数据通路

```
       27 MHz ──cmos_pll──> 24 MHz ──> OV5640 XCLK
                        ──sys_pll──> 32 MHz  ──> LCD 像素时钟 / 视频域
                        ──mem_pll──> 400 MHz ──> DDR3

  OV5640 ─8bit─> cmos_8_16bit ─16bit─> write_data(BGR→RGB) ─> 帧缓冲写侧
                                                                 │
                                       Video_Frame_Buffer_Top（DDR3，三帧缓冲）
                                                                 │
   读侧(32MHz) ─> img_wb ─> img_proc / img_sobel / img_filter ┐
                 └─> img_track / img_osd ────────────────────┼─> 多路选择 ─> img_text ─> LCD
```

摄像头和屏幕是两个独立的时钟域，中间必须靠帧缓冲解耦，否则画面撕裂/滚动。

## 文件

| 文件 | 说明 |
| --- | --- |
| `src/top.v` | 顶层：时钟、I2C 配置、按键、处理流水线、输出拼接 |
| `src/img_wb.v` | 白平衡校正（默认直通，可改增益） |
| `src/img_proc.v` | 8 种像素变换 |
| `src/img_sobel.v` | 边缘检测（2×3 邻域，单行缓存） |
| `src/img_filter.v` | 均值 / 锐化 / 中值 |
| `src/img_track.v` | 10 色阈值 + 包围盒跟踪（含四重防误判） |
| `src/img_osd.v` | 十字线与边框 |
| `src/img_text.v` | 中文标签 + 追踪颜色色块 |
| `src/font_cn.v` | 16×16 汉字字模 ROM（27 字） |
| `src/syn_gen.v` | 显示时序发生器（800×600，官方原版） |
| `src/cmos_8_16bit.v` | 摄像头 8bit 数据拼成 16bit 像素 |
| `src/lut_ov5640_rgb565_800_480.v` | OV5640 的 256 条寄存器配置表 |
| `src/i2c_master/*.v` | I2C(SCCB) 主机 |
| `src/gowin_rpll/*.v` | 三个 PLL（24 / 32 / 400 MHz） |
| `src/ddr3_memory_interface/DDR3MI.v` | 高云 DDR3 控制器（**加密 IP**） |
| `src/video_frame_buffer/Video_Frame_Buffer_Top.v` | 高云视频帧缓冲（**加密 IP**） |
| `src/top.cst` / `src/lcd.sdc` | 引脚约束 / 时钟约束 |

> 两个加密 IP 是厂商用 AES 加密的 Verilog，只有高云综合器能解，**无法还原成可读代码**。
> 但它们的接口完全可用，`top.v` 里的连线就是完整用法。

## 按键

底板 **T2**（低有效，20 ms 消抖，下降沿触发）→ 切换图像处理档位，0–14 循环
底板 **T3**（同上）→ 切换追踪颜色，0–9 循环

```verilog
// 20 ms 消抖 + 下降沿检测
if (db_div == 20'd640_000) begin
    db2_div <= 0;
    key_d   <= key_s[2];
    if (key_d && !key_s[2])
        color_r <= (color_r == 4'd9) ? 4'd0 : color_r + 4'd1;
end
```

## 关键实现

**BGR → RGB 修正**：OV5640 经 DVP 送出的 RGB565 是 BGR 顺序，必须对调后再写入帧缓冲，否则红蓝互换。

```verilog
assign write_data = {cmos_16bit_data[4:0], cmos_16bit_data[10:5], cmos_16bit_data[15:11]};
.I_vin0_data (write_data)
```

**模式位宽陷阱**：`img_proc.mode` 是 3 位而档位是 4 位，直接接 `mode_r[2:0]` 会把 12 档截成 4 档（只留红）、9 档截成 1 档（灰度）。8 档以上必须让 img_proc 直通：

```verilog
.mode (mode_r[3] ? 3'd0 : mode_r[2:0])
```

**帧锁存必须用边沿**：VS 高电平持续约 4 行，若用 `if (frame)` 锁存包围盒，第 2 拍就被覆盖成空值，结果永远不画框。

```verilog
wire fstart = frame & ~vs_d;   // VS 上升沿
```

**行缓存与 BSRAM**：读无条件、写受 `de` 控制，否则会被展开成 375 个分布式 RAM16，挤占布线并扰动 DDR3。

**摄像头配置**：配置表写满 256 条即停（表尾 `0xff`）；约 5 秒超时停机；有 NACK 时整表重试，最多 6 遍；`0x3820 = 0x41` 做垂直翻转。

**追踪防误判（四重）**：

| 措施 | 实现 |
| --- | --- |
| 3 抽头去噪 | 连续 3 个像素命中才算有效 |
| 中心区域 | 仅 x 120–680、y 40–440 参与统计 |
| 命中门限 | 一帧命中像素数 ≥ 600 才更新包围盒 |
| 满屏抑制 | 包围盒超过 716×456 视为无效 |

## 资源占用

| 资源 | 占用 | 总量 | 比例 |
| --- | --- | --- | --- |
| Logic | ~6600 | 20736 | 32% |
| Register | ~2300 | 16173 | 14% |
| BSRAM | 18 | 46 | 39% |
| DSP | 4.5 | 24 | 19% |
| PLL | 3 | 4 | 75% |

## 编译与烧写

命令行：

```
D:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe build.tcl
```

IDE：打开 `Camera_LCD.gprj` → Synthesize → Place & Route

⚠️ **Project → Configuration → Dual-Purpose Pin → 勾选 SSPI**（`lcd_r[2]` 使用专用脚 N9，不勾会报 PR2017）

烧写注意：

1. Programmer 里先 `Erase` 再 `Program`，确认真的报 success
2. **烧完必须断电重新上电**（Flash 里的位流才会被加载）
3. 下载速度调最低、用后面板 USB 口、Flash 型号选 `Generic Flash`
4. 若上电后黑屏（摄像头没配上），断电重上一次

## 已知问题

| 现象 | 原因 |
| --- | --- |
| 画面每几秒轻微顿一下 | 帧缓冲 IP 的帧尺寸固定 800×600，与 480 行屏、摄像头帧率不成整数倍 |
| 上电偶尔黑屏 | 摄像头一次性配置偶发失败，重新上电可恢复 |
| 追踪框不够贴合 | 包围盒对零散命中敏感，建议选高对比目标或干净背景 |
| 目标与背景同色时不框 | 颜色阈值法的固有局限，需换帧差或连通域算法 |

## 文档

- `docs/Camera_LCD_技术交付文档.docx` — 模块设计、关键实现、踩坑记录
- `docs/Camera_LCD_源码全集.docx` — 全部源码（带行号）

## License

MIT
