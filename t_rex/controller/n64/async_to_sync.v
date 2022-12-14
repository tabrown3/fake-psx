`include "../../common/n_bit_counter.v"
module async_to_sync(
    input read_ack,
    input cur_operation,
    input data,
    input sample_clk,
    output reg derived_signal = 1'b1,
    output reg derived_clk = 1'b1,
    output reg tx_handoff = 1'b0
);
    localparam STATE_SIZE = 4; // bits
    // STATES
    localparam [STATE_SIZE-1:0] AWAITING_FIRST_BIT = {STATE_SIZE{1'b0}};
    localparam [STATE_SIZE-1:0] READING_BIT_LOW = {{STATE_SIZE - 1{1'b0}}, 1'b1};
    localparam [STATE_SIZE-1:0] READING_BIT_HIGH = {{STATE_SIZE - 2{1'b0}}, 2'b10};
    // END STATES

    // CURRENT STATE
    reg [STATE_SIZE-1:0] cur_state = AWAITING_FIRST_BIT;
    wire low_cnt_clk;
    wire high_cnt_clk;
    wire [5:0] low_cnt;
    wire [5:0] high_cnt;
    reg reset_low_cnt = 1'b0;
    reg reset_high_cnt = 1'b0;
    reg [5:0] low_cnt_latch = 6'h00;

    reg [STATE_SIZE-1:0] next_state = AWAITING_FIRST_BIT;

    n_bit_counter LOW_CNT0(.clk(low_cnt_clk), .reset(reset_low_cnt), .count(low_cnt));
    n_bit_counter HIGH_CNT0(.clk(high_cnt_clk), .reset(reset_high_cnt), .count(high_cnt));

    assign low_cnt_clk = cur_state == READING_BIT_LOW ? sample_clk : 1'b1;
    assign high_cnt_clk = cur_state == READING_BIT_HIGH ? sample_clk : 1'b1;

    always @(posedge sample_clk) begin
        cur_state <= next_state;
    end

    always @(negedge sample_clk or posedge read_ack) begin
        if (read_ack) begin
            derived_clk <= 1'b1;
        end else if (cur_operation == 1'b0) begin // Rx
            case (cur_state)
                AWAITING_FIRST_BIT: begin
                    if (!data) begin
                        next_state <= READING_BIT_LOW;
                        reset_low_cnt <= 1'b0;
                        reset_high_cnt <= 1'b0;
                    end
                end
                READING_BIT_LOW: begin
                    if (data) begin
                        reset_high_cnt <= 1'b0;
                        next_state <= READING_BIT_HIGH;

                        low_cnt_latch <= low_cnt;
                        reset_low_cnt <= 1'b1;
                    end
                end
                READING_BIT_HIGH: begin
                    if (!data) begin
                        reset_low_cnt <= 1'b0;
                        next_state <= READING_BIT_LOW;

                        derived_clk <= 1'b0;
                        reset_high_cnt <= 1'b1;
                        if (low_cnt_latch > high_cnt) begin
                            derived_signal <= 1'b0;
                        end else begin
                            derived_signal <= 1'b1;
                        end
                    end else if (high_cnt > 4'd8) begin
                        reset_low_cnt <= 1'b1;
                        reset_high_cnt <= 1'b1;
                        low_cnt_latch <= 6'h00;

                        derived_clk <= 1'b0;
                        
                        tx_handoff <= ~tx_handoff;
                        next_state <= AWAITING_FIRST_BIT;
                    end
                end
            endcase
        end
    end
endmodule