//------------------------------------------------------------------------------
// Simple UART RX/TX for 8-N-1, parameterisable baud.
//------------------------------------------------------------------------------

//=============== UART RX ======================================================
module uart_rx #(
    parameter CLKS_PER_BIT = 434  // (clk freq / baud rate)
)(
    input  wire clk,
    input  wire rst_n,
    input  wire rx_serial,
    output reg  [7:0] rx_data,
    output reg        rx_valid
);

    localparam IDLE  = 2'd0,
               START = 2'd1,
               DATA  = 2'd2,
               STOP  = 2'd3;

    reg [1:0] state;
    reg [$clog2(CLKS_PER_BIT)-1:0] clk_cnt;
    reg [2:0] bit_idx;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state   <= IDLE;
            clk_cnt <= 0;
            bit_idx <= 0;
            rx_valid<= 0;
        end else begin
            rx_valid <= 0;
            case(state)
                IDLE: begin
                    if(~rx_serial) begin       // start bit detected (low)
                        state   <= START;
                        clk_cnt <= CLKS_PER_BIT>>1; // sample mid-bit
                    end
                end
                START: begin
                    if(clk_cnt==0) begin
                        clk_cnt <= CLKS_PER_BIT-1;
                        bit_idx <= 0;
                        state   <= DATA;
                    end else clk_cnt<=clk_cnt-1;
                end
                DATA: begin
                    if(clk_cnt==0) begin
                        clk_cnt <= CLKS_PER_BIT-1;
                        rx_data[bit_idx] <= rx_serial;
                        if(bit_idx==3'd7) state<=STOP;
                        bit_idx<=bit_idx+1;
                    end else clk_cnt<=clk_cnt-1;
                end
                STOP: begin
                    if(clk_cnt==0) begin
                        state   <= IDLE;
                        rx_valid<= 1'b1;      // one-cycle pulse
                    end else clk_cnt<=clk_cnt-1;
                end
            endcase
        end
    end
endmodule

//=============== UART TX ======================================================
module uart_tx #(
    parameter CLKS_PER_BIT = 434
)(
    input  wire clk,
    input  wire rst_n,
    input  wire tx_start,
    input  wire [7:0] tx_data,
    output reg  tx_serial,
    output reg  tx_busy
);

    localparam IDLE  = 2'd0,
               START = 2'd1,
               DATA  = 2'd2,
               STOP  = 2'd3;

    reg [1:0] state;
    reg [$clog2(CLKS_PER_BIT)-1:0] clk_cnt;
    reg [2:0] bit_idx;
    reg [7:0] data_buf;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state     <= IDLE;
            tx_serial <= 1'b1; // idle high
            tx_busy   <= 1'b0;
            clk_cnt   <= 0;
            bit_idx   <= 0;
        end else begin
            case(state)
                IDLE: begin
                    tx_serial <= 1'b1;
                    tx_busy   <= 1'b0;
                    if(tx_start) begin
                        data_buf <= tx_data;
                        clk_cnt  <= CLKS_PER_BIT-1;
                        state    <= START;
                        tx_busy  <= 1'b1;
                    end
                end
                START: begin
                    tx_serial <= 1'b0; // start bit low
                    if(clk_cnt==0) begin
                        clk_cnt <= CLKS_PER_BIT-1;
                        bit_idx <= 0;
                        state   <= DATA;
                    end else clk_cnt<=clk_cnt-1;
                end
                DATA: begin
                    tx_serial <= data_buf[bit_idx];
                    if(clk_cnt==0) begin
                        clk_cnt <= CLKS_PER_BIT-1;
                        if(bit_idx==3'd7) state<=STOP;
                        bit_idx<=bit_idx+1;
                    end else clk_cnt<=clk_cnt-1;
                end
                STOP: begin
                    tx_serial <= 1'b1; // stop bit high
                    if(clk_cnt==0) begin
                        state <= IDLE;
                    end else clk_cnt<=clk_cnt-1;
                end
            endcase
        end
    end
endmodule
