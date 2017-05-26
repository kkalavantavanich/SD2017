`timescale 1ns / 1ps
/* All files are owned by Kris Kalavantavanich. 
 * Feel free to use/modify/distribute in the condition that this copyright header is kept unmodified.
 * Github: https://github.com/kkalavantavanich/SD2017 */
//////////////////////////////////////////////////////////////////////////////////
// Create Date: 05/19/2017 12:40:27 PM
// Design Name: CRC Generator - Master
// Module Name: crcGenMaster
// Project Name: SD2017
// Target Devices: Basys3
// Revision: 1.02
// Revision 1.02 - General CRC generator and size
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// CRC-7 Generator 
module crcGenMaster # (
parameter bitLength = 40,
parameter crcLength = 7
)(
    clk,            // Clock 
    useModule,      // sync. CRC Slave will start on posedge and keeps crc until negedge 
    instream,       // input bit stream. length defined by parameter 'bitLength'. Should not change while useModule.
    generator,      // crc generator polynomial
    crc,            // crc value
    finish,         // sync. 1 = isFinished
    state           // {_start, _running, _waiting}, used for debugging
    );


// 'public' variables
input clk;
input useModule;
input [bitLength - 1:0] instream;
input [crcLength:0] generator;
output wire [crcLength - 1:0] crc;
output reg finish = 0;
output [2:0] state;

// 'private' variables
wire [crcLength - 1:0] _crc; 
reg _enable = 0, _clear = 1, _sync_enable; 
reg _start = 0, _running = 0, _waiting = 0;

reg [9:0] _i = 0; // loop index 
wire _datain;
assign _datain = _enable ? instream[_i] : 1'b0;

reg _sync_useModule;
reg [1:0] _edge_useModule;
assign crc = (_sync_useModule || _running ? _crc : {crcLength{1'bZ}});

reg [1:0] _error = 0;

// 'Private' Slave CRC Generator
crcGenerator c0 (_datain, clk, _clear, _sync_enable, generator, _crc);

always @ (posedge clk) begin
    if (_edge_useModule == 2'b01 && ~_start && ~_running && ~_waiting) begin
        // start condition
        finish  <= 0;
        _clear  <= 0;
        _enable <= 1;
        _start  <= 1; // state start & not running & not waiting
    end else if (_edge_useModule == 2'b11 && _start &&  _waiting) begin
        // end condition
        _start <= 0;  // state not start & not running & waiting
        _enable <= 0;
    end else if (_edge_useModule == 2'b11 && ~_start && _waiting) begin
        finish <= 1;
    end else if (_edge_useModule == 2'b10)  begin
        // unuse module
        finish  <= 0;
        _clear  <= 1;
        _enable <= 0;
    end else begin
        // => should not enter this always loop : rw/s, r/w/s, r/ws
        _error[0] = 1;
    end
end

// 'for loop'
always @ (posedge clk) begin 
    if (_start && ~_running && ~_waiting) begin
        // start loop with index i > 0 (doesn't handle i = 0)
        _running <= 1;
        _i = bitLength - 2;         // first bit is always 0 (sent in this if-block)
        if (_i == 0) begin
            // end loop condition
            _running <= 0;
            _waiting <= 1;
        end
    end else if (_start && _running & ~_waiting) begin
        // looping
        _i = _i - 1;
        if (_i == 1) begin          // signal delay to control block (this::line 60) compensation 
            // end loop condition
            _running <= 0;
            _waiting <= 1;
        end
    end else if (_start && _waiting) begin
        // do nothing if waiting
    end else begin
        // iff not started 
        _running = 0;
        _waiting = 0;
    end
end

assign state = {_start, _running, _waiting};

always @ (posedge clk) begin
    _sync_enable <= _enable;
end

always @ (posedge clk) begin
    _edge_useModule[1] <= _edge_useModule[0];
    _edge_useModule[0] <= useModule;
end

always @ (posedge clk) begin
    _sync_useModule <= useModule;
end

endmodule
