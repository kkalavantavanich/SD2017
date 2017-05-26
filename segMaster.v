`timescale 1ns / 1ps
/* All files are owned by Kris Kalavantavanich. 
 * Feel free to use/modify/distribute in the condition that this copyright header is kept unmodified.
 * Github: https://github.com/kkalavantavanich/SD2017 */
//////////////////////////////////////////////////////////////////////////////////
// Create Date: 05/19/2017 06:09:53 PM
// Design Name: Seven Segment Master
// Module Name: segMaster
// Project Name: SD2017
// Description: This module receives an 4-digit hexadecimal number and displays it.
// DP is set "ON" when Invalid number received.
// Target Devices: Basys3
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module segMaster(
    input clk,
    input [15:0] num,
    input [3:0] aen, // high = disable digit n
    output [6:0] seg,
    output [3:0] an,
    output dp
);
reg [2:0] ctr = 0;
wire [1:0] i;
assign i = ctr [2:1];
wire [3:0] BCD;
assign BCD = (i == 0 ? num[3:0] : (i == 1 ? num[7:4] :(i == 2 ? num[11:8] : num[15:12] )));
                      
reg [7:0] SevenSeg;

always @ (posedge clk)
case(BCD)
    4'h0: SevenSeg = 8'b11000000;
    4'h1: SevenSeg = 8'b11111001;
    4'h2: SevenSeg = 8'b10100100;
    4'h3: SevenSeg = 8'b10110000;
    4'h4: SevenSeg = 8'b10011001;
    4'h5: SevenSeg = 8'b10010010;
    4'h6: SevenSeg = 8'b10000010;
    4'h7: SevenSeg = 8'b11111000;
    4'h8: SevenSeg = 8'b10000000;
    4'h9: SevenSeg = 8'b10010000;
    4'hA: SevenSeg = 8'b10001000;
    4'hB: SevenSeg = 8'b10000011;
    4'hC: SevenSeg = 8'b11000110;
    4'hD: SevenSeg = 8'b10100001;
    4'hE: SevenSeg = 8'b10000110;
    4'hF: SevenSeg = 8'b10001110;
 default: SevenSeg = 8'b01111111;
endcase

assign {dp, seg[6:0]} = SevenSeg;

always @ (posedge clk) begin
    ctr = ctr + 1;
end

assign an[3] = aen[3] || ~ctr[0] || ~(i == 3);
assign an[2] = aen[2] || ~ctr[0] || ~(i == 2);
assign an[1] = aen[1] || ~ctr[0] || ~(i == 1);
assign an[0] = aen[0] || ~ctr[0] || ~(i == 0);

endmodule
