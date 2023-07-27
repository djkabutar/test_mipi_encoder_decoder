module top (
/* Signals of the video pattern generator */

	input         tx_vga_clk,

/* Flashing LEDs to indicate successful comparison of MIPI data */

    output        led0,
    output        led1,
	
/* Clocks of MIPI TX and RX parallel interfaces */
	    
	input         tx_pixel_clk,
	input         rx_pixel_clk,

/* UART RX and TX interfacing */    

    input         uart_rx_pin,
    output        uart_tx_pin,

/* Signals used by the MIPI RX Interface Designer instance */
    
	input         my_mipi_rx_VALID,
	input [3:0]   my_mipi_rx_HSYNC,
	input [3:0]   my_mipi_rx_VSYNC,
	input [63:0]  my_mipi_rx_DATA,
	input [5:0]   my_mipi_rx_TYPE,
	input [1:0]   my_mipi_rx_VC,
	input [3:0]   my_mipi_rx_CNT,
	input [17:0]  my_mipi_rx_ERROR,
	input         my_mipi_rx_ULPS_CLK,
	input [3:0]   my_mipi_rx_ULPS,

    output        my_mipi_rx_DPHY_RSTN,
	output        my_mipi_rx_RSTN,
	output        my_mipi_rx_CLEAR,
	output [1:0]  my_mipi_rx_LANES,
	output [3:0]  my_mipi_rx_VC_ENA,
    
/* Signals used by the MIPI TX Interface Designer instance */
	    
	output        my_mipi_tx_DPHY_RSTN,
	output        my_mipi_tx_RSTN,
	output        my_mipi_tx_VALID,
	output        my_mipi_tx_HSYNC,
	output        my_mipi_tx_VSYNC,
	output [63:0] my_mipi_tx_DATA,
	output [5:0]  my_mipi_tx_TYPE,
	output [1:0]  my_mipi_tx_LANES,
	output        my_mipi_tx_FRAME_MODE,
	output [15:0] my_mipi_tx_HRES,
	output [1:0]  my_mipi_tx_VC,
	output [3:0]  my_mipi_tx_ULPS_ENTER,
	output [3:0]  my_mipi_tx_ULPS_EXIT,
	output        my_mipi_tx_ULPS_CLK_ENTER,
	output        my_mipi_tx_ULPS_CLK_EXIT
);

  wire rst_n = 1'b1;
//-----------------------------------------------------------//
// 800*600 VGA
//-----------------------------------------------------------//

/*
parameter syncPulse_h= 80;            
parameter backPorch_h= 50;             
parameter activeVideo_h= 640;            
parameter frontPorch_h= 50; 
           
parameter syncPulse_v= 80;              
parameter backPorch_v = 5;             
parameter activeVideo_v = 480;            
parameter frontPorch_v = 5;
*/

parameter syncPulse_h= 128;
parameter backPorch_h= 88;
parameter activeVideo_h= 800;
parameter frontPorch_h= 40;
parameter syncPulse_v= 4;
parameter backPorch_v = 23;
parameter activeVideo_v = 600;
parameter frontPorch_v = 1;

parameter FIFO_ADDR_WIDTH = 12;
parameter FIFO_DEPTH = (1 << FIFO_ADDR_WIDTH);

localparam HALF_FIFO_DEPTH = FIFO_DEPTH >> 1;
localparam total_pixel = activeVideo_h * activeVideo_v;
   
//**************************
// Pattern generation module
//**************************
   
wire[3:0]  video_pattern;
wire[4:0]  vga_r_patgen;
wire[5:0]  vga_g_patgen;
wire[4:0]  vga_b_patgen; 

wire hsync_patgen;
wire vsync_patgen; 
wire valid_h_patgen;
wire valid_v_patgen;

wire uart_rx_valid;
wire [7:0] uart_rx_data;
wire [7:0] fifo_out_data;
wire fifo_empty;

wire fifo_re;
wire valid_frame;
wire mipi_rst;

wire [9:0] x,y;

reg valid_frame_prev;
wire trig_pin;

reg [2:0] prev_encoder_state;
wire [2:0] encoder_state;

video_gen #(.syncPulse_h (syncPulse_h),
            .backPorch_h (backPorch_h),
            .activeVideo_h (activeVideo_h),
            .frontPorch_h (frontPorch_h),
            .syncPulse_v (syncPulse_v),
            .backPorch_v (backPorch_v),
            .activeVideo_v (activeVideo_v),
            .frontPorch_v (frontPorch_v)
            ) patgen (
                    .rst (mipi_rst),
                    .clk (tx_vga_clk),
                    .video_pattern (video_pattern),
                    .video_valid_h_o (valid_h_patgen),
                    .video_valid_h_o_2 (),
                    .video_hsync_o (hsync_patgen),
                    .video_hsync_o_2 (),
                    .video_vsync_o (vsync_patgen),
                    .video_valid_v_o (valid_v_patgen),
                    .valid_frame(valid_frame),
                    .red_o (vga_r_patgen),
                    .green_o (vga_g_patgen),
                    .blue_o (vga_b_patgen),
                    .x(x),
                    .y(y)
                    );

//***************
// MIPI TX HOOKUP
//***************

wire [63:0] pixel_data;

always @(posedge tx_vga_clk) begin
    valid_frame_prev <= valid_frame;
end

always @(posedge tx_pixel_clk) begin
    prev_encoder_state <= encoder_state;
end

uart_rx #(
    .CLOCKS_PER_BIT(20)
) receiver (
    .i_Clock(tx_pixel_clk),
    .i_RX_Serial(uart_rx_pin),
    .o_RX_DV(uart_rx_valid),
    .o_RX_Byte(uart_rx_data)
);

assign led0 = (encoder_state != prev_encoder_state);
// assign led1 = fifo_empty;

fifo #(
    .DATA_WIDTH(8),
    .ADDR_WIDTH(12)
) uart_fifo (
    .clk(tx_pixel_clk),
    .rst_n(1'b1),
    .data_in(uart_rx_data),
    .we(uart_rx_valid),
    .re(fifo_re),
    .data_out(fifo_out_data),
    .empty(fifo_empty)
);

/*
always @(posedge tx_pixel_clk) begin
    if (uart_rx_valid)
        trig_pin <= 1;
    else if (valid_frame | valid_frame_prev)
        trig_pin <= 0;
end
*/

encoder e1 (
	.tx_pixel_clk(tx_pixel_clk),
	.fifo_data(fifo_out_data),
	.fifo_empty(fifo_empty),
    .valid_frame((valid_frame | valid_frame_prev)),
    .mipi_rst(mipi_rst),
	.mipi_data(pixel_data),
    .trig_pin(trig_pin),
	.fifo_re(fifo_re),
    .state(encoder_state),
    .fifo_we(uart_rx_valid),
    .x(x),
    .y(y)
    // .valid_h_patgen(valid_h_patgen)
);

wire [7:0] decoder_data;
wire decoder_fifo_empty;
wire uart_fifo_we;

reg decoder_re;
reg [7:0] uart_tx_data = 0;
reg [2:0] uart_state = 0;
reg send_uart;

decoder d1 (
    .rx_pixel_clk(rx_pixel_clk),
    .mipi_rx_data(my_mipi_rx_DATA),
    .mipi_rx_valid(my_mipi_rx_VALID),
    
    .uart_fifo_re(decoder_re),
    .uart_fifo_we(uart_fifo_we),
    
    .uart_data(decoder_data),
    .uart_fifo_empty(decoder_fifo_empty),
    .debug_pin(led1)
);

uart_tx #(
    .CLKS_PER_BIT(40)
) transmitter (
    .i_Rst_L(1'b1),
    .i_Clock(rx_pixel_clk),
    .i_TX_DV(send_uart),
    .i_TX_Byte(uart_tx_data),
    .o_TX_Serial(uart_tx_pin),
    .o_TX_Done(uart_tx_done)
);

always @(posedge rx_pixel_clk) begin
    case (uart_state)
        0: begin
            if (~decoder_fifo_empty & ~uart_fifo_we) begin
                decoder_re <= 1;
                uart_state <= 1;
            end
        end
        
        1: begin
            decoder_re <= 0;
            uart_state <= 2;
        end
        
        2: begin
            uart_tx_data <= decoder_data;
            uart_state <= 3;
        end
        
        3: begin
            send_uart <= 1;
            uart_state <= 4;
        end
        
        4: begin
            send_uart <= 0;
            if (uart_tx_done)
                uart_state <= 0;
        end
        
        default: begin
            uart_state <= 0;
        end
    endcase
end

assign my_mipi_tx_DPHY_RSTN = ~mipi_rst;
assign my_mipi_tx_RSTN = ~mipi_rst;
assign my_mipi_tx_VALID = valid_h_patgen;
assign my_mipi_tx_HSYNC = hsync_patgen;//hsync_patgen_PC;
assign my_mipi_tx_VSYNC = vsync_patgen;//vsync_patgen_PC;
assign my_mipi_tx_DATA =  pixel_data;// tx_pixel_data_PC;//pixel_data; 64'hff0000ff0000; //: 64'd0;//tx_pixel_data_PC;//64'hFF111111000000;
// assign my_mipi_tx_DATA = 64'h204f4c4c4548;
assign my_mipi_tx_TYPE = 6'h24;			// RGB888
assign my_mipi_tx_LANES = 2'b11;                // 4 lanes
assign my_mipi_tx_FRAME_MODE = 1'b0;            // Generic Frame Mode
assign my_mipi_tx_HRES = activeVideo_h;         // Number of pixels per line
assign my_mipi_tx_VC = 2'b00;                   // Virtual Channel select
assign my_mipi_tx_ULPS_ENTER = 4'b0000;
assign my_mipi_tx_ULPS_EXIT = 4'b0000;
assign my_mipi_tx_ULPS_CLK_ENTER = 1'b0;
assign my_mipi_tx_ULPS_CLK_EXIT = 1'b0;

assign my_mipi_rx_DPHY_RSTN = 1'b1;
assign my_mipi_rx_RSTN = 1'b1;
assign my_mipi_rx_CLEAR = 1'b0;
assign my_mipi_rx_LANES = 2'b11;         // 4 lanes
assign my_mipi_rx_VC_ENA = 4'b0001;      // Virtual Channel enable

// assign led5 = hsync_patgen;//(flash_cnt==25'b0) ? 1 : flash_cnt[24];
// assign led6 = vsync_patgen;//vsync_patgen_PC;//(flash_cnt==25'b0) ? 1 : ~flash_cnt[24];

endmodule
