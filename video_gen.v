
module video_gen (
 input        rst,
 input        clk,
 input [1:0]  video_pattern,
 output [7:0] red_o,
 output [7:0] green_o,
 output [7:0] blue_o,
 output       video_hsync_o,
 output       video_hsync_o_2,
 output       video_vsync_o,
 output       video_valid_h_o,
 output       video_valid_h_o_2,
 output       video_valid_v_o,
 output       valid_frame,
 output reg [9:0] x,y
);

parameter syncPulse_h= 128;            
parameter backPorch_h= 88;             
parameter activeVideo_h= 800;            
parameter frontPorch_h= 40;            
parameter syncPulse_v= 4;              
parameter backPorch_v = 23;             
parameter activeVideo_v = 600;            
parameter frontPorch_v = 1;

localparam total_h = syncPulse_h + backPorch_h + activeVideo_h + frontPorch_h;
localparam total_v = syncPulse_v + backPorch_v + activeVideo_v + frontPorch_v;
localparam activeStart_h = syncPulse_h + backPorch_h;
localparam activeEnd_h= activeVideo_h + activeStart_h;
localparam activeStart_v= syncPulse_v + backPorch_v;
localparam activeEnd_v= activeVideo_v + activeStart_v;

localparam bar2 = activeStart_h+activeVideo_h*1/8;
localparam bar3 = activeStart_h+activeVideo_h*2/8;
localparam bar4 = activeStart_h+activeVideo_h*3/8;
localparam bar5 = activeStart_h+activeVideo_h*4/8;
localparam bar6 = activeStart_h+activeVideo_h*5/8;
localparam bar7 = activeStart_h+activeVideo_h*6/8;
localparam bar8 = activeStart_h+activeVideo_h*7/8;

wire video_vsync, video_valid_v;
wire video_hsync, video_valid_h;
reg video_vsync_o, video_valid_v_o;
reg video_hsync_o, video_valid_h_o;
reg video_hsync_o_2, video_valid_h_o_2;
reg [16:0] h_count;
reg [16:0] v_count;
wire [15:0] bar_data;
wire [15:0] checker_color;
wire [15:0] checker_data;
   
always @ (posedge clk) begin
if (rst) begin 
	h_count <= 1'b1;
	v_count <= 1'b1;
	end
else if (h_count == total_h)
	if (v_count == total_v) begin
	h_count <= 1'b1;
	v_count <= 1'b1;
	end
	else begin
	h_count <= 1'b1;
	v_count <= v_count + 1'b1;
	end
else begin
	h_count <= h_count + 1'b1;
	end
end

assign video_hsync = (h_count>=syncPulse_h) && (h_count < total_h);
assign video_valid_h = (h_count >= activeStart_h) && (h_count < activeEnd_h) && video_valid_v_o;
assign valid_frame = (h_count == total_h) && (v_count == total_v);

    always @ (posedge clk)
	begin
	   if(rst) begin
	      video_vsync_o <= 1'b0;
	      video_valid_v_o <= 1'b0; end
	   else if(h_count == total_h) begin
              if(v_count == total_v)
                video_vsync_o <= 1'b0;
              else begin
                 if(v_count == syncPulse_v)
                   video_vsync_o <= 1'b1;
                 else if(v_count == activeStart_v)
                   video_valid_v_o <= 1'b1;
                 else if(v_count == activeEnd_v)
                   video_valid_v_o <= 1'b0;
              end
           end // if (h_count == total_h)
        end // always @ (posedge clk)
   
/////sync the video format to clk ///////
always @(posedge clk) begin
   if(rst) begin
      video_hsync_o <= 1'b0;
      video_valid_h_o <= 1'b0;
      video_hsync_o_2 <= 1'b0;
      video_valid_h_o_2 <= 1'b0;
      red_o <= 5'b0;
      green_o <= 6'b0;
      blue_o <= 5'b0;
   end
   else begin
      video_hsync_o <= video_hsync;
      video_valid_h_o <= video_valid_h;
      video_hsync_o_2 <= video_hsync_o;
      video_valid_h_o_2 <= video_valid_h_o;
      red_o <= red;
      green_o <= green;
      blue_o <= blue;
end	
end // always @ (posedge clk)
   
  assign bar_data = ((h_count>=activeStart_h)&(h_count<bar2))?{5'b11111,6'b111111,5'b11111}:
					((h_count>=bar2)&(h_count<bar3))?{5'b11111,6'b111111,5'b00000}:
					((h_count>=bar3)&(h_count<bar4))?{5'b00000,6'b111111,5'b11111}:
					((h_count>=bar4)&(h_count<bar5))?{5'b00000,6'b111111,5'b00000}:
					((h_count>=bar5)&(h_count<bar6))?{5'b11111,6'b000000,5'b11111}:
					((h_count>=bar6)&(h_count<bar7))?{5'b11111,6'b000000,5'b00000}:
					((h_count>=bar7)&(h_count<bar8))?{5'b00000,6'b000000,5'b11111}:
					{5'b00000,6'b000000,5'b00000};  

   assign checker_color = (h_count[6]&v_count[6]) ? 16'hf800 : (!h_count[6]&!v_count[6]) ? 16'h001f : 16'h07e0;
   assign checker_data = (h_count[5]^v_count[5]) ? checker_color : 16'h0000;
   
//----------------------------------------------------------------
////////// DISPLAY
//----------------------------------------------------------------
wire [7:0] red;
wire [7:0] green;
wire [7:0] blue;
reg [7:0]  red_o;
reg [7:0]  green_o;
reg [7:0]  blue_o;

//------ Get XY Cordinates of screen 

always @(posedge clk)begin
    if(h_count >= activeStart_h && h_count <= activeEnd_h)begin
        x <= h_count - activeStart_h; //x + 1;
    end
    else begin
        x <= 0;
        end
    if(v_count >= activeStart_v && v_count <= activeEnd_v)begin
        // y <= v_count - (syncPulse_v + backPorch_v);
        y <= v_count - activeStart_v;
    end
    else y <= 0;
end 
 /*  
true_dual_port_ram
#(
	.DATA_WIDTH(48),
	.ADDR_WIDTH(9),
	.WRITE_MODE_1("WRITE_FIRST"),
	.WRITE_MODE_2("WRITE_FIRST"),
	.OUTPUT_REG_1("TRUE"),
	.OUTPUT_REG_2("TRUE"),
	.RAM_INIT_FILE("buffer.mem")		// Initial code file   ("piv2_720p_reg.mem")
)
inst_piv2_reg
(
	.we1(1'b0),
	.we2(1'b0),
	.clka(tx_vga_clk),
	.clkb(tx_vga_clk),
	.din1({8{1'b0}}),
	.din2({8{1'b0}}),
	.addr1(i[9:0]),
	//.addr2(i_dbg_addr),
	.dout1(pixel_data)
//	.dout2(o_dbg_dout)
);

*/
wire [63:0]buffer1, buffer2;
assign red =  (h_count>activeEnd_h && h_count[0])? buffer1[7:0]:buffer2[7:0];//(video_pattern==3) ? v_count[6:2] : (video_pattern==2) ? h_count[6:2] : (video_pattern==1) ? bar_data[15:11] : checker_data[15:11];
assign green =(h_count>activeEnd_h && h_count[0])? buffer1[15:8]:buffer2[15:8]; //(video_pattern==3) ? v_count[6:1] : (video_pattern==2) ? h_count[6:1] : (video_pattern==1) ? bar_data[10:5] : checker_data[10:5];
assign blue = (h_count>activeEnd_h && h_count[0])? buffer1[23:16]:buffer2[23:8]; //(video_pattern==3) ? v_count[6:2] :(video_pattern==2) ? h_count[6:2] : (video_pattern==1) ? bar_data[4:0] : checker_data[4:0];


endmodule