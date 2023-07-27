module udg(
    input clk, rst,
    input fifo_we,
	input [63:0] data_in,
	output tx,full
);
 
reg fifo_re = 1'b0, uart_tx_en;
wire [63:0] data_in, qword;
wire [7:0] tx_data;
parameter IDLE      = 4'd0,
          GET_BYTE  = 4'd1,
          WRITE_SPACE  = 4'd2,
          DONE      = 4'd3,
		  GET_QWORD = 4'd4,
		  WRITE_LSB   = 4'd5,
		  SET_TX_BYTE = 4'd6,
		  WAIT4_TXDONE = 4'd7,
          WRITE_MSB  = 4'd8,
          WRITE_LN = 4'd9,
          NONE      = 4'd10;

reg [3:0] current_state, next_state = IDLE, previous_state = NONE; 
parameter HEX_CHAR0 = 2'b00,
          HEX_CHAR1 = 2'b01,
          CONTROL_CHAR0 = 2'b10,
          CONTROL_CHAR1 = 2'b11; 
reg [7:0] binary;
wire [7:0] ASCII_HEX0,ASCII_HEX1;
assign tx_data = (mux == 2'b00) ? ASCII_HEX1 : 
                 (mux == 2'b01) ? ASCII_HEX0 : 
                 (mux == 2'b10) ?  8'h20 :
                 (mux == 2'b11) ?  8'h0A : 8'h20;

always@(posedge clk or negedge rst)begin
    if(~rst)current_state <= IDLE;
    else current_state <= next_state;
end

always@(current_state,fifo_empty,uart_done,index,mux)begin
    fifo_re = 1'b0; 
    uart_tx_en = 1'b0;
    mux = HEX_CHAR0;
    case(current_state)
		IDLE : begin 
				if(~fifo_empty)next_state = GET_QWORD;
				else next_state = IDLE;
		end

		GET_QWORD : begin
			fifo_re = 1'b1;
			 next_state = WRITE_LSB;
            //else next_state = IDLE;
		end
        
        WRITE_LSB :begin 
                    mux = HEX_CHAR0;
                    uart_tx_en = 1'b1;
					next_state = WAIT4_TXDONE;
                   end
                   
        WRITE_MSB :begin 
                    mux = HEX_CHAR1;
                    uart_tx_en = 1'b1;
					next_state = WAIT4_TXDONE;
                   end
                   
        WRITE_SPACE :begin 
                    mux = CONTROL_CHAR0;
                    uart_tx_en = 1'b1;
					next_state = WAIT4_TXDONE;
                   end
                   
        WRITE_LN :begin 
                    mux = CONTROL_CHAR1;
                    uart_tx_en = 1'b1;
					next_state = WAIT4_TXDONE;
                   end     
		
		WAIT4_TXDONE :begin
						if(~uart_done )begin
                           next_state = SET_TX_BYTE;
                        /*
						  if(mux == HEX_CHAR1)next_state = TX_BYTE;
                          else if(mux == CONTROL_CHAR0) next_state = SET_TX_BYTE;
						  else if(mux == CONTROL_CHAR1) next_state = SET_TX_BYTE;
                          else if(index < 7) next_state = SET_TX_BYTE;
                          else next_state = IDLE; 
                        */
						end
						else next_state = WAIT4_TXDONE;
					end

		SET_TX_BYTE : begin          
                            if     (previous_state == WRITE_LSB)  next_state = WRITE_MSB;
                            else if(previous_state == WRITE_MSB)  next_state = WRITE_SPACE;
                            else if(previous_state == WRITE_SPACE && index < 8)  next_state = WRITE_LSB;
                            else if(previous_state == WRITE_SPACE && index == 8) next_state = WRITE_LN;
                            else if(previous_state == WRITE_LN) next_state = IDLE;
                            else next_state = SET_TX_BYTE;
                     end
        
		default : next_state = IDLE;
    endcase
end

reg [7:0] byte0, byte1, byte2, byte3, byte4, byte5, byte6, byte7;//[0:8];
reg [3:0] index;

reg [1:0] mux = 2'b00;


always@(index,byte0, byte1, byte2, byte3, byte4, byte5, byte6, byte7)begin
    case(index)			
        3'd0 : binary <= byte0;
        3'd1 : binary <= byte1;
        3'd2 : binary <= byte2;
        3'd3 : binary <= byte3;
        3'd4 : binary <= byte4;
        3'd5 : binary <= byte5;
        3'd6 : binary <= byte6;
        3'd7 : binary <= byte7;	
        default : binary <= 0;			
    endcase
end


always@(posedge clk or negedge rst)begin
    if(~rst)begin
		index <= 3'd0;
		byte0 <= 8'd0;
		byte1 <= 8'd0;
		byte2 <= 8'd0;
		byte3 <= 8'd0;
		byte4 <= 8'd0;
		byte5 <= 8'd0;
		byte6 <= 8'd0;
		byte7 <= 8'd0;	
    end
    else begin
        case(current_state)
            IDLE : begin 
                index <= 8'd0;
            end
			GET_QWORD : begin
				byte7 <= qword[7:0];
				byte6 <= qword[15:8];
				byte5 <= qword[23:16];
				byte4 <= qword[31:24];
				byte3 <= qword[39:32];
				byte2 <= qword[47:40];
				byte1 <= qword[55:48];
				byte0 <= qword[63:56];
			end
            
            WRITE_LSB : begin
                previous_state <= WRITE_LSB;
            end
            
            WRITE_MSB : begin
                previous_state <= WRITE_MSB;
            end
            
            WRITE_SPACE : begin
                previous_state <= WRITE_SPACE;     
            end
            
            WRITE_LN : begin
                previous_state <= WRITE_LN;          
            end

			
			SET_TX_BYTE : begin                  
					if(previous_state == WRITE_SPACE) if( index < 8) index <= index + 1'b1;
			end	
			
        endcase
    end
end



bin2ascii b2a_0(
	.binary(binary[3:0]),
	.ASCII_HEX(ASCII_HEX0)
);

bin2ascii b2a_1(
	.binary(binary[7:4]),
	.ASCII_HEX(ASCII_HEX1)
);


fifo #(.DATA_WIDTH(64),
       .ADDR_WIDTH(8))  i_fifo(
    .clk(clk),
    .rst_n(rst),
    .data_in(data_in),
    .we(fifo_we),
    .re(fifo_re),
    .data_out(qword),
    //.occupants,
    .empty(fifo_empty),
    .full(full)
);    

uart_tx #(
    .CLKS_PER_BIT(10)
) uart_core (
    .i_Rst_L(rst),
    .i_Clock(clk),
    .i_TX_DV(uart_tx_en) ,
    .i_TX_Byte(tx_data),
    // .rx()     
    // .rx_busy 
    // .rx_error
    // .rx_data 
    .o_TX_Active(uart_done),
    .o_TX_Serial(tx) ,
    .o_TX_Done()
);

endmodule
