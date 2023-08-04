module decoder (
    input           rx_pixel_clk,
    input [63:0]    mipi_rx_data,
    input           mipi_rx_valid,
    
    input           uart_fifo_re,
    
    output [7:0]    uart_data,
    output reg      uart_fifo_we = 0,
    output          uart_fifo_empty,
    output          debug_pin
);

parameter SOF = 48'hEA_FF_99_DE_AD_FF,
            EOF = 48'hEA_FF_99_DE_AD_AA;

localparam IDLE = 0,
            CHECK_SOF = 1,
            GET_METADATA = 2,
            GET_DATA = 3,
            CHECK_EOF = 4,
            CLEANUP = 5;

reg [2:0] mipi_rx_state = 0;
reg we_mipi_rx_fifo = 0;
reg [7:0] app_id = 0;
reg [23:0] mipi_dlen = 0;
reg [23:0] packet_cnt = 0;
reg [7:0] mask = 0;
reg fifo_rst = 1;

reg mipi_rx_fifo_re = 0;

wire [47:0] mipi_data_al;
wire mipi_rx_fifo_empty;
wire [47:0] mipi_rx_fifo_out_data;

wire [12:0] occupants;

reg [2:0] j = 0;

reg align_fifo_we = 0;
reg align_fifo_re = 0;
reg [2:0] align_state = 0;
reg [47:0] aligned_data = 0;
reg [47:0] temp_data = 0;

wire [47:0] align_fifo_out_data;
wire align_fifo_empty;

reg align_fifo_rst = 1;
reg [23:0] data_cnt = 0;

assign mipi_data_al = {
                        mipi_rx_data[7:0],
                        mipi_rx_data[15:8],
                        mipi_rx_data[23:16],
                        mipi_rx_data[31:24],
                        mipi_rx_data[39:32],
                        mipi_rx_data[47:40]
                    };
// assign mipi_data_al = mipi_rx_data[47:0];
                    
fifo #(
    .DATA_WIDTH(48),
    .ADDR_WIDTH(12)
) aligning_fifo (
    .clk(rx_pixel_clk),
    .rst_n(align_fifo_rst),
    .data_in(aligned_data),
    .we(align_fifo_we),
    .re(align_fifo_re),
    .data_out(align_fifo_out_data),
    .empty(align_fifo_empty)
);

always @(posedge rx_pixel_clk) begin
    if (mipi_rx_valid) begin
        case (align_state)
            0: begin
                if (mipi_data_al == SOF) begin
                    align_state <= 2;
                    j <= 0;
                    aligned_data <= mipi_data_al;
                    align_fifo_we <= 1;
                end else if (mipi_data_al[39:0] == SOF[47:8]) begin
                    j <= 1;
                    align_state <= 1;
                    temp_data[47:8] <= SOF[47:8];
                end else if (mipi_data_al[31:0] == SOF[47:16]) begin
                    j <= 2;
                    align_state <= 1;
                    temp_data[47:16] <= SOF[47:16];
                end else if (mipi_data_al[23:0] == SOF[47:24]) begin
                    j <= 3;
                    align_state <= 1;
                    temp_data[47:24] <= SOF[47:24];
                end else if (mipi_data_al[15:0] == SOF[47:32]) begin
                    j <= 4;
                    align_state <= 1;
                    temp_data[47:32] <= SOF[47:32];
                end else if (mipi_data_al[7:0] == SOF[47:40]) begin
                    j <= 5;
                    align_state <= 1;
                    temp_data[47:40] <= SOF[47:40];
                end
                align_fifo_rst <= 1'b1;
            end
            
            1: begin
                if ((mipi_data_al[47:40] == SOF[7:0]) && (j == 1)) begin
                    aligned_data <= {temp_data[47:8], mipi_data_al[47:40]};
                    temp_data[47:8] <= mipi_data_al[39:0];
                    data_cnt <= mipi_data_al[31:8];
                    align_fifo_we <= 1;
                    align_state <= 2;
                end
                else if ((mipi_data_al[47:32] == SOF[15:0]) && (j == 2)) begin
                    aligned_data <= {temp_data[47:16], mipi_data_al[47:32]};
                    temp_data[47:16] <= mipi_data_al[31:0];
                    data_cnt <= mipi_data_al[23:0];
                    align_fifo_we <= 1;
                    align_state <= 2;
                end
                else if ((mipi_data_al[47:24] == SOF[23:0]) && (j == 3)) begin
                    aligned_data <= {temp_data[47:24], mipi_data_al[47:24]};
                    temp_data[47:24] <= mipi_data_al[23:0];
                    data_cnt[23:8] <= mipi_data_al[15:0];
                    align_fifo_we <= 1;
                    align_state <= 2;
                end
                else if ((mipi_data_al[47:16] == SOF[31:0]) && (j == 4)) begin
                    aligned_data <= {temp_data[47:32], mipi_data_al[47:16]};
                    temp_data[47:32] <= mipi_data_al[15:0];
                    data_cnt[23:16] <= mipi_data_al[7:0];
                    align_fifo_we <= 1;
                    align_state <= 2;
                end
                else if ((mipi_data_al[47:8] == SOF[39:0]) && (j == 5)) begin
                    aligned_data <= {temp_data[47:40], mipi_data_al[47:8]};
                    temp_data[47:40] <= mipi_data_al[7:0];
                    align_fifo_we <= 1;
                    align_state <= 2;
                end else begin
                    align_fifo_we <= 0;
                    align_state <= 0;
                end
            end
            
            2: begin
                case (j)
                    0: begin
                        aligned_data <= mipi_data_al;
                        data_cnt <= mipi_data_al[39:16];
                        align_state <= 3;
                        align_fifo_we <= 1;
                    end
                    
                    1: begin
                        aligned_data <= {temp_data[47:8], mipi_data_al[47:40]};
                        temp_data[47:8] <= mipi_data_al[39:0];
                        align_state <= 3;
                        align_fifo_we <= 1;
                    end
                    
                    2: begin
                        aligned_data <= {temp_data[47:16], mipi_data_al[47:32]};
                        temp_data[47:16] <= mipi_data_al[31:0];
                        align_state <= 3;
                        align_fifo_we <= 1;
                    end
                    
                    3: begin
                        aligned_data <= {temp_data[47:24], mipi_data_al[47:24]};
                        temp_data[47:24] <= mipi_data_al[23:0];
                        data_cnt[7:0] <= mipi_data_al[47:40];
                        align_state <= 3;
                        align_fifo_we <= 1;
                    end
                    
                    4: begin
                        aligned_data <= {temp_data[47:32], mipi_data_al[47:16]};
                        temp_data[47:32] <= mipi_data_al[15:0];
                        data_cnt[15:0] <= mipi_data_al[47:32];
                        align_state <= 3;
                    end
                    
                    5: begin
                        aligned_data <= {temp_data[47:40], mipi_data_al[47:8]};
                        temp_data[47:40] <= mipi_data_al[7:0];
                        data_cnt <= mipi_data_al[47:24];
                        align_state <= 3;
                        align_fifo_we <= 1;
                    end
                endcase
            end
            
            3: begin
                case (j)
                    0: begin
                        aligned_data <= mipi_data_al;
                        if (data_cnt == 0) begin
                            if (mipi_data_al == EOF) begin
                                align_state <= 5;
                                align_fifo_we <= 1;
                            end else begin
                                align_state <= 0;
                                align_fifo_we <= 0;
                                align_fifo_rst <= 0;
                            end
                        end else begin
                            data_cnt <= data_cnt - 1;
                            align_fifo_we <= 1;
                        end
                    end

                    1: begin
                        aligned_data <= {temp_data[47:8], mipi_data_al[47:40]};
                        temp_data[47:8] <= mipi_data_al[39:0];

                        if (data_cnt == 1) begin
                            if (mipi_data_al[39:0] == EOF[47:8]) begin
                                align_state <= 4;
                                align_fifo_we <= 1;
                            end else begin
                                align_state <= 0;
                                align_fifo_we <= 0;
                                align_fifo_rst <= 0;
                            end
                        end else begin
                            data_cnt <= data_cnt - 1;
                            align_fifo_we <= 1;
                        end
                    end

                    2: begin
                        aligned_data <= {temp_data[47:16], mipi_data_al[47:32]};
                        temp_data[47:16] <= mipi_data_al[31:0];

                        if (data_cnt == 1) begin
                            if (mipi_data_al[31:0] == EOF[47:16]) begin
                                align_state <= 4;
                                align_fifo_we <= 1;
                            end else begin
                                align_state <= 0;
                                align_fifo_we <= 0;
                                align_fifo_rst <= 0;
                            end
                        end else begin
                            data_cnt <= data_cnt - 1;
                            align_fifo_we <= 1;
                        end
                    end
                    
                    3: begin
                        aligned_data <= {temp_data[47:24], mipi_data_al[47:24]};
                        temp_data[47:24] <= mipi_data_al[23:0];

                        if (data_cnt == 1) begin
                            if (mipi_data_al[23:0] == EOF[47:24]) begin
                                align_state <= 4;
                                align_fifo_we <= 1;
                            end else begin
                                align_state <= 0;
                                align_fifo_we <= 0;
                                align_fifo_rst <= 0;
                            end
                        end else begin
                            data_cnt <= data_cnt - 1;
                            align_fifo_we <= 1;
                        end
                    end

                    4: begin
                        aligned_data <= {temp_data[47:32], mipi_data_al[47:16]};
                        temp_data[47:32] <= mipi_data_al[15:0];

                        if (data_cnt == 1) begin
                            if (mipi_data_al[15:0] == EOF[47:32]) begin
                                align_state <= 4;
                                align_fifo_we <= 1;
                            end else begin
                                align_state <= 0;
                                align_fifo_we <= 0;
                                align_fifo_rst <= 0;
                            end
                        end else begin
                            data_cnt <= data_cnt - 1;
                            align_fifo_we <= 1;
                        end
                    end

                    5: begin
                        aligned_data <= {temp_data[47:40], mipi_data_al[47:8]};
                        temp_data[47:40] <= mipi_data_al[7:0];

                        if (data_cnt == 1) begin
                            if (mipi_data_al[7:0] == EOF[47:40]) begin
                                align_state <= 4;
                                align_fifo_we <= 1;
                            end else begin
                                align_state <= 0;
                                align_fifo_we <= 0;
                                align_fifo_rst <= 0;
                            end
                        end else begin
                            data_cnt <= data_cnt - 1;
                            align_fifo_we <= 1;
                        end
                    end
                endcase
            end
            
            4: begin
                case(j)
                    1: begin
                        aligned_data <= {temp_data[47:8], mipi_data_al[47:40]};
                        
                        if (mipi_data_al[47:40] == EOF[7:0]) begin
                            align_state <= 5;
                            align_fifo_we <= 1;
                        end else begin
                            align_state <= 0;
                            align_fifo_we <= 0;
                            align_fifo_rst <= 0;
                        end
                    end
                    
                    2: begin
                        aligned_data <= {temp_data[47:16], mipi_data_al[47:32]};
                        
                        if (mipi_data_al[47:32] == EOF[15:0]) begin
                            align_state <= 5;
                            align_fifo_we <= 1;
                        end else begin
                            align_state <= 0;
                            align_fifo_we <= 0;
                            align_fifo_rst <= 0;
                        end
                    end
                    
                    3: begin
                        aligned_data <= {temp_data[47:24], mipi_data_al[47:24]};
                        
                        if (mipi_data_al[47:24] == EOF[23:0]) begin
                            align_state <= 5;
                            align_fifo_we <= 1;
                        end else begin
                            align_state <= 0;
                            align_fifo_we <= 0;
                            align_fifo_rst <= 0;
                        end
                    end
                    
                    4: begin
                        aligned_data <= {temp_data[47:32], mipi_data_al[47:16]};
                        
                        if (mipi_data_al[47:16] == EOF[31:0]) begin
                            align_state <= 5;
                            align_fifo_we <= 1;
                        end else begin
                            align_state <= 0;
                            align_fifo_we <= 0;
                            align_fifo_rst <= 0;
                        end
                    end
                    
                    5: begin
                        aligned_data <= {temp_data[47:40], mipi_data_al[47:8]};
                        
                        if (mipi_data_al[47:8] == EOF[39:0]) begin
                            align_state <= 5;
                            align_fifo_we <= 1;
                        end else begin
                            align_state <= 0;
                            align_fifo_we <= 0;
                            align_fifo_rst <= 0;
                        end
                    end
                endcase
            end
            
            5: begin
                align_fifo_we <= 0;
                align_state <= 0;
            end
            
            default: begin
                align_state <= 0;
            end
        endcase
    end else begin
        align_fifo_we <= 0;
    end
end

fifo #(
    .DATA_WIDTH(48),
    .ADDR_WIDTH(12)
) mipi_rx_fifo (
    .clk(rx_pixel_clk),
    .rst_n(fifo_rst),
    .data_in(align_fifo_out_data),
    .we(we_mipi_rx_fifo),
    .re(mipi_rx_fifo_re),
    .data_out(mipi_rx_fifo_out_data),
    .empty(mipi_rx_fifo_empty),
    .occupants(occupants)
);

udg u1 (
    .clk(rx_pixel_clk),
    .rst(1'b1),
    .fifo_we(align_fifo_re),
    .data_in(align_fifo_out_data),
    .tx(debug_pin),
    .full()
);

always @(posedge rx_pixel_clk) begin
    case (mipi_rx_state)
        IDLE: begin
            if (~align_fifo_empty & ~align_fifo_we & align_fifo_rst) begin
                align_fifo_re <= 1;
                mipi_rx_state <= 7;
            end
        end
        
        7: begin
            mipi_rx_state <= CHECK_SOF;
        end
        
        CHECK_SOF: begin
            if (align_fifo_out_data == SOF) begin
                mipi_rx_state <= GET_METADATA;
            end else begin
                mipi_rx_state <= IDLE;
            end
        end
        
        GET_METADATA: begin
            app_id <= align_fifo_out_data[47:40];
            mipi_dlen <= align_fifo_out_data[39:16];
            mask <= align_fifo_out_data[15:8];
            packet_cnt <= align_fifo_out_data[39:16];
            mipi_rx_state <= GET_DATA;
            we_mipi_rx_fifo <= 1;
        end
        
        GET_DATA: begin
            if (packet_cnt == 0) begin
                mipi_rx_state <= CHECK_EOF;
            end else if (packet_cnt == 1) begin
                align_fifo_re <= 1'b0;
                packet_cnt <= packet_cnt - 1;
                we_mipi_rx_fifo <= 0;       
            end else begin
                packet_cnt <= packet_cnt - 1;
            end
        end
        
        CHECK_EOF: begin
            if (align_fifo_out_data == EOF) begin
                mipi_rx_state <= CHECK_SOF;
            end else begin
                mipi_rx_state <= CLEANUP;
                fifo_rst <= 1'b0;
            end
        end
        
        CLEANUP: begin
            fifo_rst <= 1'b1;
            mipi_rx_state <= CHECK_SOF;
        end
        
        default: begin
            mipi_rx_state <= IDLE;
        end
    endcase
end

localparam IDLE_UART = 0,
            FIRST_DATA = 1,
            FILL_DATA = 2;

reg [2:0] uart_tx_state = 0;
reg [7:0] uart_fifo_data_in = 0;
reg [2:0] cnt = 0;

wire [7:0] uart_fifo_data_out = 0;

wire [7:0] data_to_process = mask == 1 ? 1 : (mask == 3 ? 2 : 
                             (mask == 7 ? 3 : (mask == 15 ? 4 : 
                             (mask == 31 ? 5 : 6))));

fifo #(
    .DATA_WIDTH(8),
    .ADDR_WIDTH(12)
) uart_fifo (
    .clk(rx_pixel_clk),
    .rst_n(1'b1),
    .data_in(uart_fifo_data_in),
    .we(uart_fifo_we),
    .re(uart_fifo_re),
    .data_out(uart_data),
    .empty(uart_fifo_empty)
);

always @(posedge rx_pixel_clk) begin
    case (uart_tx_state)
        IDLE_UART: begin
            if (~mipi_rx_fifo_empty & ~we_mipi_rx_fifo) begin
                mipi_rx_fifo_re <= 1'b1;
                cnt <= occupants == 1 ? data_to_process : 6;
                uart_tx_state <= FIRST_DATA;
            end
        end
        
        FIRST_DATA: begin
            mipi_rx_fifo_re <= 1'b0;
            // uart_fifo_data_in <= mipi_rx_fifo_out_data[(cnt * 8) - 1 -: 8];
            uart_tx_state <= FILL_DATA;
            // cnt <= cnt - 1;
        end
        
        FILL_DATA: begin
            if (cnt == 0) begin
                uart_fifo_we <= 0;
                uart_tx_state <= IDLE_UART;
            end else begin
                cnt <= cnt - 1;
                uart_fifo_data_in <= mipi_rx_fifo_out_data[(cnt * 8) - 1 -: 8];
                uart_fifo_we <= 1;
            end
        end
        
        default: begin
            uart_tx_state <= 0;
        end
    endcase
end

endmodule