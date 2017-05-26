`timescale 1ns / 1ps
/* All files are owned by Kris Kalavantavanich. 
 * Feel free to use/modify/distribute in the condition that this copyright header is kept unmodified.
 * Github: https://github.com/kkalavantavanich/SD2017 */
//////////////////////////////////////////////////////////////////////////////////
// Create Date: 05/18/2017 11:17:30 PM
// Design Name: Main SD Module
// Module Name: main
// Project Name: SD2017
// Target Devices: Basys3
// Revision: 1.21
// Revisiom 1.21 - Complete CRCD (CRC-16 Data In)
// Revision 1.20 - Added UBADDR + (partial CRCD)
// Revision 1.10 - Branched from Revision 1.07 (remove v1.08)
// Revision 1.07 - Replaced RD Communication State Logic with main state logic
// Revision 1.06 - Debug
// Revision 1.05 - Debug
// Revision 1.04 - Debug
// Revision 1.03 - Debug
// Revision 1.02 - Debug
// Revision 1.01 - Removed led[3:0] output due to synthesis error
// Revision 1.00 - Finished Read Operation
// Revision 0.01 - File Created
// Additional Comments:
//
// KNOWN BUGS //
//
// F_CPU = 100000000 (100 MHz)
// F_SPI = 390625    (390.6 kHz)
//////////////////////////////////////////////////////////////////////////////////
// SPI Connection:
// PIN1 = Data[0] = JA[0] = 7 = MISO
// PIN2 = Data[1] = JA[1] = 8
// PIN3 = Data[2] = JA[2] = 9 
// PIN4 = Data[3] = JA[3] = 1 = CS (active low)
// PIN7 = CLK     = JA[4] = 5 = CLK
// PIN8 = CMD     = JA[5] = 2 = MOSI
// PIN9 = CD      = JA[6]
// PIN10 = WP     = JA[7]

module main(
    input _cpuClock,
    input [15:0] sw,
    
    input btnC, 
    input btnU, 
    input btnD, 
    input btnL, 
    input btnR,
    
    output [15:0] led,
    
    output [6:0] seg,
    output dp,
    output [3:0] an,
    
    input  SD_MISO, SD_CD, SD_WP,
    output SD_CLK, SD_MOSI, SD_CS
    ,
    input [31:0] UBDI, // Data In from MB
    output [31:0] UBDO, // Data Out to MB
    output UBEO, // Error Out to MB (Active HIGH)
    output UBRRI, // ReadReadyInterrupt to MB (Active HIGH)
    input UBRRA, // ReadReadyAcknowledge from MB (Active HIGH)
    input UBRM,  // read mode 
    input UBWM,  // write mode
    input [31:0] UBADDR // Block Address
);
// CPU CLOCK PRESCALER //
localparam PRESCALE = 8;                          // Use to slowdown CPU CLOCK 
wire cpuClock;
//clockDiv #(PRESCALE) c00 (_cpuClock, cpuClock);   // Slowed     (Debugging)
assign cpuClock = _cpuClock;                    // Not Slowed (Normal Operation)

// RESET BUTTON //
wire globalReset;
assign globalReset = btnU || btnC;

// ERROR REGISTER //
reg [7:0] _errorState = 0;                      // Last state before error occured
wire _errorNoti;

// COMMANDS //
reg [5:0] CMD_INDEX;      // Command Index (CMD0 - CMD63)
reg [31:0] CMD_ARG;       // 32-bit Command Argument
reg CMD_TRANSMIT;         // 0 => Receiver, 1 => Transmitter

// Communication Master (CM) //
reg CM_EN   = 0;                // Enable       
reg CM_RST    = 1;              // Reset
reg cmSpiClkEn = 1;             // Enable SPI Clock Output
reg CMClkBS = 0;             // 0 = not activate, 1 = activate byte sync mode

wire CM_EINT;                   // Error Interrupt
wire [3:0] CM_ETYPE;            // Error Type
wire [3:0] CM_EST;              // Errored State

reg [1:0] CM_RM = 2'b00;        // Read Mode
wire [39:0] CM_RR;              // Read Response (Read Data Buffer)

reg CM_STA = 0;                 // Start
wire CM_FIN;                    // Finished
wire CM_MISO, CM_CD, CM_WP;     // => From SD
wire CM_SCLK, CM_MOSI, CM_CS;   // <= To SD

spiCommMaster CMM (cpuClock, CM_EN, CM_RST, cmSpiClkEn, CMClkBS,
                   CM_EINT, CM_ETYPE, CM_EST,
                   CMD_TRANSMIT, CMD_INDEX, CMD_ARG,
                   CM_RM, CM_RR,
                   CM_STA, CM_FIN,
                   CM_MISO, CM_CD, CM_WP, CM_SCLK, CM_MOSI, CM_CS);


// INTERNAL //
reg spiClockEn = 0;
reg INTL_MOSI = 1, INTL_CS = 1;
reg INTLTM_RST = 1;            // Internal Timer Reset
wire [9:0] INTLTM_OUT;
wire INTLTM_OV;                // Internal Timer Overflow
counter #(10) INTLTM (CM_SCLK, INTLTM_RST, INTLTM_OUT, INTLTM_OV);
reg [39:0] INTL_RR = 0;            // Internal Read Response 
reg trySDv1 = 1;

// SPI PROTOCOL PORT CONNECTION //
assign CM_MISO = SD_MISO;
assign CM_CD = SD_CD;
assign CM_WP = SD_WP;
assign SD_CLK = (spiClockEn ? CM_SCLK : 1'b1) ; // also controlled by cmSpiClkEn
assign SD_MOSI = (CM_EN ? CM_MOSI : INTL_MOSI);
assign SD_CS = (CM_EN ? CM_CS : INTL_CS);

//// Outsize Communication Ports (UB - MicroBlaze)
//wire [31:0] UBDI; // Data In from MB
//wire [31:0] UBDO; // Data Out to MB
//wire UBEO; // Error Out to MB (Active HIGH)
//wire UBRRI; // ReadReadyInterrupt to MB (Active HIGH)
//wire UBRRA; // ReadReadyAcknowledge from MB (Active HIGH)
//wire UBRM;  // read mode 
//wire UBWM;  // write mode
//wire UBADDR;
//assign UBRM = btnR;
//assign UBWM = btnL;
//assign UBRRA = btnD;
//assign UBADDR = 32'h0;

// Data Read //
reg [6:0] _yb = 0; // vertical SD reading (128)

// Single Read (8-bit)
reg INTLRS_ST = 0;
wire INTLRS_FIN;
reg [7:0] INTLRS_BUFF;
wire [7:0] INTLRS_OUT;
reg INTLRS_WFBI = 1;
spiRead #(1) INTLRSM (CM_SCLK, INTLRS_ST, SD_MISO, INTLRS_FIN, INTLRS_OUT, INTLRS_WFBI);

// Double Read (16-bit)
reg INTLRD_ST = 0;
wire INTLRD_FIN;
reg [15:0] INTLRD_BUFF;
wire [15:0] INTLRD_OUT;
reg INTLRD_WFBI = 0;
spiRead #(2) INTLRDM (CM_SCLK, INTLRD_ST, SD_MISO, INTLRD_FIN, INTLRD_OUT, INTLRD_WFBI);

// Quad read (32-bit)
reg INTLRQ_ST = 0;
wire INTLRQ_FIN;
reg [31:0] INTLRQ_BUFF;
wire [31:0] INTLRQ_OUT;
reg INTLRQ_WFBI = 0;
spiRead #(4) INTLRQM (CM_SCLK, INTLRQ_ST, SD_MISO, INTLRQ_FIN, INTLRQ_OUT, INTLRQ_WFBI);

// CRC-16 For Data (CRCD) //
// uses CPU CLOCK
wire CRCD_IN;
reg CRCD_CLR = 1;
reg CRCD_EN = 0;
wire [15:0] CRCD_OUT;
reg  [15:0] CRCD_OUT_BUFF;
crcGenerator #(.LEN(16)) CRCDM (CRCD_IN, CM_SCLK, CRCD_CLR, CRCD_EN, 17'b1_00010000_00100001, CRCD_OUT);
assign CRCD_IN = SD_MISO;

// Data Reader (DR) //
reg DR_DRI = 0;         // <= Data Ready Interrupt
wire DR_DACK;           // => Data Ready Acknowledge
reg DREO = 0;           // <= Data Reader Error Out
wire [31:0] DR_OUT;     // Data Read output
assign DR_OUT = (DR_DRI) ? INTLRQ_BUFF : 32'bZ;

assign UBDO = DR_OUT; // Data Out to MB
assign UBEO = DREO;   
assign UBRRI = DR_DRI; // ReadReadyInterrupt to MB (Active HIGH)
assign DR_DACK = UBRRA; // ReadReadyAcknowledge from MB (Active HIGH)


// STATES //
// 0x0- : error states
// 0x1- : power sequence states 
// 0x2- : initialization states (1)
// 0x3- : initialization states (2)
// 0x40 : data transfer standby
// 0x6- : read 
// 0xA- : write

reg [7:0] state  = 8'h10;
reg [7:0] nstate = 8'h10;
assign _errorNoti = state[7:4] == 4'b0;

// main loop //
always @ (negedge cpuClock) begin
    if(globalReset) begin
        _errorState <= 8'h0;
        nstate <= 8'h10;
        INTLTM_RST <= 1;            // Stop Internal Timer
        CM_RST <= 1;                // Reset Communication Master
        DREO <= 0;
    end else begin
        case (state)
            8'h07: begin // card locked error
                if (SD_WP) begin
                    nstate <= 8'h10;
                end
            end
            8'h10: begin // wait for card
                CM_RST <= 0;                // Start Communication Master (Use CM_CLK)
                CM_EN  <= 0;                // Disable Communication Master (Use Internal CS and Timer)
                if (!SD_CD) begin
                    INTLTM_RST <= 0;         // Start Internal Timer With SPI Clock from CMM
                    nstate <= 8'h11;
                end
            end
            8'h11: begin // wait >= 1ms
                if (INTLTM_OUT > 200) begin
                    spiClockEn <= 1;        // Main Enable SPI Clock Set for the rest of operation
                    INTL_CS <= 1;           // Set CS HIGH per SD specification
                    INTLTM_RST <= 1;        // Stop Internal Timer
                    nstate <= 8'h12;
                end 
            end
            8'h12: begin // ctrReset sync 
                if (INTLTM_OUT == 0) begin // wait until counter is set to 0 at SPI Clock
                    INTLTM_RST <= 0;       // Start Inter Internal Timer With SPI Clock from CMM
                    nstate <= 8'h13;
                end
            end
            8'h13: begin // wait for at least 74 SPI clocks
                if (INTLTM_OUT > 74) begin
                    CM_EN   <= 1;
                    nstate  <= 8'h14;
                end
            end
            8'h14: begin // [CMD0] Set CMD
                INTLTM_RST   <= 1;      // reset Internal Timer
                CMD_INDEX    <= 0;      // CMD 0
                CMD_ARG      <= 0;
                CMD_TRANSMIT <= 1;          
                CM_STA       <= 1;      // Start Communication Master
                CM_RST       <= 0;
                CM_RM        <= 0;
                nstate       <= 8'h15;
            end
            8'h15: begin // [CMD0] wait for CM
                if (CM_EINT) begin 
                    _errorState <= state;
                    nstate <= 8'h05;    // CM Error
                end else if (CM_FIN) begin 
                    CM_STA <= 0;
                    INTL_RR = CM_RR;
                    nstate <= 8'h16;
                end
            end
            8'h16: begin // [CMD0] check response
                if (INTL_RR[7:0] == 8'b1) nstate <= 8'h20;
                else begin // init response error (unknown device)
                    _errorState <= state;
                    nstate <= 8'h02;                    // response error
                end             
            end
            8'h20: begin // standby (card idle state)
                //if (check?)
                nstate <= 8'h24; // Check Voltage range
            end
            8'h24: begin // [CMD8] Set CMD
                CMD_INDEX    <= 6'h08;                      // CMD8: Send Interface Condition Command 
                CMD_ARG      <= {24'h000001, 8'hAA};       // AA = 8-bit check pattern
                CMD_TRANSMIT <= 1;
                CM_STA       <= 1;
                CM_RST       <= 0;
                CM_RM        <= 2;
                nstate       <= 8'h25;
            end
            8'h25: begin // [CMD8] wait for CM
                if (CM_EINT) begin
                    if(CM_ETYPE == 4'b0010) begin       // timeout => Might be SDv1
                        trySDv1 <= 0;
                        CM_RST <= 1;
                        nstate <= 8'h28;                // goto 'set CMD55' state
                    end else begin
                        nstate <= 8'h05;                // CM Error
                    end    
                end else if (CM_FIN) begin
                    CM_STA   <= 0;
                    INTL_RR  <= CM_RR;
                    nstate   <= 8'h26;
                end
            end
            8'h26: begin // [CMD8] check response 
                if (INTL_RR[11:0] == 12'h1AA) begin
                    nstate <= 8'h28;                     // SDv2
                end else if(INTL_RR[39:32] == 8'h05) begin
                    trySDv1 <= 0;
                    nstate <= 8'h28;                     // SDv1? => try SDv1
                end else begin
                    _errorState = state;
                    nstate <= 8'h03;                     // Unknown Card Error
                end
            end
            8'h28: begin // [CMD55] set CMD (SDv1 & SDv2)
                CMD_INDEX    <= 55;                      // CMD55: Application Specific Command (APP_CMD)
                CMD_ARG      <= 0;      
                CMD_TRANSMIT <= 1;
                CM_STA       <= 1;
                CM_RST       <= 0;
                CM_RM        <= 0;
                nstate       <= 8'h29;
            end
            8'h29: begin // [CMD55] wait for CM (SDv1 & SDv2)
                if (CM_EINT) begin
                    _errorState    <= state; 
                    nstate         <= 8'h05;            // CM Error
                end else if (CM_FIN) begin
                    CM_STA <= 0;
                    INTL_RR <= CM_RR;
                    nstate <= 8'h2A;                    // delay check response to next clock for safety
                end
            end
            8'h2A: begin // [CMD55] check response (SDv1 & SDv2)
                if (INTL_RR[7:0] == 8'h01) begin             // Definitely SDv2
                    nstate <= 8'h2C;
                end else if (INTL_RR[7:0] == 8'h05) begin    // Is it SD v1?
                    if (trySDv1) begin                       // Have we tried SD v1?
                        trySDv1 <= 0;
                        nstate <= 8'h28;                     // goto 'Set CMD55' State
                    end else begin                           // Not SD v1 and SD v2
                        nstate <= 8'h03;                     // Unknown Card Error
                    end
                end else begin
                    _errorState <= state;
                    nstate      <= 8'h03;                    // Unknown Card Error
                end
            end
            8'h2C: begin // [ACMD41] Set CMD (SDv1 & SDv2 -- different in ACMD41_ARG)
                CMD_INDEX    <= 41;                         // ACMD41
                CMD_ARG      <= {(trySDv1 ? 4'h4 : 4'h0), 28'h0};                       
                CMD_TRANSMIT <= 1;  
                CM_STA       <= 1;
                CM_RST       <= 0;
                CM_RM        <= 0;
                nstate       <= 8'h2D;
            end
            8'h2D: begin // [ACMD41] wait for reading (SDv1 & SDv2)
                if (CM_EINT) begin
                    _errorState <= state;  
                    nstate      <= 8'h05;                    // CM Error
                end else if (CM_FIN) begin
                    CM_STA      <= 0;
                    INTL_RR     <= CM_RR;
                    nstate      <= 8'h2E;                   
                end
            end
            8'h2E: begin // [ACMD41] check response (SDv1 & SDv2)
                if (INTL_RR[7:0] == 8'h01) begin             // Not finished
                    nstate <= 8'h28;                         // Set CMD 58
                end else if (INTL_RR[7:0] == 8'h00) begin    // finished
                    if (trySDv1) begin                          // SDv2
                        nstate <= 8'h30;                        // goto `Set CMD58` State  
                    end else begin                              // SDv1
                        nstate <= 8'h38;                        // goto `Set CMD16` State  
                    end         
                end else if (INTL_RR[7:0] == 8'h05) begin // 'invalid command'
                    if (trySDv1) begin                        // Have we tried SD v1?
                        trySDv1 <= 0;
                        nstate <= 8'h28;                     // goto 'Set CMD55' State
                    end else begin                           // Not SD v1 and SD v2
                        _errorState = state;
                        nstate <= 8'h03;                     // Unknown Card Error
                    end
                end else begin
                    _errorState = state;
                    nstate <= 8'h03;                         // Unknown Card Error
                end
            end
            
            8'h30: begin // [CMD58] set CMD
                CMD_INDEX       <= 58;              // CMD58 - gen_crc
                CMD_ARG         <= 32'h0;                       
                CMD_TRANSMIT    <= 1;  
                CM_STA <= 1;
                CM_RST <= 0;
                CM_RM  <= 2;
                nstate <= 8'h31;
            end
            8'h31: begin // [CMD58] wait for CM
                if (CM_EINT) begin
                    _errorState    <= state;  
                    nstate         <= 8'h05;             // CM Error
                end else if (CM_FIN) begin
                    CM_STA <= 0;
                    INTL_RR <= CM_RR;
                    nstate <= 8'h32;                     // delay check response to next clock for safety
                end
            end
            8'h32: begin // [CMD58] check response 
                if (INTL_RR[30] == 1) begin     // CSS bit: determines whether High Capacity (HC) Card or not
                    // HC => Finish Initialize
                    nstate <= 8'h40;
                end else begin
                    // Standard Capacity => force block size
                    nstate <= 8'h34;
                end    
            end
            
            8'h34: begin // [CMD16] Set CMD
                CMD_INDEX    <= 16;                  // CMD16
                CMD_ARG      <= 32'h00000200;        // Force Block Size = 512 bytes for FAT filesystem
                CMD_TRANSMIT <= 1;    
                CM_STA       <= 1;
                CM_RST       <= 0;
                CM_RM        <= 0;
                nstate       <= 8'h35;
            end
            8'h35: begin // [CMD16] wait for CM
                if (CM_EINT) begin
                    _errorState    <= state;  
                    nstate         <= 8'h05;            // CM Error
                end else if (CM_FIN) begin
                    CM_STA <= 0;
                    INTL_RR <= CM_RR;
                    nstate <= 8'h36;                    
                end
            end
            8'h36: begin  // [CMD16] Check response
                if (INTL_RR[7:0] == 8'h01) begin
                    nstate <= 8'h40;
                end else begin
                    nstate <= 8'h02;
                    _errorState <= state;
                end
            end
            8'h40: begin
                // finished initialization
                if (SD_CD) begin
                    nstate <= 8'h10;
                end
                if (UBRM) begin
                    nstate <= 8'h60;
                end else if (UBWM) begin
                    nstate <= 8'hA0;
                end
            end
            8'h60: begin // [CMD17] Set CMD
                CMD_INDEX    <= 17;                  // CMD17 (Read Single Block)
                CMD_ARG      <= UBADDR;        // Address = 0
                CMD_TRANSMIT <= 1;    
                CM_STA       <= 1;
                CM_RST       <= 0;
                CM_RM        <= 0;
                nstate       <= 8'h61;
            end
            8'h61: begin // [CMD17] Wait for CM
                if (CM_EINT) begin
                    _errorState <= state;
                    nstate <= 8'h05;
                end else if (CM_FIN) begin
                    CM_STA <= 0;
                    INTL_RR <= CM_RR;
                    nstate <= 8'h62;
                end
            end
            8'h62: begin // [CMD17] Check Response
                if (INTL_RR[7:0] == 8'h00) begin
                    CM_EN      <= 0;                    // Disable CM
                    INTL_MOSI  <= 1;
                    INTL_CS    <= 0;
                    INTLTM_RST <= 0;
                    spiClockEn <= 0;
                    nstate <= 8'h64;                // goto ' wait for reading //
                end else begin
                    _errorState <= state;
                    nstate <= 8'h02;                // Response Error
                end
            end
            8'h64: begin // Start Reading into INTLRS (Data Token Receive)
                if (INTLRS_FIN == 0) begin          // check whether previous reading `stop` has been acknowledged
                    INTLRS_ST <= 1;                 // start reading
                    INTLRS_WFBI <= 0;
                    spiClockEn <= 1;
                    nstate    <= 8'h65;
                end 
            end
            8'h65: begin // wait for INTLRS reading
                if (INTLRS_FIN) begin
                    nstate <= 8'h66;
                    INTLRS_ST <= 0;
                    INTLRS_WFBI <= 1;
                    INTLRS_BUFF <= INTLRS_OUT;
                end
            end
            8'h66: begin // check response of INTLRS (Data Token)
                if (INTLRS_BUFF == 8'hFE) begin // received data token for CMD17/18/24
                    INTLTM_RST <= 1;
                    nstate <= 8'h67;
                end else if (INTLRS_BUFF == 8'hFC) begin // received data token for CMD25
                    _errorState <= state;
                    nstate <= 8'h02;
                end else if (INTLRS_BUFF == 8'hFD) begin // Stop trans token for CMD25
                    _errorState <= state;
                    nstate <= 8'h02;
                end else if (INTLRS_BUFF == 8'hFF) begin
                    if (INTLTM_OUT > 200) begin
                        INTLTM_RST <= 1;
                        _errorState <= state;
                        nstate <= 8'h01; 
                    end else begin
                        spiClockEn <= 0;
                        nstate <= 8'h64;                // go back
                    end
                end else begin
                    _errorState <= state;
                    nstate <= 8'h02;                    // illegal response
                end
            end
            8'h67: begin // Start Reading Loop (y) - 32 bit
                _yb <= 0;
                CRCD_CLR <= 0;
                nstate <= 8'h68;
            end
            8'h68: begin // Read Data Loop body (1)
                INTLRQ_ST <= 1;
                spiClockEn <= 1;                
                DR_DRI <= 0;
                CRCD_EN <= 1;
                nstate <= 8'h69;
            end
            8'h69: begin // Wait for Reading 
                if (INTLRQ_FIN) begin
                    spiClockEn <= 0;
                    INTLRQ_BUFF <= INTLRQ_OUT;
                    INTLRQ_ST <= 0;
                    DR_DRI <= 1;
                    CRCD_OUT_BUFF <= CRCD_OUT; 
                    CRCD_EN <= 0;
                    nstate <= 8'h6A;
                end else begin
                    spiClockEn <= 1;
                end
            end
            8'h6A: begin // Check data
                if (!INTLRQ_FIN && DR_DACK) begin
                    if (_yb == 7'h7F) begin                 // loop condition
                        _yb <= 0;       
                        nstate <= 8'h70;
                    end else begin
                        _yb <= _yb + 1;                     // loop increment
                        nstate <= 8'h68;
                    end
                end
            end
            8'h70: begin // Finish Reading Data => read CRC-16
                INTLRD_ST <= 1;
                spiClockEn <= 1;
                nstate <= 8'h71;
            end
            8'h71: begin
                if (INTLRD_FIN) begin
                    INTLRD_BUFF <= INTLRD_OUT;
                    INTLRD_ST <= 0;
                    nstate <= 8'h72;
                end
            end
            8'h72: begin 
                if (INTLRD_BUFF == CRCD_OUT_BUFF) begin
                    DREO <= 0;
                    nstate <= 8'h74;
                end else begin
                    DREO <= 1;
                    nstate <= 8'h08;                        // crc error
                end
            end
            8'h74: begin //wait for data transfer to UB (Microblaze) complete.
                CM_EN      <= 1;                    // Enable CM
                nstate <= 8'h40;                    // go back
            end
            8'h80: begin // [CMD18] Set CMD
                CMD_INDEX    <= 18;                  // CMD17 (Read Multi Block)
                CMD_ARG      <= UBADDR;              // Address
                CMD_TRANSMIT <= 1;    
                CM_STA       <= 1;
                CM_RST       <= 0;
                CM_RM        <= 0;
                nstate       <= 8'h81;
            end
            8'h81: begin // [CMD18] Wait for CM
                if (CM_EINT) begin
                    _errorState <= state;
                    nstate <= 8'h05;
                end else if (CM_FIN) begin
                    CM_STA <= 0;
                    INTL_RR <= CM_RR;
                    nstate <= 8'h82;
                end
            end
            8'h82: begin // [CMD18] Check Response
                if (INTL_RR[7:0] == 8'h00) begin
                    CM_EN      <= 0;                    // Disable CM
                    INTL_MOSI  <= 1;
                    INTL_CS    <= 0;
                    INTLTM_RST <= 0;
                    spiClockEn <= 0;
                    nstate <= 8'h84;                // goto ' wait for reading //
                end else begin
                    _errorState <= state;
                     nstate <= 8'h02;                // Response Error
                end
            end
            8'h84: begin
                
            end
            8'hA0: begin // <single write>
                
            end
            default: begin 
                if(state[7:4] != 4'b0) begin
                    _errorState = state;
                    nstate = 8'h04;
                end
            end
        endcase
    end
end

always @ (posedge cpuClock) begin
    if (nstate != state && nstate != state + 1 && nstate[1:0] != 2'b00 && nstate[7:4] != 4'h0) begin
        state <= 8'h06;     //Invalid state sequence
    end else begin
        state <= nstate;
    end
end

// History of states //
// LSB = newest, MSB = oldest
reg [63:0] history = 0;
always @ (posedge cpuClock) begin
    if (globalReset)begin
        history = 0;
    end else if (nstate != state) begin
        history = {history[55:0], nstate};
    end
end

// Seven Segment //

wire [2:0] historySel;
assign historySel = sw[10:8];
wire [15:0] numSegment;
wire segClock;
wire [3:0] aen;
assign numSegment = sw[11] ? {CM_EST, CM_ETYPE} : historySel == 0 ? {_errorState, state} : history[historySel * 8 +:7];
assign aen = ~sw[15:12];
clockDiv #(10) seg0 (cpuClock, segClock);
segMaster seg1 (segClock, numSegment, aen, seg, an, dp); 

// debug

reg [255:0] historyBuff = 0;
always @ (posedge cpuClock) begin
    if (globalReset)begin
        historyBuff = 0;
    end else if (INTLRQ_BUFF != historyBuff[31:0]) begin
        historyBuff = {historyBuff[223:0], INTLRQ_BUFF};
    end
end

wire [1:0] layer;
assign layer = sw[1:0];

wire cl0, cl1, cl2;
clockDiv #(12) d0 (cpuClock, cl0);
assign led = (sw[1] ? historyBuff[historySel * 32 + 16 +:15] : historyBuff[historySel * 32 +:15]);
endmodule
