
module clockDiv(
    input clk,
    output reg out
    );

parameter scale = 5; // default divide by 2^5, max 15
reg r[15:0];

initial r = 0;
assign out = r[scale];

always @ (posedge clk) begin
    r = r + 1;
end
endmodule
