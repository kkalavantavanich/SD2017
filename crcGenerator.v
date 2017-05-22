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
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// CRC Slave : should be used through CRC Master
// Clear > Enable
module crcGenerator(
    input inputBit,
    input clk,
    input clear,
    input enable,
    output reg [6:0] crc
    );

wire invert;
assign invert = inputBit ^ crc[6];

always @ (posedge clk) begin
    if (clear) begin
        crc = 0;    
        end
    else if (enable) begin
        crc[6] = crc[5];
        crc[5] = crc[4];
        crc[4] = crc[3];
        crc[3] = crc[2] ^ invert;
        crc[2] = crc[1];
        crc[1] = crc[0];
        crc[0] = invert;
    end
end


endmodule
