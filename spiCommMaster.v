`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Creator: Kris Kalavantavanich (kkalavantavanich@gmail.com)
// Create Date: 05/22/2017 08:17:18 PM
// Design Name: SPI Communication Master
// Module Name: spiCommMaster
// Project Name: SD_2017
// Target Devices: Basys3
// Description: 
// 
// Dependencies: main.v
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// - Doesn't interpret response -- (Master of this)'s job.
// - All signals are synchronous (including reset). Reset without clock means nothing.
// --- Except enable signal
//////////////////////////////////////////////////////////////////////////////////

module spiCommMaster(
    input cpuClock,             // CPU Clock Input
    input enable,               // If LOW => all outputs will be Z (high impedence) (Active HIGH)
    input reset,                // IF HIGH => Reset to ST_IDLE (Active HIGH)
    input spiClockEn,           // Enable SPI Clock (SD_SDLK) (Active HIGH)
    
    output errorInterrupt,      // HIGH <= Error has occurred
    output [3:0] errorType,     // output the type of error
    output [3:0] errorState,    // output the last error if an error occurs
    
    input cmdTransmitBit,       // Transmit bit of CMD (second MSB of CMD)
    input [5:0] cmdIndex,       // CMD Index
    input [31:0] cmdArgument,   // CMD Argument(s)
    
    input [1:0] readMode,       // Reading Mode (00 = readSingle, 01 = readDouble, 10 = readWide, 11 = reserved)
    output [39:0] readResponse, // Response of Slave SPI Device. If response is less than 40-bits, response is aligned right and left-filled with 0.
    
    input commStart,            // (Signal) Start Communication Cycle from ST_IDLE. posedge = Start, negedge = Stop.
    output commFinish,          // (Signal) Finished Communication Cycle and waiting for Response to be fetched. HIGH only if ST_FINISH. 
    
    input SD_MISO,              // SD Master In Slave Out
    input SD_CD,                // SD Chip Detected
    input SD_WP,                // SD Write Protect
    output SD_SCLK,             // SD SPI Clock (Controlled only with spiClockEn; not by enable)
    output SD_MOSI,             // SD Master Out Slave In
    output SD_CS                // SD Chip Select
);

// Common Acronyms //
// ST = State
// STA = Start
// STO = Stop
// EN = Enable (out value or high impedence)
// RST = Reset 
// FIN = Finished
// OUT = wire data out
// BUFF = reg data

// DEFINE CONSTANTS //
localparam ST_IDLE       = 4'b0000;  // Wait for `commStart` HIGH
localparam ST_GEN_CRC    = 4'b0010;  // Wait for previous cooldown and start CRC Generation
localparam ST_SEND       = 4'b0100;  // Wait for CRC generation and start sending
localparam ST_READ       = 4'b0110;  // Wait for Sending finish and start reading
localparam ST_INPUT      = 4'b1000;  // Wait for Reading
localparam ST_COOLDOWN   = 4'b1010;  // Cooldown Requied (does nothing)
localparam ST_FINISH     = 4'b1100;  // Finish and wait for `commStart` LOW
localparam ST_ERROR      = 4'b1111;  // Error state

localparam ER_UNKN       = 4'b0000;  // No Error / Unknown Error
localparam ER_IVST       = 4'b0001;  // Invalid State Error
localparam ER_TMOT       = 4'b0010;  // Timeout Error
localparam ER_RESP       = 4'b0100;  // Response Error
localparam ER_UDEV       = 4'b0110;  // Unknown Device Error

// STATE //
reg [3:0] CST = ST_IDLE;  // Current State
reg [3:0] NST = ST_IDLE;  // Next State

// ERRORS //
reg EINT = 0;             // Error Interrupt    
reg EINTE = 1;            // Error Interrupt Enable
reg [3:0] EST = 0;        // Internal Error State (State before ST_ERROR)
reg [3:0] ETYPE = 0;      // Error Type
assign errorInterrupt = enable ? (EINTE ? EINT : 1'b0) : 1'bZ;
assign errorType = enable ? ETYPE : 4'bZ;
assign errorState = enable ? EST : 4'bZ;

// BUFFERED ENABLE OUTPUTS //
wire [39:0] readData;                                        // Internal Read Response Wiring
assign readResponse = enable ? readData : 40'bZ;
wire MOSI;                                                   // MOSI Data
reg MOSI_EN = 0;                                             // MOSI Enable (Active HIGH)
assign SD_MOSI = enable ? (MOSI_EN ? MOSI : 1'b1): 1'bZ;
reg CS = 1;                                                  // Chip Select (Active LOW)
assign SD_CS = enable ? CS : 1'bZ;
assign commFinish = (CST == 4'b1100);

// SPI CLOCK //
wire spiClock, _spiClock;                     // _spiClock is without enable, spiClock is with enable
clockDiv #(8) SPICLKM (cpuClock, _spiClock);       // run _spiClock at 390.6 kHz
//clockDiv #(9) c4(cpuClock, _spiClock);      // run _spiClock at 195.3 kHz
assign spiClock = (spiClockEn && enable) ? _spiClock : 1; // spiClock is active low
assign SD_SCLK = (spiClockEn ? _spiClock : 1);

// SPI TIMEOUT COUNTER (TMTO)//
localparam TMTO_bitSize = 16;
reg TMTO_RST = 1;
wire [TMTO_bitSize-1 :0] TMTO_OUT;
wire TMTO_OV;
wire [TMTO_bitSize-1 :0] TMTO_VAL;   // Value for timeout
wire TMTO_TOI;                       // Timeout Interrupt
assign TMTO_TOI = (TMTO_OUT >= TMTO_VAL);
counter #(TMTO_bitSize) TMTOM (_spiClock, TMTO_RST, TMTO_OUT, TMTO_OV);

// SPI COOLDOWN COUNTER (TMWC)// 
localparam TMWC_bitSize = 4;
reg TMWC_RST = 1;
wire [TMWC_bitSize-1 :0] TMWC_OUT;
wire TMWC_OV;          // set whether cooldown timer finished
wire TMWC_MSB;         // set whether SD_CS is on
assign TMWC_MSB = TMWC_OUT[TMWC_bitSize - 1];
counter #(TMWC_bitSize) TMWCM (_spiClock, TMWC_RST, TMWC_OUT, TMWC_OV);

// COMMANDS // 
// Constructed from (Inputs to Module)
wire [5:0] CMD_INDEX;      // Command Index (CMD0 - CMD63)
wire [31:0] CMD_ARG;       // 32-bit Command Argument
wire [6:0] CMD_CRC;        // CRC-7 Code
wire CMD_TRANSMIT;         // 0 => Receiver, 1 => Transmitter
wire [47:0] CMD;           // 48-bit command
assign CMD_INDEX = cmdIndex;
assign CMD_ARG = cmdArgument;
assign CMD_TRANSMIT = cmdTransmitBit;
assign CMD = {1'b0, CMD_TRANSMIT, CMD_INDEX, CMD_ARG, CMD_CRC, 1'b1};

// SPI SEND (SPS) //
reg SPS_STA = 0;
reg [47:0] SPS_BUFF;
wire SPS_FIN;
spiSend SPSM (spiClock, SPS_STA, SPS_BUFF, MOSI, SPS_FIN);

// SPI READ (SPR) //

// Normal Response (Single Byte) (SPRS)
reg SPRS_STA = 0;                        // SPRSM Start
wire [7:0] SPRS_OUT;                     // Output from SPRSM (Can be high impedence)
wire SPRS_FIN;                           // SPRSM Finish
spiRead SPRSM (spiClock, SPRS_STA, SD_MISO, SPRS_FIN, SPRS_OUT);

// Double Byte Response (Double Byte) (SPRD)
reg SPRD_STA = 0;   
wire [15:0] SPRD_OUT;         
wire SPRD_FIN;
spiRead #(2) SPRDM (spiClock, SPRD_STA, SD_MISO, SPRD_FIN, SPRD_OUT);

// Wide Response (R3 / R7) -- 5 bytes (R1 + Rn) (SPRW)
reg SPRW_STA = 0;
wire [39:0] SPRW_OUT;
wire SPRW_FIN;
spiRead #(5) SPRWM (spiClock, SPRW_STA, SD_MISO, SPRW_FIN, SPRW_OUT);

// SPI Reading -- Common //
wire SPR_FIN;
assign SPR_FIN = (readMode == 2'b00 ? SPRS_FIN : (readMode == 2'b01 ?  SPRD_FIN : SPRW_FIN));
reg [39:0] SPR_BUFF;
assign readData = SPR_BUFF;
assign TMTO_VAL = (readMode == 2'b00 ? 100 : (readMode == 2'b01 ? 200 : 500));

// 'Response' CRC-7 (CRCR) // 
// uses CPU CLOCK
wire [39:0] CRCR_IN;
reg CRCR_EN = 0;
wire CRCR_FIN;
wire [6:0] CRCR_OUT;
wire [2:0] CRCR_ST;
crcGenMaster CRCRM (cpuClock, CRCR_EN, CRCR_IN, CRCR_OUT, CRCR_FIN, CRCR_ST);
assign CRCR_IN = {1'b0, CMD_TRANSMIT, CMD_INDEX, CMD_ARG};
assign CMD_CRC = CRCR_OUT;

// 'Data CRC-16 (CRCD) //



// MAIN STATE MACHINE //
always @ (posedge cpuClock) begin
    if (reset) begin
        NST <= ST_IDLE;     // Set Next State to IDLE
        
        EINT <= 0;          // Clear Error Interrupt
        ETYPE <= 0;         // Clear Error Type
        EST <= 0;           // Clear Error State
        
        MOSI_EN <= 0;       // Disable MOSI
        CS <= 1;            // Disable Chip Select
        
        TMTO_RST <= 1;      // Stop Timeout Timer
        TMWC_RST <= 1;      // Stop Warmup/Cooldown Timer
        
        SPS_STA  <= 0;      // Stop Sending (SPS)
        SPS_BUFF <= 0;      // Clear Sending Buffer
        
        SPRS_STA <= 0;      // Stop Reading Single
        SPRD_STA <= 0;      // Stop Reading Double
        SPRW_STA <= 0;      // Stop Reading Wide
        SPR_BUFF <= 0;      // Clear Reading Buffer
        
        CRCR_EN  <= 0;      // Disable CRC-7 Generation
    end else begin
        case (CST)
            ST_IDLE: begin
                if (commStart) begin
                    NST <= ST_GEN_CRC;
                end
            end
            ST_GEN_CRC: begin // Start CRC generation if previous cooldown finished. CMD data *must* be stable and complete.
                if (!TMWC_OV) begin
                    CS       <= 1;       // CS HIGH before warmup
                    TMWC_RST <= 0;       // Start warmup/cooldown timer
                    CRCR_EN  <= 1;       // Start CRC7 generation
                    NST      <= ST_SEND; // goto 'send' state
                end
            end
            ST_SEND: begin  // Wait for CRC generation/warmup and start sending.
                if (CRCR_FIN && TMWC_OV) begin
                    TMWC_RST <= 1;       // Stop warmup/cooldown timer
                    CS       <= 0;       // Chip Select Must be LOW
                    SPS_STA  <= 1;       // Start Sending
                    SPS_BUFF <= CMD;     // Copy CMD to SPS Internal Buffer
                    MOSI_EN  <= 1;       // Enable MOSI
                    CRCR_EN  <= 0;       // Stop CRC7 generation
                    NST      <= ST_READ; // goto 'read' state
                end else begin
                    CS <= ~TMWC_MSB;     // Set CS to be half HIGH, half LOW for TMWC duration
                end
            end
            ST_READ: begin  // Wait for sending and start reading.
                if (SPS_FIN) begin
                    SPS_STA   <= 0;     // Stop Sending
                    MOSI_EN   <= 0;     // Disable MOSI
                    TMTO_RST  <= 0;     // Start timeout timer (TMTO)
                    case (readMode)     // Start Reader
                        2'b00:   SPRS_STA <= 1;
                        2'b01:   SPRD_STA <= 1;
                        default: SPRW_STA <= 1;
                    endcase
                    NST <= ST_INPUT;
                end
            end
            ST_INPUT: begin // Wait for Reading 
                if (TMTO_TOI) begin
                    NST <= ST_ERROR;
                    ETYPE <= ER_TMOT;    // Timeout Error
                    EINT  <= 1;          // Raise Error Interrupt
                    EST   <= CST;        // Store Error State
                end else if (SPR_FIN) begin
                    TMTO_RST <= 1;       // Stop Timeout Timer
                    TMWC_RST <= 0;       // Start Cooldown Timer
                    case (readMode)      // Copy data out to buffer
                        2'b00:   SPR_BUFF <= {32'b0, SPRS_OUT};
                        2'b01:   SPR_BUFF <= {24'b0, SPRD_OUT};
                        default: SPR_BUFF <= SPRW_OUT;
                    endcase
                    case (readMode)      // Stop Readers
                        2'b00:   SPRS_STA <= 0;
                        2'b01:   SPRD_STA <= 0;
                        default: SPRW_STA <= 0;
                    endcase
                    NST <= ST_COOLDOWN;  // goto `cooldown` state
                end
            end
            ST_COOLDOWN: begin
                if (TMWC_OV) begin
                    TMWC_RST <= 1;      // Stop Cooldown Timer
                    CS <= 1;            // CS HIGH After cooldown
                    NST <= ST_FINISH;   // goto `finish` state
                end else begin
                    CS <= TMWC_MSB;     // Set value of CS to be half LOW, half HIGH during TMWC duration
                end
            end
            ST_FINISH: begin    // Finished Comm Cycle State. Waiting for start LOW
                if (!commStart) begin
                    NST <= ST_IDLE;
                end
            end
            ST_ERROR: begin     // Error State. Will stay in this state until `reset` HIGH
                
            end
            default: begin
                NST   <= ST_ERROR;
                ETYPE <= ER_IVST;
                EST   <= 0;
            end
        endcase
    end
end // MAIN STATE MACHINE//

always @ (posedge cpuClock) begin
    CST <= NST;
end

endmodule
