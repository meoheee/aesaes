`timescale 1ns/1ps
`default_nettype none
// ------------------------------------------------------------------
// AES-128 encipher block – 16-cycle S-Box, same port list
// ------------------------------------------------------------------
module aes_encipher_block (
    input  wire           clk, reset_n,
    input  wire           next,
    // input wire         keylen,                // not used: 128-bit fixed
    output wire [3 : 0]   round,
    input  wire [127 : 0] round_key,

    output wire [31 : 0]  sboxw,                // to aes_sbox
    input  wire  [31 : 0] new_sboxw,            // from aes_sbox

    input  wire [127 : 0] block,
    output reg  [127 : 0] new_block,
    output reg            ready
);
  // ---------------------------------------------------------------
  // very small MixColumns helpers
  function [7:0] xtime(input [7:0] b);
      xtime = {b[6:0],1'b0} ^ (8'h1b & {8{b[7]}});
  endfunction
  function [31:0] mix(input [31:0] col);
      mix = { xtime(col[31:24]) ^ xtime(col[23:16]) ^ col[23:16] ^ col[15:8]  ^ col[7:0],
              col[31:24]        ^ xtime(col[23:16]) ^ xtime(col[15:8]) ^ col[15:8]  ^ col[7:0],
              col[31:24]        ^ col[23:16]  ^ xtime(col[15:8]) ^ xtime(col[7:0]) ^ col[7:0],
              xtime(col[31:24]) ^ col[31:24]  ^ col[23:16] ^ col[15:8] ^ xtime(col[7:0]) };
  endfunction

  // ---------------------------------------------------------------
  // state registers
  localparam S_IDLE = 0, S_ADDKEY0=1, S_SUB=2, S_WAIT=3,
             S_MIX=4,  S_ADDKEYF=5, S_DONE=6;
  reg [2:0]  state;
  reg [3:0]  byte_ctr;
  reg [127:0] st;                // internal data block
  assign round = 4'd0;           // single-round core

  // connect S-Box (one per AES core)
  assign sboxw = st[127:96];     // top 32-bit word

  // ---------------------------------------------------------------
  always @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
        state<=S_IDLE; ready<=0; byte_ctr<=0; st<=0; new_block<=0;
    end else begin
        ready<=0;
        case(state)
          S_IDLE: if(next) begin
              st    <= block ^ round_key;    // AddRoundKey #0
              state <= S_SUB;
              byte_ctr<=0;
          end
          //---------------- 16-cycle subbytes ----------------------
          S_SUB: begin state<=S_WAIT; end
          S_WAIT: begin
              st[127-:32] <= new_sboxw;      // write substituted word
              // rotate to next word
              st <= {st[95:0], new_sboxw};
              byte_ctr <= byte_ctr + 1'b1;
              if(byte_ctr==4'd15) state<=S_MIX;
              else                state<=S_SUB;
          end
          //---------------- ShiftRows+MixColumns -------------------
          S_MIX: begin
              st[127:96] <= mix(st[127:96]);
              st[95 :64] <= mix(st[95 :64]);
              st[63 :32] <= mix(st[63 :32]);
              st[31 : 0] <= mix(st[31 : 0]);
              state <= S_ADDKEYF;
          end
          //---------------- Final AddRoundKey ---------------------
          S_ADDKEYF: begin
              st    <= st ^ round_key;
              state <= S_DONE;
          end
          S_DONE: begin
              new_block <= st; ready <= 1'b1;
              state <= S_IDLE;
          end
        endcase
    end
  end
endmodule
`default_nettype wire
