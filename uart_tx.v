// uart_tx.v (Verilog-2001 Standard)

module uart_tx (
    i_clk,
    i_rst_n,
    i_tx_start,
    i_tx_data,
    o_txd,
    o_tx_busy
);
    parameter CLOCK_FREQ = 50_000_000;
    parameter BAUD_RATE  = 9600;

    input  wire        i_clk;
    input  wire        i_rst_n;
    input  wire        i_tx_start;
    input  wire [7:0]  i_tx_data;
    output reg         o_txd; // always 블록에서 제어되므로 reg
    output reg         o_tx_busy; // always 블록에서 제어되므로 reg

    parameter CLKS_PER_BIT = CLOCK_FREQ / BAUD_RATE;

    // FSM 상태를 위한 파라미터 정의 (enum 대신)
    parameter S_IDLE  = 3'b000;
    parameter S_START = 3'b001;
    parameter S_DATA  = 3'b010;
    parameter S_STOP  = 3'b011;

    reg [2:0]  state;
    reg [19:0] clk_counter;
    reg [2:0]  bit_index;
    reg [7:0]  tx_buffer;

    // 상태 머신 및 출력 로직
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state       <= S_IDLE;
            o_txd       <= 1'b1; // IDLE 상태는 High
            o_tx_busy   <= 1'b0;
            clk_counter <= 0;
            bit_index   <= 0;
            tx_buffer   <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (i_tx_start) begin
                        state     <= S_START;
                        tx_buffer <= i_tx_data; // 보낼 데이터 저장
                        o_txd     <= 1'b0; // Start Bit (Low)
                        clk_counter <= 0;
                        o_tx_busy <= 1'b1;
                    end
                end
                S_START: begin
                    if (clk_counter == CLKS_PER_BIT - 1) begin
                        state       <= S_DATA;
                        clk_counter <= 0;
                        bit_index   <= 0;
                        o_txd       <= tx_buffer[0]; // 데이터 첫 비트 전송
                    end else begin
                        clk_counter <= clk_counter + 1;
                    end
                end
                S_DATA: begin
                    if (clk_counter == CLKS_PER_BIT - 1) begin
                        clk_counter <= 0;
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                            o_txd     <= tx_buffer[bit_index + 1];
                        end else begin
                            state <= S_STOP;
                            o_txd <= 1'b1; // Stop bit
                        end
                    end else begin
                        clk_counter <= clk_counter + 1;
                    end
                end
                S_STOP: begin
                    if (clk_counter == CLKS_PER_BIT - 1) begin
                        state     <= S_IDLE;
                        o_tx_busy <= 1'b0; // 전송 완료
                    end else begin
                        clk_counter <= clk_counter + 1;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule