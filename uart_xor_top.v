// uart_xor_top.v (UART ��ɾ�� Ű ����, ���� ������)

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

    // --- Ű ������ ���� �Ķ���� �� �������� ---
    parameter CMD_SET_KEY = 8'hFF; // Ű ������ �����ϴ� ��ɾ� ����Ʈ
    
    // FSM ���� ����
    parameter S_OP_MODE    = 1'b0; // �Ϲ� ��ȣȭ ���� ���
    parameter S_SET_KEY_MODE = 1'b1; // Ű �� ��� ���

    reg state; // ���� ���� ����
    reg [7:0] key_reg; // Ű ���� ������ ���� ��������

    // --- ������ ��ȣ�� ---
    wire        rx_done_tick;
    wire [7:0]  rx_data;
    reg         tx_start;
    reg  [7:0]  tx_data;
    wire        tx_busy;

    // --- ������Ͱ� ������ �κ��� ������ �ڵ� ---
    // UART RX ��� �ν��Ͻ�ȭ
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

    // UART TX ��� �ν��Ͻ�ȭ
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
    // --- ������� ---


    // ���� ����: ���� �ӽ�(FSM)���� ��� ����
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            tx_start  <= 1'b0;
            tx_data   <= 8'b0;
            state     <= S_OP_MODE; // ���� �� �Ϲ� ���� ���� ����
            key_reg   <= 8'hA5;     // �⺻ Ű �� ����
        end else begin
            tx_start <= 1'b0; // �� Ŭ������ �ʱ�ȭ

            // �����Ͱ� ���ŵǾ��� ���� ����
            if (rx_done_tick) begin
                case (state)
                    S_OP_MODE: begin
                        // ���ŵ� �����Ͱ� Ű ���� ��ɾ���
                        if (rx_data == CMD_SET_KEY) begin
                            state <= S_SET_KEY_MODE; // Ű ���� ���� ����
                        end
                        // �Ϲ� �����Ͷ��
                        else begin
                            if (!tx_busy) begin
                                tx_start <= 1'b1;
                                tx_data  <= rx_data ^ key_reg; // ���� ����� Ű�� XOR
                            end
                        end
                    end
                    
                    S_SET_KEY_MODE: begin
                        key_reg <= rx_data; // ���ŵ� �����͸� �� Ű�� ����
                        state   <= S_OP_MODE; // �ٽ� �Ϲ� ���� ���� ����
                    end
                endcase
            end
        end
    end

endmodule