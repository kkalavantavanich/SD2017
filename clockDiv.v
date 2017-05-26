/* All files are owned by Kris Kalavantavanich. 
 * Feel free to use/modify/distribute in the condition that this copyright header is kept unmodified.
 * Github: https://github.com/kkalavantavanich/SD2017 */

`timescale 1ns / 1ps
module clockDiv(
    input clk,
    output out
    );

parameter scale = 5; // default divide by 2^5, max 20
reg [scale:0] r;

initial r = 0;
assign out = r[scale];

always @ (posedge clk) begin
    r = r + 1;
end
endmodule
