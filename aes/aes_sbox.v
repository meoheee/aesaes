`timescale 1ns/1ps
`default_nettype none

module aes_sbox (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [31:0] sboxw,     // 4 input bytes
    output reg  [31:0] new_sboxw, // 4 output bytes

    // external ROM interface (256 ¡¿ 8)
    output reg [7:0]  rom_addr,
    input  wire [7:0]  rom_data,
    output reg        rom_ce_n,
    output reg        rom_oe_n
);
  // FSM states
  localparam IDLE  = 3'd0,
             READ0 = 3'd1,
             READ1 = 3'd2,
             READ2 = 3'd3,
             READ3 = 3'd4;

  reg [2:0] state;

  //--------------------------------------------------------------
  // FSM
  //--------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      state      <= IDLE;
      new_sboxw  <= 32'd0;
      rom_addr   <= 8'd0;
      rom_ce_n   <= 1'b1;
      rom_oe_n   <= 1'b1;
    end else begin
      case(state)
        //--------------------------------------------------------
        IDLE: begin
          // initialise first access every time we enter IDLE
          rom_addr  <= sboxw[31:24];
          rom_ce_n  <= 1'b0;           // enable ROM
          rom_oe_n  <= 1'b0;
          state     <= READ0;
        end
        //--------------------------------------------------------
        READ0: begin
          new_sboxw[31:24] <= rom_data;
          rom_addr         <= sboxw[23:16];
          state            <= READ1;
        end
        READ1: begin
          new_sboxw[23:16] <= rom_data;
          rom_addr         <= sboxw[15:8];
          state            <= READ2;
        end
        READ2: begin
          new_sboxw[15:8]  <= rom_data;
          rom_addr         <= sboxw[7:0];
          state            <= READ3;
        end
        READ3: begin
          new_sboxw[7:0]   <= rom_data;
          rom_ce_n         <= 1'b1;     // disable ROM until next cycle
          rom_oe_n         <= 1'b1;
          state            <= IDLE;     // ready for next word
        end
        //--------------------------------------------------------
        default: state <= IDLE;
      endcase
    end
  end
endmodule

`default_nettype wire
