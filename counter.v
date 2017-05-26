`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/19/2017 08:59:36 AM
// Design Name: 
// Module Name: counter
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


module counter(
    clk,
    reset, // active high
    out,
    overflow
);
    
input clk, reset;
parameter bitSize = 8;
output reg [bitSize-1:0] out = 0;
output wire overflow;
parameter [bitSize-1:0] clearVal = {bitSize{1'b1}};
assign overflow = &out;

always @ (posedge clk) begin
    if (reset) out = 0;
    else if (out == clearVal) out = 0;
    else out = out + 1;
end

endmodule
