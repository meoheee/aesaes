`timescale 1ns/1ps
`default_nettype none
//---------------------------------------------------------------------
// aes_uart_top.v  -  ROM 하나(256×8)와 연결되는 최상위 예제
//   * AES RTL(aes.v / aes_core.v) 형식에 맞춰 단일 S-Box ROM 포트를
//     그대로 외부로 노출.
//   * UART 프로토콜:  'K'+KEY16, 'E'+PT16, 'D'+CT16 → 결과 CT/PT16 전송
//   * FSM·버스 로직은 원본 그대로 유지, 포트 이름만 aes_* prefix 사용
//---------------------------------------------------------------------
module aes_uart_top #(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD     = 115_200)
  (
   input  wire        clk,
   input  wire        rst_n,
   // UART
   input  wire        rx,
   output wire        tx,
   // S-Box 외부 ROM (256×8)
   output wire [7:0]  rom_addr,
   input  wire [7:0]  rom_data,
   output wire        rom_ce_n,
   output wire        rom_oe_n

  );

 //wire [127:0] key_dbg,  
 //wire [127:0] data_dbg, 
 //wire [127:0] ct_dbg,   
 wire [3:0]   st;        
  
  
  
  
  //------------------------------------------------------------------
  // UART 인스턴스
  //------------------------------------------------------------------
  localparam CLKS_PER_BIT = CLK_FREQ / BAUD;

  wire [7:0] rx_d;  wire rx_v;
  uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx
    (.clk(clk), .rst_n(rst_n), .rx_serial(rx), .rx_data(rx_d), .rx_valid(rx_v));

  reg        tx_start;  wire tx_busy;
  reg  [7:0] tx_d;
  uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx
    (.clk(clk), .rst_n(rst_n), .tx_start(tx_start), .tx_data(tx_d),
     .tx_serial(tx), .tx_busy(tx_busy));

  //------------------------------------------------------------------
  // AES 인스턴스 (단일 ROM 포트)
  //------------------------------------------------------------------
  reg         aes_cs, aes_we;
  reg  [7:0]  aes_addr;
  reg  [31:0] aes_wdata;
  wire [31:0] aes_rdata;

  aes u_aes (
      .clk       (clk),
      .reset_n   (rst_n),
      .cs        (aes_cs),
      .we        (aes_we),
      .address   (aes_addr),
      .write_data(aes_wdata),
      .read_data (aes_rdata),
      // 외부 ROM 연결
      .rom_addr  (rom_addr),
      .rom_data  (rom_data),
      .rom_ce_n  (rom_ce_n),
      .rom_oe_n  (rom_oe_n)
  );

  //------------------------------------------------------------------
  // 버퍼 & 디버그용 레지스터
  //------------------------------------------------------------------
  reg [127:0] key_buf, data_buf, ct_buf;
  //assign key_dbg  = key_buf;
  //assign data_dbg = data_buf;
  //assign ct_dbg   = ct_buf;

  //------------------------------------------------------------------
  // FSM 정의 (기존 그대로)
  //------------------------------------------------------------------
  localparam S_IDLE        = 4'd0,
             S_RX128       = 4'd1,
             S_KEY_WR      = 4'd2,
             S_CFG_INIT0   = 4'd3,
             S_CFG_INIT1   = 4'd4,
             S_WAIT_READY  = 4'd5,
             S_DATA_WR     = 4'd6,
             S_CFG_NEXT0   = 4'd7,
             S_CFG_NEXT1   = 4'd8,
             S_WAIT_VALID  = 4'd9,
             S_TX_RD_WAIT  = 4'd10,
             S_TX_RD       = 4'd11;

  reg [3:0] state; assign st = state;
  reg [4:0] byte_cnt;
  reg       cmd_k, cmd_e, cmd_d;

  //------------------------------------------------------------------
  // AXI-lite-style helper tasks (write / idle)
  //------------------------------------------------------------------
  task wr32(input [7:0] a, input [31:0] d);
    begin aes_addr<=a; aes_wdata<=d; aes_cs<=1; aes_we<=1; end
  endtask
  task bus_idle; begin aes_cs<=0; aes_we<=0; end endtask

  //------------------------------------------------------------------
  // Main FSM
  //------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      state<=S_IDLE; byte_cnt<=0; bus_idle(); tx_start<=0;
    end else begin
      bus_idle(); tx_start<=0;
      case(state)
        S_IDLE: if(rx_v) begin
                    cmd_k <= (rx_d==8'h4B); cmd_e <= (rx_d==8'h45); cmd_d <= (rx_d==8'h44);
                    byte_cnt<=0; state<=S_RX128; key_buf<=0; data_buf<=0;
                 end
        S_RX128: if(rx_v) begin
                    data_buf <= {data_buf[119:0],rx_d};
                    byte_cnt <= byte_cnt+1;
                    if(byte_cnt==5'd15) begin
                      byte_cnt<=0;
                      if(cmd_k) begin key_buf<= {data_buf[119:0],rx_d}; state<=S_KEY_WR; end
                      else state<=S_DATA_WR;
                    end
                 end
        // KEY write (4 words)
        S_KEY_WR: begin
                    wr32(8'h10+byte_cnt, key_buf[127-byte_cnt*32 -:32]);
                    byte_cnt<=byte_cnt+1;
                    if(byte_cnt==3) begin byte_cnt<=0; state<=S_CFG_INIT0; end
                  end
        S_CFG_INIT0: begin wr32(8'h0A,32'h0000_0001); state<=S_CFG_INIT1; end
        S_CFG_INIT1: begin wr32(8'h08,32'h0000_0001); state<=S_WAIT_READY; end
        S_WAIT_READY: begin aes_addr<=8'h09; aes_cs<=1; if(aes_rdata[0]) state<=S_IDLE; end

        // DATA write (4 words)
        S_DATA_WR: begin
                      wr32(8'h20+byte_cnt, data_buf[127-byte_cnt*32 -:32]);
                      byte_cnt<=byte_cnt+1;
                      if(byte_cnt==3) begin byte_cnt<=0; state<=S_CFG_NEXT0; end
                    end
        S_CFG_NEXT0: begin wr32(8'h0A,{31'd0,cmd_e}); state<=S_CFG_NEXT1; end
        S_CFG_NEXT1: begin wr32(8'h08,32'h0000_0002); state<=S_WAIT_VALID; end
        S_WAIT_VALID: begin aes_addr<=8'h09; aes_cs<=1; if(aes_rdata[1]) state<=S_TX_RD_WAIT; end

        // 4-cycle idle so aes_rdata stable
        S_TX_RD_WAIT: begin if(!tx_busy) state<=S_TX_RD; end
        S_TX_RD: begin
          aes_addr<=8'h30+byte_cnt; aes_cs<=1;
          if(!tx_busy) begin tx_d<=aes_rdata[byte_cnt*8 +:8]; tx_start<=1; end
          if(!tx_busy) begin
            ct_buf[127-byte_cnt*32 -:32] <= aes_rdata; // capture 4 words
            byte_cnt<=byte_cnt+1;
            if(byte_cnt==3) state<=S_IDLE;
          end
        end
        default: state<=S_IDLE;
      endcase
    end
  end
endmodule

`default_nettype wire
