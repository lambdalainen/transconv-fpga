`timescale 1ns / 1ps

module top
(
    input wire clk,
    input wire btnC, btnU,
    output wire [0:0] led,
    output wire [7:0] an,
    output wire dp,
    output wire [6:0] seg
);

wire we;
wire [15:0] addr_a, addr_b, addr_c;
reg [15:0] addr_result = 0;
wire [7:0] a, b;
wire [31:0] c, result;
wire done_tick;
reg led_reg = 0;
wire btn_c_tick, btn_u_tick;

bram #(.ADDR_WIDTH(16), .DATA_WIDTH(8), .DATA_FILE("input_1_uint8.data")) bram_lhs
    (.clk(clk), .we(1'b0), .addr_a(addr_a), .addr_b(16'd0), .din_a(8'd0), .dout_a(a), .dout_b());

bram #(.ADDR_WIDTH(16), .DATA_WIDTH(8), .DATA_FILE("weight_1_uint8.data")) bram_rhs
    (.clk(clk), .we(1'b0), .addr_a(16'd0), .addr_b(addr_b), .din_a(8'd0), .dout_a(), .dout_b(b));

bram #(.ADDR_WIDTH(16), .DATA_WIDTH(32)) bram_res
        (.clk(clk), .we(we), .addr_a(addr_c), .addr_b(addr_result), .din_a(c), .dout_a(), .dout_b(result));

sparse_gemm mm_unit
    (.clk(clk), .reset(1'b0), .m(14'd256), .k(14'd256), .n(14'd256), .start_tick(btn_c_tick),
     .a(a), .b(b), .a_rd_addr(addr_a), .b_rd_addr(addr_b), .c(c), .c_wr_en(we), .c_wr_addr(addr_c), .done_tick(done_tick));

disp_hex_mux disp_unit (
    .clk(clk), .reset(1'b0),
    .hex7(result[31:28]), .hex6(result[27:24]), .hex5(result[23:20]), .hex4(result[19:16]),
    .hex3(result[15:12]), .hex2(result[11:8]), .hex1(result[7:4]), .hex0(result[3:0]),
    .dp_in(8'hFF), .an(an), .dp(dp), .seg(seg));

debounce debounce_btn_c (
    .clk(clk), .reset(1'b0), .sw(btnC), .db_level(), .db_tick(btn_c_tick));

debounce debounce_btn_u (
    .clk(clk), .reset(1'b0), .sw(btnU), .db_level(), .db_tick(btn_u_tick));

always @(posedge clk)
begin
    if (done_tick)
        led_reg <= 1;
    if (btn_u_tick)
        addr_result <= addr_result + 1;
end

assign led = led_reg;

endmodule
