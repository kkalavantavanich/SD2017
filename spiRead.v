`timescale 1ns / 1ps
/* All files are owned by Kris Kalavantavanich. 
 * Feel free to use/modify/distribute in the condition that this copyright header is kept unmodified.
 * Github: https://github.com/kkalavantavanich/SD2017 */
//////////////////////////////////////////////////////////////////////////////////
// Creator: Kris Kalavantavanich (kkalavantavanich@gmail.com)
// Create Date: 05/20/2017 08:46:14 AM
// Design Name: SPI Read Module
// Module Name: spiRead
// Project Name: SD2017
// Target Devices: Basys3
// Revision: 1.02
// Revision 1.02 - Debug
// Revision 1.00 - Finished Read Operation
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module spiRead(
    spiClock,
    start,
    bitIn,
    finish,
    byteOut, 
    waitForBitIn
);
parameter outByteSize = 1;
// 'public' variables
input spiClock;
input start;
input bitIn;
output [(outByteSize * 8) - 1:0] byteOut;
output reg finish;
input waitForBitIn;

// 'private' variables  
wire _start;
assign _start = start;
reg _running = 0, _waiting = 0;

reg [(outByteSize * 8) - 1:0] inputBuffer = 0;
reg [outByteSize + 3:0] _i;
assign byteOut = _running ? 'bZ : inputBuffer;

reg _error = 0;

// main //
always @ (posedge spiClock) begin
    if (_start && ~_running && ~_waiting) begin
        // initial
        if (~waitForBitIn || ~bitIn) begin
            inputBuffer <= {{(outByteSize * 8 - 1){1'b0}}, bitIn};
            finish   <= 0;
            _running <= 1;
            _i <= (outByteSize * 8) - 1;                                    // Read the last 7 bits, first bit is always 0;
        end
    end else if (_start && _running && ~_waiting) begin
        // looping
        _i = _i - 1;
        inputBuffer <= {inputBuffer[(outByteSize * 8) - 2:0], bitIn};
        if (_i == 0) begin
            // end
            finish   <= 1;
            _running <= 0;
            _waiting <= 1;
        end
    end else if (_start && _waiting) begin
        //do nothing while waiting
    end else if (~_start) begin
        finish   <= 0;
        _waiting <= 0;
    end else begin
        _error = 1;
    end
end
endmodule
