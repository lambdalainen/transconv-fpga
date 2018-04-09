`timescale 1ns / 1ps

module sparse_gemm
#(
    parameter ADDR_WIDTH = 16, // 2^16 = 65536
              DATA_WIDTH = 8,
              ACC_WIDTH = 32,
              MKN_WIDTH = 14, // max 2^14 - 1 = 16383, our max row/col number is 8192
              N_OUT_PLANE_WIDTH = 10,
              INOUT_WH_WIDTH = 7,
              MISC_WIDTH = 3
)
(
    input wire clk,
    input wire reset,
    input wire start_tick,
    input wire [MKN_WIDTH-1:0] m,
    input wire [MKN_WIDTH-1:0] k,
    input wire [MKN_WIDTH-1:0] n,
    input wire [N_OUT_PLANE_WIDTH-1:0] n_output_plane,
    input wire [INOUT_WH_WIDTH-1:0] output_h,
    input wire [INOUT_WH_WIDTH-1:0] output_w,
    input wire [INOUT_WH_WIDTH-1:0] input_h,
    input wire [INOUT_WH_WIDTH-1:0] input_w,
    input wire [MISC_WIDTH-1:0] kernel_h,
    input wire [MISC_WIDTH-1:0] kernel_w,
    input wire [MISC_WIDTH-1:0] pad_h,
    input wire [MISC_WIDTH-1:0] pad_w,
    input wire [MISC_WIDTH-1:0] stride_h,
    input wire [MISC_WIDTH-1:0] stride_w,
    input wire [MISC_WIDTH-1:0] dilation_h,
    input wire [MISC_WIDTH-1:0] dilation_w,
    input wire [DATA_WIDTH-1:0] a,
    input wire [DATA_WIDTH-1:0] b,
    output wire [ADDR_WIDTH-1:0] a_rd_addr,
    output wire [ADDR_WIDTH-1:0] b_rd_addr,
    output wire [ACC_WIDTH-1:0] c,
    output wire c_wr_en,
    output wire [ADDR_WIDTH-1:0] c_wr_addr,
    output reg done_tick
);

localparam [1:0]
    idle = 2'b00,
    load = 2'b01,
    done = 2'b10;

reg [1:0] state, state_next;
reg [ADDR_WIDTH-1:0] a_rd_addr_reg, a_rd_addr_next;
reg [ADDR_WIDTH-1:0] b_rd_addr_reg, b_rd_addr_next;
reg [ACC_WIDTH-1:0] c_reg, c_reg_next;
reg c_wr_en_reg, c_wr_en_next;
reg [ADDR_WIDTH-1:0] c_wr_addr_reg, c_wr_addr_next;
reg [MKN_WIDTH-1:0] row, row_next;
reg [MKN_WIDTH-1:0] col, col_next;
reg [MKN_WIDTH-1:0] i, i_next;

reg [N_OUT_PLANE_WIDTH-1:0] c_im, c_im_next;
reg [MISC_WIDTH-1:0] h_offset, h_offset_next;
reg [MISC_WIDTH-1:0] w_offset, w_offset_next;
reg [INOUT_WH_WIDTH-1:0] h_col, h_col_next;
reg [INOUT_WH_WIDTH-1:0] w_col, w_col_next;
reg [INOUT_WH_WIDTH-1:0] h_im, w_im;

always @(posedge clk, posedge reset)
begin
    if (reset)
        begin
            state <= idle;
            a_rd_addr_reg <= 0;
            b_rd_addr_reg <= 0;
            c_reg <= 0;
            c_wr_en_reg <= 0;
            c_wr_addr_reg <= 0;
            row <= 0;
            col <= 0;
            i <= 0;

            c_im <= 0;
            h_offset <= 0;
            w_offset <= 0;
            h_col <= 0;
            w_col <= 0;
            // no need to reset done_tick (see debounce.v, for example)
        end
    else
        begin
            state <= state_next;
            a_rd_addr_reg <= a_rd_addr_next;
            b_rd_addr_reg <= b_rd_addr_next;
            c_reg <= c_reg_next;
            c_wr_en_reg <= c_wr_en_next;
            c_wr_addr_reg <= c_wr_addr_next;
            row <= row_next;
            col <= col_next;
            i <= i_next;

            c_im <= c_im_next;
            h_offset <= h_offset_next;
            w_offset <= w_offset_next;
            h_col <= h_col_next;
            w_col <= w_col_next;
        end
end

task inner_loop;
    begin
        if (w_col == input_w - 1)
            begin
                h_col_next = h_col + 1;
                w_col_next = 0;
            end
        else
            begin
                w_col_next = w_col + 1;
            end
    end
endtask

task inner_loop2;
    begin
        if (h_col == input_h - 1)
            begin
                if (w_col == input_w - 1)
                    begin
                        w_offset_next = w_offset + 1;
                        h_col_next = 0;
                        w_col_next = 0;
                    end
                else
                    begin
                        w_col_next = w_col + 1;
                    end
            end
        else
            inner_loop();
    end
endtask

task inner_loop3;
    begin
        if (w_offset == kernel_w - 1)
            begin
                if (h_col == input_h - 1)
                    begin
                        if (w_col == input_w - 1)
                            begin
                                h_offset_next = h_offset + 1;
                                w_offset_next = 0;
                                h_col_next = 0;
                                w_col_next = 0;
                            end
                        else
                            begin
                                w_col_next = w_col + 1;
                            end
                    end
                else
                    inner_loop();
            end
        else
            inner_loop2();
    end
endtask

always @*
begin
    state_next = state;
    a_rd_addr_next = a_rd_addr_reg;
    b_rd_addr_next = b_rd_addr_reg;
    c_reg_next = c_reg;
    c_wr_en_next = 1'b0; // a tick
    c_wr_addr_next = c_wr_addr_reg;
    row_next = row;
    col_next = col;
    i_next = i;

    c_im_next = c_im;
    h_offset_next = h_offset;
    w_offset_next = w_offset;
    h_col_next = h_col;
    w_col_next = w_col;

    // direct output signals
    done_tick = 1'b0;
    case (state)
        idle:
            begin
                if (start_tick)
                    begin
                        state_next = load;
                        a_rd_addr_next = 0;
                        b_rd_addr_next = 0;
                        // No need to set these two
                        // c_reg_next = 0;
                        // c_wr_en_next = 1'b0;
                        c_wr_addr_next = -1;
                        row_next = 0;
                        col_next = 0;
                        i_next = 0;

                        c_im_next = 0;
                        h_offset_next = 0;
                        w_offset_next = 0;
                        h_col_next = 0;
                        w_col_next = 0;
                    end
            end
        load:
            begin
                if (c_im == n_output_plane - 1)
                    begin
                        if (h_offset == kernel_h - 1)
                            begin
                                if (w_offset == kernel_w - 1)
                                    begin
                                        if (h_col == input_h - 1)
                                            begin
                                                if (w_col == input_w - 1)
                                                    begin
                                                        //state_next = done;
                                                    end
                                                else
                                                    begin
                                                        w_col_next = w_col + 1;
                                                    end
                                            end
                                        else
                                            inner_loop();
                                    end
                                else
                                    inner_loop2();
                            end
                        else
                            inner_loop3();
                    end
                else
                    begin
                        if (h_offset == kernel_h - 1)
                            begin
                                if (w_offset == kernel_w - 1)
                                    begin
                                        if (h_col == input_h - 1)
                                            begin
                                                if (w_col == input_w - 1)
                                                    begin
                                                        c_im_next = c_im + 1;
                                                        h_offset_next = 0;
                                                        w_offset_next = 0;
                                                        h_col_next = 0;
                                                        w_col_next = 0;
                                                    end
                                                else
                                                    begin
                                                        w_col_next = w_col + 1;
                                                    end
                                            end
                                        else
                                            inner_loop();
                                    end
                                else
                                    inner_loop2();
                            end
                        else
                            inner_loop3();
                    end

                if (i == k - 1) // test this case first since when k == 1, i == 0
                    begin
                        if (i == 0)
                            c_reg_next = a * b;
                        else
                            c_reg_next = c_reg + a * b;
                        i_next = 0;
                        // the next c_reg value should be written to the next address
                        c_wr_en_next = 1'b1;
                        c_wr_addr_next = c_wr_addr_reg + 1;

                        if (row == m - 1)
                            if (col == n - 1)
                                state_next = done;
                            else
                                col_next = col + 1;
                        else
                            if (col == n - 1)
                                begin
                                    row_next = row + 1;
                                    col_next = 0;
                                end
                            else
                                col_next = col + 1;
                    end
                else if (i == 0)
                    begin
                        c_reg_next = a * b;
                        i_next = i + 1;
                    end
                else
                    begin
                        c_reg_next = c_reg + a * b;
                        i_next = i + 1;
                    end

                a_rd_addr_next = row_next * k + i_next;
                b_rd_addr_next = col_next * k + i_next;
            end
        done:
            begin
                state_next = idle;
                done_tick = 1'b1;
            end
    endcase
end

// The reason that we assign a_rd_addr to a_rd_addr_next instead of a_rd_addr_reg is so that
// a will be immediately available in the next cycle. Otherwise it's 2 DFF cascaded and a will
// be delayed a cycle.
assign a_rd_addr = a_rd_addr_next;
assign b_rd_addr = b_rd_addr_next;
assign c = c_reg;
assign c_wr_en = c_wr_en_reg;
assign c_wr_addr = c_wr_addr_reg;

endmodule
