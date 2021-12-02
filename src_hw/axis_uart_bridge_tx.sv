`timescale 1ns / 1ps

module axis_uart_bridge_tx #(
    parameter UART_SPEED    = 115200   ,
    parameter FREQ_HZ       = 100000000,
    parameter N_BYTES       = 32       ,
    parameter QUEUE_DEPTH   = 16       ,
    parameter QUEUE_MEMTYPE = "block"  ,  // "distributed", "auto"
    parameter REGISTER_LEN  = 1
) (
    input                          clk          ,
    input                          reset        ,
    input        [(N_BYTES*8)-1:0] S_AXIS_TDATA ,
    input                          S_AXIS_TVALID,
    output logic                   S_AXIS_TREADY,
    output logic                   UART_TX
);

    localparam CLOCK_DURATION = (FREQ_HZ/UART_SPEED);
    localparam DATA_WIDTH     = (N_BYTES*8)         ;

    typedef enum {
        IDLE_ST,
        START_ST,
        DATA_ST,
        STOP_ST,
        STUB_ST
    } tx_fsm;

    tx_fsm current_state_tx = IDLE_ST;

    logic [31:0] clock_counter = '{default:0};
    logic        clock_event   = 1'b0        ;

    // interface for transmit
    logic [    DATA_WIDTH-1:0] in_dout_data             ;
    logic [    DATA_WIDTH-1:0] in_dout_data_shift       ;
    logic [(DATA_WIDTH/8)-1:0] in_dout_keep             ;
    logic                      in_rden            = 1'b0;
    logic                      in_empty                 ;

    // data_bit_counter 
    logic [ 2:0] data_bit_counter = '{default:0};
    logic [31:0] byte_counter     = '{default:0};

    logic internal_uart_tx;

    generate 
        if (REGISTER_LEN == 0) begin : GEN_UNREGISTERED_OUTPUT
            always_comb begin 
                UART_TX = internal_uart_tx;
            end 
        end 
    endgenerate

    generate 
        if (REGISTER_LEN > 1) begin : GEN_REGISTERED_OUTPUT     

            logic [REGISTER_LEN-1:0] registered_uart_tx;

            always_ff @(posedge clk) begin 
                registered_uart_tx <= {registered_uart_tx[REGISTER_LEN-2:0], internal_uart_tx};
            end 

            always_comb begin 
                UART_TX = registered_uart_tx[REGISTER_LEN-1];
            end 

        end 
    endgenerate

    generate 
        if (REGISTER_LEN == 1) begin
            always_ff @(posedge clk) begin 
                UART_TX <= internal_uart_tx;
            end 
        end 
    endgenerate


    always_ff @(posedge clk) begin : uart_tx_proc 
        if (reset) begin 
            internal_uart_tx <= 1'b1;
        end else begin 
            case (current_state_tx)
                IDLE_ST : 
                    if (clock_event) begin 
                        if (~in_empty) begin 
                            internal_uart_tx <= 1'b0;
                        end else begin 
                            internal_uart_tx <= 1'b1;
                        end 
                    end else begin 
                        internal_uart_tx <= internal_uart_tx;
                    end 

                START_ST : 
                    if (clock_event) begin 
                        internal_uart_tx <= in_dout_data_shift[0];
                    end else begin 
                        internal_uart_tx <= internal_uart_tx;
                    end 

                DATA_ST : 
                    if (clock_event) begin 
                        if (data_bit_counter == 7) begin 
                            internal_uart_tx <= 1'b1;
                        end else begin 
                            internal_uart_tx <= in_dout_data_shift[0];
                        end 
                    end else begin 
                        internal_uart_tx <= internal_uart_tx;
                    end 

                STOP_ST: 
                    if (clock_event) begin 
                        if (byte_counter == N_BYTES) begin
                            if (~in_empty) begin 
                                internal_uart_tx <= 1'b0;
                            end else begin  
                                internal_uart_tx <= 1'b1; // если в очереди еще есть данные
                            end 
                        end else begin 
                            internal_uart_tx <= 1'b0;
                        end 
                    end else begin 
                        internal_uart_tx <= internal_uart_tx;
                    end 

                default : 
                    internal_uart_tx <= 1'b1;

            endcase // current_state_tx
        end 
    end 

    always_ff @(posedge clk) begin : clock_counter_proc 
        if (reset) begin 
            clock_counter <= '{default:0};
        end else begin 
            if (clock_counter < (CLOCK_DURATION-1)) begin 
                clock_counter <= clock_counter + 1;
            end else begin 
                clock_counter <= '{default:0};
            end 
        end 
    end

    always_ff @(posedge clk) begin : clock_event_proc 
        if (reset) begin 
            clock_event <= 1'b0;
        end else begin 
            if (clock_counter < (CLOCK_DURATION-1)) begin 
                clock_event <= 1'b0;
            end else begin 
                clock_event <= 1'b1;
            end 
        end 
    end 

    always_ff @(posedge clk) begin : current_state_tx_proc
        if (reset) begin 
            current_state_tx <= IDLE_ST;
        end else begin 

            case (current_state_tx)
                IDLE_ST : 
                    if (clock_event) begin 
                        if (~in_empty) begin 
                            current_state_tx <= START_ST;
                        end else begin 
                            current_state_tx <= current_state_tx;
                        end 
                    end else begin 
                        current_state_tx <= current_state_tx;
                    end 

                START_ST : 
                    if (clock_event) begin 
                        current_state_tx <= DATA_ST;
                    end else begin 
                        current_state_tx <= current_state_tx;
                    end 

                DATA_ST :
                    if (clock_event) begin 
                        if (data_bit_counter == 7) begin 
                            current_state_tx <= STOP_ST;
                        end else begin 
                            current_state_tx <= current_state_tx;
                        end 
                    end else begin 
                        current_state_tx <= current_state_tx;
                    end 

                STOP_ST :
                    if (clock_event) begin 
                        if (byte_counter == N_BYTES) begin 
                            if (~in_empty) begin 
                                current_state_tx <= START_ST;
                            end else begin 
                                current_state_tx <= IDLE_ST;
                            end 
                        end else begin 
                            current_state_tx <= START_ST;
                        end 
                    end else begin
                        current_state_tx <= current_state_tx;
                    end

                STUB_ST : 
                    current_state_tx <= current_state_tx;

                default: current_state_tx <= current_state_tx;

            endcase // current_state_tx

        end 
    end 

    always_ff @(posedge clk) begin : data_bit_counter_proc 
        case (current_state_tx)
            DATA_ST : 
                if (clock_event) begin 
                    data_bit_counter <= data_bit_counter + 1;
                end else begin 
                    data_bit_counter <= data_bit_counter;
                end 

            default:
                data_bit_counter <= '{default:0};

        endcase // current_state_tx
    end

    always_ff @(posedge clk) begin : byte_counter_proc 
        if (reset) begin
            byte_counter <= '{default:0};
        end else begin 
            case (current_state_tx)

                IDLE_ST : 
                    byte_counter <= '{default:0};

                DATA_ST: 
                    if (clock_event) begin 
                        if (data_bit_counter == 7) begin 
                            byte_counter <= byte_counter + 1;
                        end else begin 
                            byte_counter <= byte_counter;
                        end 
                    end else begin 
                        byte_counter <= byte_counter;
                    end

                STOP_ST: 
                    if (clock_event) begin 
                        if (byte_counter == N_BYTES) begin 
                            byte_counter <= '{default:0};
                        end else begin 
                            byte_counter <= byte_counter;
                        end 
                    end else begin 
                        byte_counter <= byte_counter;
                    end 

                default: 
                    byte_counter <= byte_counter;
            endcase // current_state_tx
        end 
    end 

    fifo_in_sync_xpm #(
        .DATA_WIDTH(DATA_WIDTH   ),
        .MEMTYPE   (QUEUE_MEMTYPE),
        .DEPTH     (QUEUE_DEPTH  )
    ) fifo_in_sync_xpm_inst (
        .CLK          (clk          ),
        .RESET        (reset        ),
        .S_AXIS_TDATA (S_AXIS_TDATA ),
        .S_AXIS_TKEEP ('b0          ),
        .S_AXIS_TVALID(S_AXIS_TVALID),
        .S_AXIS_TLAST (1'b0         ),
        .S_AXIS_TREADY(S_AXIS_TREADY),
        .IN_DOUT_DATA (in_dout_data ),
        .IN_DOUT_KEEP (in_dout_keep ),
        .IN_DOUT_LAST (             ),
        .IN_RDEN      (in_rden      ),
        .IN_EMPTY     (in_empty     )
    );

    always_ff @(posedge clk) begin 
        if (reset) begin 
            in_rden <= 1'b0;
        end else begin 
            case (current_state_tx)
                START_ST :
                    if (clock_event) begin 
                        if (byte_counter == 0) begin 
                            in_rden <= 1'b1;
                        end else begin 
                            in_rden <= 1'b0;
                        end  
                    end else begin 
                        in_rden <= 1'b0;
                    end 

                default: 
                    in_rden <= 1'b0;
            endcase // current_state_tx
        end 
    end 

    always_ff @(posedge clk) begin : in_dout_data_shift_proc
        case (current_state_tx)
            IDLE_ST: 
                if (~in_empty) begin 
                    in_dout_data_shift <= in_dout_data;
                end else begin 
                    in_dout_data_shift <= in_dout_data_shift;
                end 

            START_ST : 
                if (clock_event) begin 
                    in_dout_data_shift <= {1'b0, in_dout_data_shift[(DATA_WIDTH-1):1]};
                end else begin 
                    in_dout_data_shift <= in_dout_data_shift;
                end 

            DATA_ST : 
                if (clock_event) begin 
                    if (data_bit_counter == 7) begin 
                        in_dout_data_shift <= in_dout_data_shift;
                    end else begin 
                        in_dout_data_shift <= {1'b0, in_dout_data_shift[(DATA_WIDTH-1):1]};
                    end 
                end else begin 
                    in_dout_data_shift <= in_dout_data_shift;
                end 

            STOP_ST : 
                if (clock_event) begin 
                    if (byte_counter == N_BYTES) begin
                        if (~in_empty) begin 
                            in_dout_data_shift <= in_dout_data;
                        end else begin 
                            in_dout_data_shift <= in_dout_data_shift;
                        end 
                    end else begin 
                        in_dout_data_shift <= in_dout_data_shift;
                    end 
                end else begin 
                    in_dout_data_shift <= in_dout_data_shift;
                end 

            default:
                in_dout_data_shift <= in_dout_data_shift;

        endcase // current_state_tx
    end 

endmodule
