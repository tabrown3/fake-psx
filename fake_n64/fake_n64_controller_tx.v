module fake_n64_controller_tx(
    input sample_clk,
    input cur_operation,
    input [7:0] cmd,
    input [7:0] crc,
    output reg rx_handoff = 1'b0,
    output reg data_tx
);
    localparam LEVEL_WIDTH = 4'h2; // in clk cycles
    localparam BIT_WIDTH = 4'h4*LEVEL_WIDTH; // in clk cycles
    localparam STOP_BIT = {{LEVEL_WIDTH{1'b0}}, {LEVEL_WIDTH{1'b0}}, {LEVEL_WIDTH{1'b1}},
        {LEVEL_WIDTH{1'bz}}}; // L,L,H,Z

    localparam STATE_SIZE = 4; // bits
    // STATES
    localparam [STATE_SIZE-1:0] PREPPING_RESPONSE = {STATE_SIZE{1'b0}};
    localparam [STATE_SIZE-1:0] SENDING_LEVELS = {{STATE_SIZE - 1{1'b0}}, 1'b1};
    localparam [STATE_SIZE-1:0] SENDING_STOP = {{STATE_SIZE - 2{1'b0}}, 2'b10};
    localparam [STATE_SIZE-1:0] FLUSH_CRC = {{STATE_SIZE - 2{1'b0}}, 2'b11};

    reg [STATE_SIZE - 1:0] cur_state = PREPPING_RESPONSE;
    reg level_cnt_reset = 1'b0;
    reg level_cnt_clk = 1'b1;
    wire [2:0] level_cnt;
    reg bit_cnt_reset = 1'b0;
    reg bit_cnt_clk = 1'b1;
    wire [8:0] bit_cnt;
    reg [263:0] tx_byte_buffer; // 33 bytes
    reg [8:0] tx_byte_buffer_length; // 0 to 511
    reg [BIT_WIDTH - 1:0] tx_bit_buffer;

    reg crc_reset = 1'b0;
    reg crc_enable = 1'b1;
    reg crc_clk = 1'b1;
    wire [7:0] complete_crc;
    reg crc_cnt_clk = 1'b1;
    wire [3:0] crc_cnt;

    n_bit_counter #(.BIT_COUNT(3)) LEVEL_CNT0(
        .clk(level_cnt_clk),
        .reset(1'b0),
        .count(level_cnt)
    );
    n_bit_counter #(.BIT_COUNT(9)) BIT_CNT0(.clk(bit_cnt_clk), .reset(bit_cnt_reset), .count(bit_cnt));
    n_bit_counter #(.BIT_COUNT(4)) CRC_CNT0(
        .clk(crc_cnt_clk),
        .reset(1'b0),
        .count(crc_cnt)
    );

    generate_crc CRC0(
        .reset(crc_reset),
        .reset_to(crc),
        .enable(crc_enable),
        .clk(crc_clk),
        .data(1'b0),
        .rem(complete_crc)
    );

    always @(edge sample_clk) begin
        if (cur_operation == 1'b1) begin // Tx   
            if (sample_clk) begin
                level_cnt_clk <= 1'b1;
                level_cnt_reset <= 1'b0;
                bit_cnt_clk <= 1'b1;
                bit_cnt_reset <= 1'b0;
                crc_clk <= 1'b1;
                crc_cnt_clk <= 1'b1;
            end

            if (!sample_clk) begin
                if (cur_state == PREPPING_RESPONSE) begin
                    case (cmd)
                        8'h00, 8'hff: begin
                            tx_byte_buffer <= 24'h050000; // INFO - OEM controller
                            tx_byte_buffer_length <= 9'd24;
                            cur_state <= SENDING_LEVELS;
                        end
                        8'h01: begin
                            tx_byte_buffer <= 32'h00000000; // STATUS - buttons/analog sticks
                            tx_byte_buffer_length <= 9'd32;
                            cur_state <= SENDING_LEVELS;
                        end
                        8'h02: begin // READ
                            tx_byte_buffer <= {9'd264{1'b0}}; // "0" 264 times
                            tx_byte_buffer_length <= 9'd264;
                            cur_state <= SENDING_LEVELS;
                        end
                        8'h03: begin // WRITE
                            tx_byte_buffer_length <= 9'd8;
                            crc_reset <= 1'b1;
                            cur_state <= FLUSH_CRC;
                        end
                    endcase
                end else if (cur_state == SENDING_LEVELS) begin
                    if (level_cnt == 1'b0) begin
                        if (bit_cnt == tx_byte_buffer_length + 1) begin
                            rx_handoff <= ~rx_handoff;
                            cur_state <= PREPPING_RESPONSE;
                            bit_cnt_reset <= 1'b1;
                        end // if all data bits have been transmitted
                        else if (bit_cnt == tx_byte_buffer_length) begin
                            tx_bit_buffer <= STOP_BIT;
                            data_tx <= 1'b0;
                            level_cnt_clk <= 1'b0;
                        end else begin // otherwise load the next data bit
                            tx_bit_buffer <= wire_encoding(
                                tx_byte_buffer[tx_byte_buffer_length - 1 - bit_cnt]
                            );

                            data_tx <= 1'b0;
                            level_cnt_clk <= 1'b0;
                        end
                    end else begin // otherwise transmit the next level in the bit
                        data_tx <= tx_bit_buffer[BIT_WIDTH - 1 - level_cnt];
                        level_cnt_clk <= 1'b0; // and increment level count
                    end
                    
                    if (level_cnt == BIT_WIDTH - 1'b1) begin
                        bit_cnt_clk <= 1'b0; // increment bit count
                        level_cnt_reset <= 1'b1;
                    end 
                end else if (cur_state == FLUSH_CRC) begin
                    if (crc_reset) begin
                        crc_reset <= 1'b0;
                    end else if (crc_cnt == 4'd8) begin
                        tx_byte_buffer <= complete_crc;
                        cur_state <= SENDING_LEVELS;
                    end else begin
                        crc_clk <= 1'b0;
                        crc_cnt_clk <= 1'b0;
                    end
                end
            end
        end
    end

    // LEVEL in this context is physical HIGH or LOW. In the Joybus protocol, bits can
    //  be broken into as many as 4 LEVELs. For instance, logical "0" is LOW-LOW-LOW-HIGH.
    //  LEVEL_WIDTH is the number of cycles each LEVEL remains constant. If LEVEL_WIDTH = 2,
    //  a logical "0" would take 8 clk cycles to transmit: LOW (2 cycles), LOW (2 cycles),
    //  LOW (2 cycles), HIGH (2 cycles). Therefore the BIT_WIDTH is 8 clk cycles, because
    //  it takes 8 cycles to fully transmit a single bit.
    function [BIT_WIDTH - 1:0] wire_encoding (input logic_bit);
        case (logic_bit)
            1'b0: begin // logical 0
                wire_encoding = {{LEVEL_WIDTH{1'b0}}, {LEVEL_WIDTH{1'b0}},
                    {LEVEL_WIDTH{1'b0}}, {LEVEL_WIDTH{1'b1}}}; // L,L,L,H
            end
            1'b1: begin // logical 1
                wire_encoding = {{LEVEL_WIDTH{1'b0}}, {LEVEL_WIDTH{1'b1}},
                    {LEVEL_WIDTH{1'b1}}, {LEVEL_WIDTH{1'b1}}}; // L,H,H,H
            end
        endcase
    endfunction
endmodule