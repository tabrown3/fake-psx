`timescale 1us/10ns
module tb_fake_psx();

    // Testbench variables
    // All idle HIGH
    reg start_btn = 1;
    reg clk = 1;
    wire data;
    wire ack;
    wire psx_clk;
    wire cmd;
    wire att;

    fake_psx PSX(
        .start_btn(start_btn),
        .clk(clk),
        .data(data),
        .ack(ack),
        .psx_clk(psx_clk),
        .cmd(cmd),
        .att(att)
    );

    fake_controller CONT(
        .psx_clk(psx_clk),
        .cmd(cmd),
        .att(att),
        .clk(clk),
        .data(data),
        .ack(ack)
    );

    always begin
        #2; clk = ~clk; // 2us per toggle, 4us period (~250kHz)
    end

    initial begin
        #10; start_btn = 0;
        #5; start_btn = 1;
        #10; start_btn = 0;
        #5; start_btn = 1;
        #10; start_btn = 0;
        #5; start_btn = 1;
        #10; start_btn = 0;
        #5; start_btn = 1;
        #10; start_btn = 0;
        #5; start_btn = 1;
        #10; start_btn = 0;
        #5; start_btn = 1;

        #590; $stop;
    end
endmodule