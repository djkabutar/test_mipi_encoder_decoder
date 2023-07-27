module bin2ascii(
	input wire [3:0] binary,
	output reg [7:0] ASCII_HEX
);
always@(binary)begin
    case(binary)
        4'h0 : ASCII_HEX = 8'h30;
        4'h1 : ASCII_HEX = 8'h31;
        4'h2 : ASCII_HEX = 8'h32;
        4'h3 : ASCII_HEX = 8'h33;
        4'h4 : ASCII_HEX = 8'h34;
        4'h5 : ASCII_HEX = 8'h35;
        4'h6 : ASCII_HEX = 8'h36;
        4'h7 : ASCII_HEX = 8'h37;
        4'h8 : ASCII_HEX = 8'h38;
        4'h9 : ASCII_HEX = 8'h39;
        4'hA : ASCII_HEX = 8'h41;
        4'hB : ASCII_HEX = 8'h42;
        4'hC : ASCII_HEX = 8'h43;
        4'hD : ASCII_HEX = 8'h44;
        4'hE : ASCII_HEX = 8'h45;
        4'hF : ASCII_HEX = 8'h46;
        default : ASCII_HEX = binary;
    endcase
end

endmodule