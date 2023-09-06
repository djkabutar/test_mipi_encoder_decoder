module i2c_master#(
    parameter DATA_WIDTH = 8,
    parameter REG_WIDTH  = 8,
    parameter ADDR_WIDTH = 7 
)(
    input                           i_clk,
    input                           i_enable,
    input                           i_rw,
    input       [DATA_WIDTH-1:0]    i_mosi_data,
    input       [REG_WIDTH-1:0]     i_reg_addr,
    input       [ADDR_WIDTH-1:0]    i_device_addr,
    input  wire [15:0]              i_divider, // value = 249 for 100 MHz clock freq.
    output reg  [DATA_WIDTH-1:0]    o_miso_data ,
    output reg                      o_busy = 0,
    output                          io_sda,
    input                           sda_input,
    output                          io_scl,
    input                           scl_input,
    output                          divider_tick,
    output                          scl_oe,
    output                          sda_oe,
    output reg [7:0] state,
    output i2c_done,
    output reg o_fifo_wren = 0
);
 
    localparam S_IDLE                =       8'h00;
    localparam S_START               =       8'h01;
    localparam S_WRITE_ADDR_W        =       8'h02;
    localparam S_CHECK_ACK           =       8'h03;
    localparam S_WRITE_REG_ADDR      =       8'h04;
    localparam S_RESTART             =       8'h05;
    localparam S_WRITE_ADDR_R        =       8'h06;
    localparam S_READ_REG            =       8'h07;
    localparam S_SEND_NACK           =       8'h08;
    localparam S_SEND_STOP           =       8'h09;
    localparam S_WRITE_REG_DATA      =       8'h0A;
    localparam S_WRITE_REG_ADDR_MSB  =       8'h0B;
    localparam S_WRITE_REG_DATA_MSB  =       8'h0C;
    localparam S_READ_REG_MSB        =       8'h0D;
    localparam S_SEND_ACK            =       8'h0E;    
    
    reg scl_out = 0;
    reg [ADDR_WIDTH:0] saved_device_addr = 0;
    reg [REG_WIDTH-1:0] saved_reg_addr = 0;
    reg [DATA_WIDTH-1:0] saved_mosi_data = 0;
    reg [7:0] post_state = S_IDLE;
    reg [1:0] proc_counter = 0;
    reg [7:0] bit_counter = 0;
    
    reg sda_out = 0;
    reg post_sda_out = 0;
    reg enable = 0;
    reg rw = 0;
    reg ack_received =0;
    reg done = 0;
    
    assign i2c_done = done; 
    
    wire sda_neg_oe;
    assign sda_oe = (state!=S_IDLE && state!=S_CHECK_ACK && state!=S_READ_REG && state!=S_READ_REG_MSB);
    assign sda_neg_oe = ~sda_oe;
    assign scl_neg_oe = ~scl_oe;
    wire scl_neg_oe;
    //when proc_counter = 1, we check for clock stretching from slave
    assign scl_oe = (state!=S_IDLE && proc_counter!=1 && proc_counter!=2);

    //tri state buffer for scl and sda
    assign io_scl = scl_out;
    assign io_sda = sda_out;
    
    reg [15:0] divider_counter = 0;
    assign divider_tick = (divider_counter == i_divider) ? 1 : 0;

    //i2c divider tick geneartor
    always @(posedge i_clk) begin
        if (divider_counter == i_divider)
            divider_counter <= 0;
        else
            divider_counter <= divider_counter + 1;
    end
    
    always @(posedge i_clk) begin
        if(divider_tick) begin
            case(state)
                S_IDLE: begin
                    proc_counter      <= 0;
                    sda_out           <= 1;
                    scl_out           <= 1;
                    enable            <= i_enable;
                    saved_device_addr <= {i_device_addr, 1'b0};
                    saved_reg_addr    <= i_reg_addr;
                    saved_mosi_data   <= i_mosi_data;
                    o_busy            <= 0;
                    ack_received      <= 0;
                    rw                <= i_rw;
                    done              <= 0;
                    o_fifo_wren       <= 1'b0;
                        
                    if (enable) begin
                        state <= S_START;
                        post_state <= S_WRITE_ADDR_W;
                    end	// if_block
                end	// S_IDLE
                
                S_START: begin
                        case(proc_counter)
                        0: begin
                            proc_counter <= 1;
                            o_busy       <= 1;
                            enable       <= 0;
                        end	//0
                        1: begin
                            sda_out      <= 0;
                            proc_counter <= 2;
                        end	//1
                        2: begin
                            proc_counter <= 3;
                            bit_counter  <= 8;
                        end	//2
                        3: begin
                            scl_out      <= 0;
                            proc_counter <= 0;
                            state        <= post_state;
                            sda_out      <= saved_device_addr[ADDR_WIDTH];
                        end	//3
                    endcase	//proc_counter_case
                end		//S_START
                        
                S_WRITE_ADDR_W: begin
                    case(proc_counter)
                        0:begin
                            scl_out      <= 1;
                            proc_counter <= 1;
                        end	//0
                        1: begin
                            if(scl_input == 1) begin
                                proc_counter <= 2;
                            end	//1
                        end
                        2: begin
                            scl_out      <= 0;
                            bit_counter  <= bit_counter -1;
                            proc_counter <= 3;
                        end	//2
                        3: begin
                            if(bit_counter == 0) begin
                                post_sda_out <= saved_reg_addr[REG_WIDTH-1];
                                            
                                if(REG_WIDTH == 16) begin
                                    post_state <= S_WRITE_REG_ADDR_MSB;
                                end	//inner_if_block
                                            
                                else begin
                                    post_state <= S_WRITE_REG_ADDR;
                                end	//inner_else_block
                                            
                                state <= S_CHECK_ACK;
                                bit_counter <= 8;
                            end	//outer_if_block
                                      
                            else begin
                                sda_out <= saved_device_addr[bit_counter-1];
                            end	//outer_else_block
                                      
                            proc_counter <= 0;
                        end	//3
                    endcase	//proc_counter_case
                end	//	S_WRITE_ADDR_W
                
                S_CHECK_ACK: begin
                    case(proc_counter)
                        0:begin
                            scl_out <= 1;
                            sda_out <= 1;
                            proc_counter <= 1;
                        end	//0
                        1: begin
                            if(scl_input == 1) begin
                                ack_received <= 0;
                                proc_counter <= 2;
                            end	//1
                        end
                        2: begin
                            scl_out          <= 0;					
                            if(sda_input == 0) begin
                                ack_received <= 1;
                            end	//if_block
                            else if(sda_input == 1) begin
                                ack_received <= 0;
                            end //else_block
                            proc_counter     <= 3;
                        end	//2
                        3: begin
                            if(ack_received) begin
                                state <= post_state;
                                ack_received <= 0;
                                sda_out <= post_sda_out;
                            end	//if_block
                            else begin
                                state <= S_SEND_STOP;
                            end	//else_block
                            proc_counter <= 0;
                        end	//3
                    endcase	//proc_counter_case
                end	//S_CHECK_ACK
                
                S_WRITE_REG_ADDR_MSB: begin
                    case(proc_counter)
                        0: begin
                            scl_out <= 1;
                            proc_counter <= 1;
                        end	//0
                        1: begin
                            if(scl_input == 1) begin
                                ack_received <= 0;
                                proc_counter <= 2;
                            end	//if_block
                        end	//1
                        2: begin
                            scl_out          <= 0;
                            bit_counter      <= bit_counter -1;
                            proc_counter     <= 3;
                        end	//2
                        3: begin
                            if(bit_counter == 0) begin
                                post_state   <= S_WRITE_REG_ADDR;
                                post_sda_out <= saved_reg_addr[7];
                                bit_counter  <= 8; 
                                sda_out      <= 0;
                                state        <= S_CHECK_ACK;
                            end	//if_block
                            else begin
                              sda_out <= saved_reg_addr[bit_counter+7];
                            end	//else_block
                            proc_counter <= 0;
                        end	//3
                    endcase	//proc_counter_case
                end	//S_WRITE_REG_ADDR_MSB
                
                S_WRITE_REG_ADDR: begin
                    case(proc_counter)
                        0:begin
                            scl_out <= 1;
                            proc_counter <= 1;
                        end	//0
                        1: begin
                            if(scl_input == 1) begin
                                ack_received <= 0;
                                proc_counter <= 2;
                            end	//if_block
                        end	//1
                        2: begin
                            scl_out      <= 0;
                            bit_counter  <= bit_counter -1;
                            proc_counter <= 3;
                        end	//2
                        3: begin
                            if(bit_counter == 0) begin
                                if(rw == 0) begin //write data
                                    if(DATA_WIDTH == 16) begin
                                        post_state   <= S_WRITE_REG_DATA_MSB;
                                        post_sda_out <= saved_mosi_data[15];
                                    end	//if_block
                                    else begin
                                        post_state   <= S_WRITE_REG_DATA;
                                        post_sda_out <= saved_mosi_data[7];
                                    end	//else_block
                                end	//if_block
                                else begin
                                    post_state   <= S_RESTART;
                                    post_sda_out <= 1;
                                end	//else_block
                                bit_counter <= 8; 
                                sda_out     <= 1;
                                state       <= S_CHECK_ACK;
                            end	//if_block
                            else begin
                                sda_out <= saved_reg_addr[bit_counter-1];
                            end	//else_block
                            proc_counter <= 0;
                        end	//3
                    endcase	//proc_counter_case
                end	//S_WRITE_REG_ADDR
                
                S_WRITE_REG_DATA_MSB: begin
                    case(proc_counter)
                        0:begin
                            scl_out      <= 1;
                            proc_counter <= 1;
                        end	//0
                        1: begin
                           if(scl_input == 1) begin
                                ack_received <= 0;
                                proc_counter <= 2;
                            end	//if_block
                        end	//1
                        2: begin
                            scl_out          <= 0;
                            bit_counter      <= bit_counter -1;
                            proc_counter     <= 3;
                        end	//2
                        3: begin
                            if(bit_counter == 0) begin
                                state        <= S_CHECK_ACK;
                                post_state   <= S_WRITE_REG_DATA;
                                post_sda_out <= saved_mosi_data[7];
                                bit_counter  <= 8; 
                                sda_out      <= 0;
                            end	//if_block
                            else begin
                                sda_out <= saved_mosi_data[bit_counter+7];
                            end	//else_block
                            proc_counter <= 0;
                        end	//3
                    endcase	//proc_counter_case
                end	//S_WRITE_REG_DATA_MSB
                
                S_WRITE_REG_DATA: begin
                    case(proc_counter)
                        0:begin
                            scl_out      <= 1;
                            proc_counter <= 1;
                        end	//0
                        1: begin
                            if(scl_input == 1) begin
                                ack_received <= 0;
                                proc_counter <= 2;
                            end	// if_block
                        end	//1
                        2: begin
                            scl_out      <= 0;
                            bit_counter  <= bit_counter -1;
                            proc_counter <= 3;
                        end	//2
                        3: begin
                            if(bit_counter == 0) begin
                                state        <= S_CHECK_ACK;
                                post_state   <= S_SEND_STOP;
                                post_sda_out <= 0;
                                bit_counter  <= 8; 
                                sda_out      <= 0;
                            end	//if_block
                            else begin
                                sda_out <= saved_mosi_data[bit_counter-1];
                            end	//else_block
                            proc_counter <= 0;
                        end	//3
                    endcase	//proc_counter_case
                end	//S_WRITE_REG_DATA
                
                S_RESTART: begin
                
                    case(proc_counter)
                        0:begin
                            scl_out <= 1;
                            proc_counter <= 1;
                        end	//0
                        1: begin
                            proc_counter <= 2;
                        end	//1
                        2: begin
                            proc_counter <= 3;
                        end	//2
                        3: begin
                            state        <= S_START;
                            post_state   <= S_WRITE_ADDR_R;
                            saved_device_addr[0] <= 1'b1;
                            proc_counter <= 0;
                        end	//3
                    endcase	//proc_counter_case
                end	//S_RESTART
                
                S_WRITE_ADDR_R: begin
                    case(proc_counter)
                        0: begin
                            scl_out      <= 1;
                            proc_counter <= 1;
                        end	//0
                        1: begin
                          if(scl_input == 1) begin
                                ack_received <= 0;
                                proc_counter <= 2;
                           end	//if_block
                        end	//1
                        2: begin
                            scl_out      <= 0;
                            bit_counter  <= bit_counter -1;
                            proc_counter <= 3;
                        end	//2
                        3: begin
                            if(bit_counter == 0) begin
                                if(DATA_WIDTH == 16) begin
                                    post_state   <= S_READ_REG_MSB;
                                    post_sda_out <= 0;
                                end	//if_block
                                else begin
                                    post_state   <= S_READ_REG;
                                    post_sda_out <= 0;
                                end	//else_block
                                state       <= S_CHECK_ACK;
                                bit_counter <= 8;
                            end	//if_block
                            else begin
                                sda_out <= saved_device_addr[bit_counter-1];
                            end	//else_block
                            proc_counter <= 0;
                        end	//3
                    endcase	//proc_counter_case
                end	//S_WRITE_ADDR_R
                
                S_READ_REG_MSB: begin
                    case(proc_counter)
                        0:begin
                            sda_out <= 0;
                            scl_out      <= 1;
                            proc_counter <= 1;
                        end	//0
                        1: begin
                            if(scl_input == 1) begin
                                ack_received <= 0;
                                proc_counter <= 2;
                            end	//if_block
                        end	//1
                        2: begin
                            scl_out <= 0; 
                            //sample data on this rising edge of scl
                            o_miso_data[bit_counter+7] <= sda_input;
                            bit_counter                <= bit_counter -1;
                            proc_counter               <= 3;
                        end	//2
                        3: begin
                            if(bit_counter == 0) begin
                                post_state  <= S_READ_REG;
                                state       <= S_SEND_ACK;
                                bit_counter <= 8;
                                sda_out     <= 0;
                            end	//if_block
                            proc_counter    <= 0;
                        end	//3
                    endcase	//proc_counter_case
                end//S_READ_REG_MSB
                
                S_READ_REG: begin
                    case(proc_counter)
                        0:begin
                            sda_out      <= 1;
                            scl_out      <= 1;
                            proc_counter <= 1;
                        end	//0
                        1: begin
                            if(scl_input == 1) begin
                                ack_received <= 0;
                                proc_counter <= 2;
                            end	//if_block
                        end	//1
                        2: begin
                            scl_out <= 0; 
                            //sample data on rising edge of scl
                            o_miso_data[bit_counter-1] <= sda_input;
                            bit_counter  <= bit_counter -1;
                            proc_counter <= 3;
                        end	//2
                        3: begin
                            if(bit_counter == 0) begin
                                state <= S_SEND_NACK;
                                sda_out  <= 1;
                            end	//if_block
                            proc_counter <= 0;
                        end	//3
                    endcase	//proc_counter_case
                end	//S_READ_REG
                
                S_SEND_NACK: begin
                    case(proc_counter)
                        0:begin
                            scl_out <= 1;
                            sda_out <= 1;
                            proc_counter <= 1;
                        end	//0
                        1: begin
                            if(scl_input == 1) begin
                                ack_received <= 0;
                                proc_counter <= 2;
                            end	//if_block
                        end	///1
                        2: begin
                            proc_counter <= 3;
                            scl_out      <= 0;
                        end	//2
                        3: begin
                            state        <= S_SEND_STOP;
                            proc_counter <= 0;
                            sda_out      <= 0;
                            o_fifo_wren <= 1'b1;
                        end	//3
                    endcase	//proc_counter_case
                  
                end	//S_SEND_NACK
                
                S_SEND_ACK: begin
                    case(proc_counter)
                        0:begin
                            scl_out      <= 1;
                            proc_counter <= 1;
                            sda_out      <= 0;
                        end	//0
                        1: begin
                            if(scl_input == 1) begin
                                proc_counter <= 2;
                            end	//	if_block
                        end	//1
                        2: begin
                            proc_counter <= 3;
                            scl_out      <= 0;
                        end	//2
                        3: begin
                            state        <= post_state;
                            proc_counter <= 0;
                        end	//3
                    endcase	//proc_counter_case
                end	//S_SEND_ACK
                
                S_SEND_STOP: begin
                    case(proc_counter)
                        0:begin
                            scl_out      <= 1;
                            proc_counter <= 1;
                            o_busy       <= 0;
                            o_fifo_wren <= 1'b0;
                        end	//0
                        1: begin
                            if(scl_input == 1) begin
                                proc_counter <= 2;
                            end	//if_block
                        end	//1
                        2: begin
                            scl_out <= 0;
                            proc_counter <= 3;
                            sda_out      <= 1;
                        end	//2
                        3: begin
                            done         <= 1;
                            state        <= S_IDLE;
                            proc_counter <= 0;
                        end	//3
                    endcase	//proc_counter_case
                    
                end	//S_SEND_STOP
                      
                default : begin
                    state <= S_IDLE;
                end
                    
            endcase	//state
        end	//if_block
    end	//always_block
endmodule