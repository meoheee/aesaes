

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

            o_rx_done <= 1'b0;
            
            case(state)
                S_IDLE: begin
                    if (!rxd_sync) begin
                        state       <= S_START;
                        clk_counter <= 0;
                    end
                end

                S_START: begin

                    if (clk_counter < (CLKS_PER_BIT / 2) - 1) begin
                        clk_counter <= clk_counter + 1;
                    end else begin

                        if (!rxd_sync) begin
                            state       <= S_DATA;
                            bit_index   <= 0;
                            clk_counter <= 0; 
                        end else begin
                            state <= S_IDLE;
                        end
                    end
                end

                S_DATA: begin

                    if (clk_counter < CLKS_PER_BIT - 1) begin
                        clk_counter <= clk_counter + 1;
                    end else begin

                        rx_buffer[bit_index] <= rxd_sync;
                        clk_counter <= 0;

                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            state <= S_STOP; 
                        end
                    end
                end
                
                S_STOP: begin

                    if (clk_counter < CLKS_PER_BIT - 1) begin
                        clk_counter <= clk_counter + 1;
                    end else begin
                        state     <= S_IDLE; 
                        o_rx_done <= 1'b1;  
                        o_rx_data <= rx_buffer;
                    end
                end
            endcase
        end
    end
endmodule