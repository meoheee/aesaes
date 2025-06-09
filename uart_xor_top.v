// uart_xor_top.v (UART 명령어로 키 설정, 최종 수정본)

module uart_xor_top (
    i_clk,
    i_rst_n,
    i_uart_rxd,
    o_uart_txd
);

    parameter CLOCK_FREQ = 50_000_000;
    parameter BAUD_RATE  = 9600;

    input  wire i_clk;
    input  wire i_rst_n;
    input  wire i_uart_rxd;
    output wire o_uart_txd;

    // --- 키 설정을 위한 파라미터 및 레지스터 ---
    parameter CMD_SET_KEY = 8'hFF; // 키 설정을 시작하는 명령어 바이트
    
    // FSM 상태 정의
    parameter S_OP_MODE    = 1'b0; // 일반 암호화 동작 모드
    parameter S_SET_KEY_MODE = 1'b1; // 키 값 대기 모드

    reg state; // 현재 상태 저장
    reg [7:0] key_reg; // 키 값을 저장할 내부 레지스터

    // --- 나머지 신호들 ---
    wire        rx_done_tick;
    wire [7:0]  rx_data;
    reg         tx_start;
    reg  [7:0]  tx_data;
    wire        tx_busy;

    // --- 여기부터가 에러난 부분의 완전한 코드 ---
    // UART RX 모듈 인스턴스화
    uart_rx #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_uart_rx (
        .i_clk        (i_clk),
        .i_rst_n      (i_rst_n),
        .i_rxd        (i_uart_rxd),
        .o_rx_done    (rx_done_tick),
        .o_rx_data    (rx_data)
    );

    // UART TX 모듈 인스턴스화
    uart_tx #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_uart_tx (
        .i_clk        (i_clk),
        .i_rst_n      (i_rst_n),
        .i_tx_start   (tx_start),
        .i_tx_data    (tx_data),
        .o_txd        (o_uart_txd),
        .o_tx_busy    (tx_busy)
    );
    // --- 여기까지 ---


    // 메인 로직: 상태 머신(FSM)으로 모드 관리
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            tx_start  <= 1'b0;
            tx_data   <= 8'b0;
            state     <= S_OP_MODE; // 리셋 시 일반 동작 모드로 시작
            key_reg   <= 8'hA5;     // 기본 키 값 설정
        end else begin
            tx_start <= 1'b0; // 매 클럭마다 초기화

            // 데이터가 수신되었을 때만 동작
            if (rx_done_tick) begin
                case (state)
                    S_OP_MODE: begin
                        // 수신된 데이터가 키 설정 명령어라면
                        if (rx_data == CMD_SET_KEY) begin
                            state <= S_SET_KEY_MODE; // 키 설정 모드로 변경
                        end
                        // 일반 데이터라면
                        else begin
                            if (!tx_busy) begin
                                tx_start <= 1'b1;
                                tx_data  <= rx_data ^ key_reg; // 현재 저장된 키로 XOR
                            end
                        end
                    end
                    
                    S_SET_KEY_MODE: begin
                        key_reg <= rx_data; // 수신된 데이터를 새 키로 저장
                        state   <= S_OP_MODE; // 다시 일반 동작 모드로 복귀
                    end
                endcase
            end
        end
    end

endmodule