`timescale 1ns / 1ps
/* All files are owned by Kris Kalavantavanich. 
 * Feel free to use/modify/distribute in the condition that this copyright header is kept unmodified.
 * Github: https://github.com/kkalavantavanich/SD2017 */
//////////////////////////////////////////////////////////////////////////////////
// Create Date: 05/19/2017 08:59:36 AM
// Design Name: Counter 
// Module Name: counter
// Project Name: SD2017
// Target Devices: Basys3
// Dependencies:
// Revision: 0.01
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
