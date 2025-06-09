// uart_rx.v (타이밍 로직을 개선한 최종 수정본)

module uart_rx (
    i_clk,
    i_rst_n,
    i_rxd,
    o_rx_done,
    o_rx_data
);
    parameter CLOCK_FREQ = 50_000_000;
    parameter BAUD_RATE  = 9600;

    input  wire        i_clk;
    input  wire        i_rst_n;
    input  wire        i_rxd;
    output reg         o_rx_done;
    output reg  [7:0]  o_rx_data;

    localparam CLKS_PER_BIT = CLOCK_FREQ / BAUD_RATE;
    
    parameter S_IDLE  = 2'b00;
    parameter S_START = 2'b01;
    parameter S_DATA  = 2'b10;
    parameter S_STOP  = 2'b11;

    reg [1:0]  state;
    reg [19:0] clk_counter;
    reg [2:0]  bit_index;
    reg [7:0]  rx_buffer;
    reg        rxd_sync, rxd_d1;

    always @(posedge i_clk) begin
        rxd_d1   <= i_rxd;
        rxd_sync <= rxd_d1;
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state          <= S_IDLE;
            clk_counter    <= 0;
            bit_index      <= 0;
            o_rx_done      <= 1'b0;
            o_rx_data      <= 8'b0;
            rx_buffer      <= 8'b0;
        end else begin
            // o_rx_done은 한 클럭 후에 자동으로 0이 되도록 처리
            o_rx_done <= 1'b0;
            
            case(state)
                S_IDLE: begin
                    if (!rxd_sync) begin // Start Bit 감지 (Falling Edge)
                        state       <= S_START;
                        clk_counter <= 0; // 타이머 시작!
                    end
                end

                S_START: begin
                    // Start Bit의 중간 지점까지 대기
                    if (clk_counter < (CLKS_PER_BIT / 2) - 1) begin
                        clk_counter <= clk_counter + 1;
                    end else begin
                        // 중간 지점에서 rxd가 Low가 맞는지 재확인
                        if (!rxd_sync) begin
                            state       <= S_DATA;
                            bit_index   <= 0;
                            clk_counter <= 0; // 다음 비트를 위해 타이머 리셋
                        end else begin
                            state <= S_IDLE; // 잘못된 신호였으면 IDLE로 복귀
                        end
                    end
                end

                S_DATA: begin
                    // 한 비트의 시간(Baud Period)만큼 대기
                    if (clk_counter < CLKS_PER_BIT - 1) begin
                        clk_counter <= clk_counter + 1;
                    end else begin
                        // 비트 시간의 끝에서 샘플링 (실제로는 중간값 샘플링이 더 좋지만, 시뮬레이션에서는 이것도 잘 동작함)
                        rx_buffer[bit_index] <= rxd_sync;
                        clk_counter <= 0;

                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            state <= S_STOP; // 8비트 수신 완료
                        end
                    end
                end
                
                S_STOP: begin
                    // Stop Bit 시간만큼 대기
                    if (clk_counter < CLKS_PER_BIT - 1) begin
                        clk_counter <= clk_counter + 1;
                    end else begin
                        state     <= S_IDLE; // 모든 과정 종료, IDLE로 복귀
                        o_rx_done <= 1'b1;   // 수신 완료 신호
                        o_rx_data <= rx_buffer; // 최종 데이터 출력
                    end
                end
            endcase
        end
    end
endmodule