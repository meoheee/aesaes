`timescale 1ns/1ps
`default_nettype none
// ------------------------------------------------------------------
// AES-128 decipher block – inverse S-Box via external ROM
// ------------------------------------------------------------------
module aes_decipher_block (
    input  wire           clk, reset_n,
    input  wire           next,
    // input wire         keylen,
    output wire [3 : 0]   round,
    input  wire [127 : 0] round_key,

    input  wire [127 : 0] block,
    output reg  [127 : 0] new_block,
    output reg            ready,

    // external ROM – same pins kept
    output wire [7:0]     rom_addr,
    input  wire [7:0]     rom_data,
    output wire           rom_ce_n,
    output wire           rom_oe_n
);
  // ---------------------------------------------------------------
  // inverse MixColumns helpers
  function [7:0] xtime(input [7:0] b);
      xtime = {b[6:0],1'b0} ^ (8'h1b & {8{b[7]}});
  endfunction
  function [7:0] mul(input [7:0] b, input integer c);
      case(c)
        9 : mul = xtime(xtime(xtime(b))) ^ b;
        11: mul = xtime(xtime(xtime(b)) ^ b) ^ b;
        13: mul = xtime(xtime(xtime(b) ^ b)) ^ b;
        14: mul = xtime(xtime(xtime(b) ^ b) ^ b);
        default: mul = 8'h00;
      endcase
  endfunction
  function [31:0] invmix(input [31:0] w);
      invmix = { mul(w[31:24],14) ^ mul(w[23:16],11) ^ mul(w[15: 8],13) ^ mul(w[7:0], 9),
                 mul(w[31:24], 9) ^ mul(w[23:16],14) ^ mul(w[15: 8],11) ^ mul(w[7:0],13),
                 mul(w[31:24],13) ^ mul(w[23:16], 9) ^ mul(w[15: 8],14) ^ mul(w[7:0],11),
                 mul(w[31:24],11) ^ mul(w[23:16],13) ^ mul(w[15: 8], 9) ^ mul(w[7:0],14)};
  endfunction

  // ---------------------------------------------------------------
  localparam S_IDLE=0,S_ADDKEY0=1,S_INVSHIFT=2,S_SUB=3,S_WAIT=4,
             S_INVMIX=5,S_ADDKEYF=6,S_DONE=7;
  reg [2:0] state; reg [3:0] byte_ctr;
  reg [127:0] st; reg [31:0] sboxw_r;
  assign round = 4'd0;

  // inverse S-Box wrapper (reuse aes_sbox with separate table)
  aes_sbox INV_SBOX (
      .clk(clk), .rst_n(reset_n),
      .sboxw   (sboxw_r),
      .new_sboxw(new_sboxw),
      .rom_addr(rom_addr), .rom_data(rom_data),
      .rom_ce_n(rom_ce_n), .rom_oe_n(rom_oe_n)
  );
  wire [31:0] new_sboxw;

  // ---------------------------------------------------------------
  always @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
        state<=S_IDLE; ready<=0; byte_ctr<=0; st<=0; new_block<=0;
    end else begin
        ready<=0;
        case(state)
          S_IDLE: if(next) begin
              st <= block ^ round_key;          // pre-AddRoundKey
              state<=S_INVSHIFT;
          end
          S_INVSHIFT: begin
              // simple byte permutation
              st <= { st[127:120], st[23:16],  st[47:40],  st[71:64],
                      st[95:88],   st[119:112],st[15:8],    st[39:32],
                      st[63:56],   st[87:80],  st[111:104], st[7:0] };
              byte_ctr<=0; state<=S_SUB;
          end
          S_SUB: begin
              sboxw_r <= st[127:96];   // top word
              state<=S_WAIT;
          end
          S_WAIT: begin
              st[127:96] <= new_sboxw;
              st <= {st[95:0],new_sboxw};
              byte_ctr<=byte_ctr+1;
              if(byte_ctr==15) state<=S_INVMIX;
              else             state<=S_SUB;
          end
          S_INVMIX: begin
              st[127:96] <= invmix(st[127:96]);
              st[95 :64] <= invmix(st[95 :64]);
              st[63 :32] <= invmix(st[63 :32]);
              st[31 : 0] <= invmix(st[31 : 0]);
              state<=S_ADDKEYF;
          end
          S_ADDKEYF: begin
              st <= st ^ round_key;
              state<=S_DONE;
          end
          S_DONE: begin
              new_block<=st; ready<=1; state<=S_IDLE;
          end
        endcase
    end
  end
endmodule
`default_nettype wire
