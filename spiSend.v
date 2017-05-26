`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/19/2017 10:23:10 PM
// Design Name: SPI_SEND
// Module Name: spiSend
// Project Name: SD_2017
// Target Devices: Xilinx Basys3
// Description: Submodule of main.v. Send 48-bit cmd command `CMD`. Output is in `bitout`.
// Sending process will start on `start` HIGH (synchronous with negedge)
// Process finish is notified by `finish` HIGH (synchronous with negedge)
// Dependencies: main.v
// Revision: 1.00
// Revision 1.00 - Finished Read Operation
// Revision 0.01 - File Created
// Additional Comments: SET ON NEGEDGE!!!!
//////////////////////////////////////////////////////////////////////////////////


module spiSend(
    spiClock,
    start,
    cmd,
    bitout,
    finish
);
parameter byteSize = 6;

// 'public' variables
input spiClock;
input start;
input [(byteSize * 8) - 1:0] cmd;
output bitout;
output reg finish;

// 'private' variables  
wire _start;
assign _start = start;
reg _running = 0, _waiting = 0;

reg [(byteSize * 8) - 1:0] _cmdBuffer;
reg [byteSize - 1:0]       _i;
assign bitout = _running ? _cmdBuffer[47] : 1'b1;   /// active low

reg _error = 0;


// main //
always @ (negedge spiClock) begin
    if (_start && ~_running && ~_waiting) begin
        // initial
        finish   <= 0;
        _cmdBuffer <= cmd; // cmd always start with 0
        _running <= 1;
        _i <= 47; // this loop sends a `0`
    end else if (_start && _running && ~_waiting) begin
        // looping
        _i = _i - 1;
        _cmdBuffer = _cmdBuffer << 1;
        if (_i == 0) begin
            // end
            _running <= 0;
            _waiting <= 1;
        end
    end else if (_start && _waiting) begin
        finish   <= 1;
    end else if (~_start) begin
        finish   <= 0;
        _waiting <= 0;
    end else begin
        _error = 1;
    end
end
endmodule
