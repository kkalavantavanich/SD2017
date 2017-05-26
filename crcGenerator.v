`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/19/2017 11:15:00 AM
// Design Name: 
// Module Name: crcGenerator
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision: 1.02
// Revision 1.02 - CRC General generator and length
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// CRC Slave : should be used through CRC Master
// Clear > Enable
module crcGenerator 
#(parameter LEN = 7)(
    input inputBit,
    input clk,
    input clear,                
    input enable,               // will not activate on clk input
    input [LEN:0] generator,
    output reg [LEN - 1:0] crc
    );

wire invert;
assign invert = inputBit ^ crc[LEN - 1];
integer _i = 0;

always @ (posedge clk) begin
    if (clear) begin
        crc = 0;    
        end
    else if (enable) begin
        for (_i = LEN - 1; _i > 0; _i = _i - 1) begin
            crc[_i] = crc[_i - 1] ^ (invert & generator[_i]);  
        end
        crc[0] = invert;
    end
end

endmodule
