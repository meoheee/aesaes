`timescale 1ns/1ps
`default_nettype none
// ------------------------------------------------------------------
// AES-128 key schedule (single S-Box, ports unchanged)
// ------------------------------------------------------------------
module aes_key_mem (
    input  wire         clk, reset_n,
    input  wire [127:0] key,
    // input wire        keylen,          // fixed to 128-bit
    input  wire         init,

    input  wire  [3:0]  round,
    output reg  [127:0] round_key,
    output reg          ready,

    output wire [31:0]  sboxw,
    input  wire [31:0]  new_sboxw       // from shared aes_sbox
);
  // only 11 round keys (0..10) stored
  reg [127:0] rk_mem [0:10];
  reg [3:0]   idx;
  reg         gen;

  assign sboxw = rk_mem[idx][31:0];     // lowest word → S-Box

  // --------------------------- key expansion FSM ------------------
  localparam K_IDLE=0,K_GEN=1,K_WAIT=2,K_DONE=3;
  reg [1:0] kstate;
  reg [7:0] rcon;

  // Fsm
  always @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
        kstate<=K_IDLE; idx<=0; ready<=0; rcon<=8'h01;
    end else begin
        case(kstate)
          K_IDLE: if(init) begin
                      rk_mem[0] <= key;
                      idx<=0; kstate<=K_GEN; ready<=0; rcon<=8'h01;
                  end
          K_GEN: begin
                  // start S-Box on word3
                  gen<=1; kstate<=K_WAIT;
                 end
          K_WAIT: begin
                  gen<=0;
                  // construct next key
                  rk_mem[idx+1] <= { rk_mem[idx][127:96] ^
                                     {new_sboxw[23:0],new_sboxw[31:24]} ^ {rcon,24'h0},
                                     rk_mem[idx][95:0] ^
                                     ({ rk_mem[idx][127:96] ^
                                        {new_sboxw[23:0],new_sboxw[31:24]} ^ {rcon,24'h0}}) };
                  rcon <= {rcon[6:0],1'b0} ^ (8'h1b & {8{rcon[7]}});
                  idx  <= idx + 1;
                  if(idx==9) kstate<=K_DONE; else kstate<=K_GEN;
                 end
          K_DONE: begin ready<=1; kstate<=K_IDLE; end
        endcase
    end
  end

  // read port (combinational)
  always @(*) begin
      round_key = rk_mem[round];
  end
endmodule
`default_nettype wire
