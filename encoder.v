// encode the mipi frame to send to processor

module encoder (
	input		    tx_pixel_clk,

	input [7:0]     fifo_data,
	input 		    fifo_empty,
    input           fifo_we,

    input           valid_frame,
    // input           valid_h_patgen,
    input [9:0]     x,
    input [9:0]     y,

    output reg      trig_pin,
    output reg      mipi_rst = 1,
	output [63:0] 	mipi_data,
	output reg	    fifo_re = 0,
    output reg [2:0]state = 0
);

localparam SOF = 48'hEA_FF_99_DE_AD_FF,
	EOF = 48'hEA_FF_99_DE_AD_AA;

localparam IDLE = 0,
    WAIT_VALID_FRAME = 1,
    WAIT_ACTIVE_STATE = 2,
	SEND_SOF = 3,
	SEND_METADATA = 4,
	SEND_PAYLOAD = 5,
	SEND_EOF = 6,
    CLEANUP = 7;

// reg [2:0] state;
reg [7:0] uart_payload = 0;
reg [47:0] frame_data = 0;

always @(posedge tx_pixel_clk) begin
	case (state)
		IDLE: begin
			if (~fifo_empty & ~fifo_we) begin
                if (x > 0 && x < 800 && y > 1 && y < 600)
                    state <= SEND_SOF;
                else state <= WAIT_VALID_FRAME;
				fifo_re <= 1;
                mipi_rst <= 0;
			end
           
            if (valid_frame) begin
                mipi_rst <= 1;
                trig_pin <= 0;
            end else
                frame_data <= 0;
		end
        
        WAIT_VALID_FRAME: begin
			fifo_re <= 0;
            if (valid_frame)
                state <= WAIT_ACTIVE_STATE;
        end
        
        WAIT_ACTIVE_STATE: begin
			fifo_re <= 0;
            if (x > 1 && y > 1) begin
                state <= SEND_SOF;
                trig_pin <= 1;
            end
        end

		SEND_SOF: begin
            fifo_re <= 0;
			frame_data <= SOF;
			state <= SEND_METADATA;
		end

		SEND_METADATA: begin
            uart_payload <= fifo_data;
			frame_data <= {
				8'h02,
				24'h01,
				8'h01,
				8'h00
			};
			state <= SEND_PAYLOAD;
		end

		SEND_PAYLOAD: begin
			frame_data <= {56'h0, uart_payload};
			state <= SEND_EOF;
		end

		SEND_EOF: begin
			frame_data <= EOF;
			state <= CLEANUP;
		end
        
        CLEANUP: begin
            frame_data <= 0;
            state <= IDLE;
        end

		default: begin
			state <= IDLE;
		end
	endcase
end

assign mipi_data = {
	16'h0,
	frame_data[7:0],
	frame_data[15:8],
	frame_data[23:16],
	frame_data[31:24],
	frame_data[39:32],
	frame_data[47:40]
};

endmodule
