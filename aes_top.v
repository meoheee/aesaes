module uart_aes_top(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        uart_rx,
    output wire        uart_tx
);
parameter CLK_FREQ = 50000000;
parameter BAUD     = 115200;
localparam CLKS_PER_BIT = CLK_FREQ/BAUD;

//--------------------------------------------------
// UART RX
//--------------------------------------------------
wire [7:0] rx_d;
wire       rx_v;
reg  [7:0] blk [0:15];
reg  [3:0] idx;
reg        start;
reg  [127:0] pt;

uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
    .clk(clk), .rst_n(rst_n), .rx_serial(uart_rx),
    .rx_data(rx_d), .rx_valid(rx_v)
);

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        idx<=0; start<=0;
    end else begin
        start<=0;
        if(rx_v) begin
            blk[idx] <= rx_d;
            idx      <= idx + 1'b1;
            if(idx==4'd15) begin
                pt   <= {blk[0],blk[1],blk[2],blk[3],blk[4],blk[5],blk[6],blk[7],
                         blk[8],blk[9],blk[10],blk[11],blk[12],blk[13],blk[14],rx_d};
                start<=1'b1;
                idx  <= 4'd0;
            end
        end
    end
end

//--------------------------------------------------
// AES CORE (Secworks) 
//--------------------------------------------------
// keylen : 0 = 128bit, 1 = 256bit
wire [127:0] ct;
wire         ready;

aes_core u_aes (
    .clk    (clk),
    .reset_n(rst_n),
    .init   (start),
    .next   (1'b0),
    .encdec (1'b1),        // 1 = encrypt
    .keylen (1'b0),        // 0 = AES-128
    .key    (128'h0011_2233_4455_6677_8899_aabb_ccdd_eeff),
    .block  (pt),
    .ready  (ready),
    .result (ct)
);

//--------------------------------------------------
// UART TX
//--------------------------------------------------
reg  [127:0] tx_buf;
reg  [4:0]   tx_idx;
reg          tx_start;
wire         tx_busy;

uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
    .clk(clk), .rst_n(rst_n), .tx_start(tx_start),
    .tx_data(tx_buf[7:0]), .tx_serial(uart_tx), .tx_busy(tx_busy)
);

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        tx_start<=0; tx_idx<=0; tx_buf<=0;
    end else begin
        tx_start<=0;
        if(ready) begin
            tx_buf <= ct;
            tx_idx <= 0;
        end else if(tx_idx < 16 && !tx_busy) begin
            tx_start <= 1;
            tx_buf   <= tx_buf >> 8;
            tx_idx   <= tx_idx + 1'b1;
        end
    end
end
endmodule
