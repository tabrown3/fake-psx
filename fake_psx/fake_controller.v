module fake_controller
// #(
    //        Bit0 Bit1 Bit2 Bit3 Bit4 Bit5 Bit6 Bit7
    // DATA1: SLCT           STRT UP   RGHT DOWN LEFT
    // DATA1: L2   R2    L1  R1   /\   O    X    |_|
    // source https://gamesx.com/controldata/psxcont/psxcont.htm#CIRCUIT
    // parameter FAKE_DATA1 = 8'b01111111, // Pressed left on d-pad, reversed
    // parameter FAKE_DATA2 = 8'b11111111 // Square thru L2 left unpressed
// )
(
    input psx_clk,
    input att,
    input clk, // this is a fake input to drive the (usually analog) ack
    // NOTE: if using FPGA to emulate controller, this'll be the onboard
    // ... clock; normally this would be governed by an RC circuit
    input [1:0] d_btn,
    output reg data,
    output reg ack
);

    reg [7:0] data0;
    reg [7:0] data1;
    reg [7:0] data2;
    reg [7:0] data3;
    reg [7:0] data4;

    reg [2:0] ack_count;
    reg should_ack;

    wire [5:0] total_bit_counter;
    wire [3:0] ack_delay;

    n_bit_counter #(.BIT_COUNT(6)) CNT0(.clk(psx_clk), .reset(att), .count(total_bit_counter));
    n_bit_counter #(.BIT_COUNT(4)) CNT1(.clk(clk), .reset(!should_ack), .count(ack_delay));

    always @(negedge psx_clk or posedge att)
    begin: SHIFT_REGISTER // SISO w/ preload and async reset
        if (att) begin
            data0 <= 8'hff;
            data1 <= 8'h41;
            data2 <= 8'h5a;
            data3 <= {d_btn[0], 1'b1, d_btn[1], 5'b11111};
            data4 <= 8'b11111111;
            data <= 1'b1;
        end else begin // acts as the register reset
            data4 <= {1'b1, data4[7:1]};
            data3 <= {data4[0], data3[7:1]};
            data2 <= {data3[0], data2[7:1]};
            data1 <= {data2[0], data1[7:1]};
            data0 <= {data1[0], data0[7:1]};
            data <= data0[0];
        end
    end

    always @(negedge clk) begin
        if (total_bit_counter == 0) begin
            ack <= 1'b1;
            ack_count <= 1;
            should_ack <= 0;
        end else if (!att && (total_bit_counter == 32 || total_bit_counter == 24 ||
            total_bit_counter == 16 || total_bit_counter == 8)) begin
            if (total_bit_counter >> 3 == ack_count) begin // total_bit_counter / 8
                ack_count <= ack_count + 3'd1;
                should_ack <= 1;
            end
        end

        if (should_ack) begin
            if (ack && ack_delay > 4'd2) begin
                ack <= 1'b0;
            end else if (!ack) begin
                ack <= 1'b1;
                should_ack <= 0;
            end
        end
    end
endmodule