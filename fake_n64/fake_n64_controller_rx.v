module fake_n64_controller_rx
(
    input cur_operation,
    input data_rx,
    input sample_clk,
    output reg tx_handoff = 1'b0,
    output reg [7:0] cmd = 8'hfe,
    output reg [15:0] address = 16'h0000,
    output reg [7:0] crc
);
    localparam BIT_CNT_SIZE = 9;

    wire derived_signal;
    wire derived_clk;
    wire bit_cnt_reset;
    wire [BIT_CNT_SIZE-1:0] bit_cnt;
    wire crc_reset;
    reg crc_enable = 1'b0;
    wire [7:0] rem;

    n_bit_counter #(.BIT_COUNT(BIT_CNT_SIZE)) BIT_CNT0(
        .clk(derived_clk),
        .reset(bit_cnt_reset),
        .count(bit_cnt)
    );

    async_to_sync ASYNC0(
        .cur_operation(cur_operation),
        .data(data_rx),
        .sample_clk(sample_clk),
        .derived_signal(derived_signal),
        .derived_clk(derived_clk)
    );

    generate_crc CRC0(
        .reset(crc_reset),
        .enable(crc_enable),
        .clk(derived_clk),
        .data(derived_signal),
        .rem(rem)
    );

    assign bit_cnt_reset = ((cmd == 8'h00 || cmd == 8'h01 || cmd == 8'hff) && bit_cnt == 4'd9) ||
        (cmd == 8'h02 && bit_cnt == 5'd25) ||
        (cmd == 8'h03 && bit_cnt == 9'd281);

    assign crc_reset = cmd == 8'h03 && bit_cnt == 9'd281;

    always @(negedge derived_clk) begin
        if (bit_cnt >= 9'h08) begin
            case (cmd)
                8'h00, 8'h01, 8'hff: begin // INFO, BUTTON STATUS, RESET
                    tx_handoff <= ~tx_handoff;
                end
                8'h02: begin // READ
                    if (bit_cnt < 9'd24) begin
                        address[6'd23 - bit_cnt] <= derived_signal;
                    end else begin
                        tx_handoff <= ~tx_handoff;
                    end
                end
                8'h03: begin // WRITE
                    if (bit_cnt < 9'd24) begin
                        address[6'd23 - bit_cnt] <= derived_signal;

                        if (bit_cnt == 9'd23) begin
                            crc_enable <= 1'b1;
                        end
                    end else if (bit_cnt == 9'd279) begin
                        crc_enable <= 1'b0;
                    end else if (bit_cnt == 9'd280) begin
                        crc <= rem;
                        tx_handoff <= ~tx_handoff;
                    end
                end
            endcase
        end else begin
            cmd[9'h07 - bit_cnt] <= derived_signal;
        end
    end
endmodule