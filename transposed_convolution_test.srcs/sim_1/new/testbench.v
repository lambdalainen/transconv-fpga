`timescale 1ns / 1ps

module testbench();

localparam T = 10; // 100MHz = 10ns period

reg clk, reset;
wire we;
wire [15:0] addr_a, addr_b, addr_c;
reg [15:0] addr_result;
wire [7:0] a, b;
wire [31:0] c, result;
wire done_tick;
reg btn_tick;

bram #(.ADDR_WIDTH(16), .DATA_WIDTH(8), .DATA_FILE("input_1_uint8.data")) bram_lhs
    (.clk(clk), .we(1'b0), .addr_a(addr_a), .addr_b(16'd0), .din_a(8'd0), .dout_a(a), .dout_b());

bram #(.ADDR_WIDTH(16), .DATA_WIDTH(8), .DATA_FILE("weight_1_uint8.data")) bram_rhs
    (.clk(clk), .we(1'b0), .addr_a(16'd0), .addr_b(addr_b), .din_a(8'd0), .dout_a(), .dout_b(b));

bram #(.ADDR_WIDTH(16), .DATA_WIDTH(32)) bram_res
        (.clk(clk), .we(we), .addr_a(addr_c), .addr_b(addr_result), .din_a(c), .dout_a(), .dout_b(result));

sparse_gemm mm_unit
    (.clk(clk), .reset(reset), .start_tick(btn_tick), .m(14'd9), .k(14'd1), .n(14'd4),
     .n_output_plane(10'd1), .output_h(7'd4), .output_w(7'd4), .input_h(7'd3), .input_w(7'd3),
     .kernel_h(3'd2), .kernel_w(3'd2), .pad_h(3'd1), .pad_w(3'd1),
     .stride_h(3'd2), .stride_w(3'd2), .dilation_h(3'd1), .dilation_w(3'd1), .a(a), .b(b),
     .a_rd_addr(addr_a), .b_rd_addr(addr_b), .c(c), .c_wr_en(we), .c_wr_addr(addr_c), .done_tick(done_tick));

always
begin
    clk = 1'b1;
    #(T/2);
    clk = 1'b0;
    #(T/2);
end

// reset for the first half cycle
initial
begin
reset = 1'b1;
#(T/2);
reset = 1'b0;
end

// other stimulus
initial
begin
    // initial input
    addr_result = 16'd0;
    btn_tick = 1'b0;
    // wait for reset to deassert
    @(negedge  reset);
    // wait for 1 clock
    @(negedge clk);
    btn_tick = 1'b1;
    @(negedge clk);
    btn_tick = 1'b0;
    wait(done_tick);
    @(negedge clk);
    addr_result = 16'd1;
    @(negedge clk);
    addr_result = 16'd2;
    @(negedge clk);
    addr_result = 16'd3;
    @(negedge clk);
    addr_result = 16'd4;
end

endmodule
