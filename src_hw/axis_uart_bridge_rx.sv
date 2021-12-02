`timescale 1ns / 1ps

module axis_uart_bridge_rx #(
    parameter UART_SPEED    = 115200   ,
    parameter FREQ_HZ       = 100000000,
    parameter N_BYTES       = 32       ,
    parameter QUEUE_DEPTH   = 16       ,
    parameter QUEUE_MEMTYPE = "block"  ,
    parameter REGISTER_LEN  = 1  // "distributed", "auto"
) (
    input                          clk               ,
    input                          aresetn           ,
    output logic [(N_BYTES*8)-1:0] M_AXIS_TDATA      ,
    output logic                   M_AXIS_TVALID     ,
    input                          M_AXIS_TREADY     ,
    input                          UART_RX
);

    localparam CLOCK_DURATION      = (FREQ_HZ/UART_SPEED);
    localparam DATA_WIDTH          = (N_BYTES*8)         ;
    localparam HALF_CLOCK_DURATION = (CLOCK_DURATION/2)  ;

    logic [DATA_WIDTH-1:0] out_din_data = '{default:0};
    logic                  out_wren     = 1'b0        ;
    logic                  out_awfull                 ;

    logic [                       2:0] bit_index          = '{default:0};
    logic [    $clog2(DATA_WIDTH)-1:0] word_counter       = '{default:0};
    logic [$clog2(CLOCK_DURATION)-1:0] clock_counter      = '{default:0};
    logic                              clock_event        = 1'b0        ;
    logic                              d_internal_uart_rx               ;

    typedef enum {
        AWAIT_START_ST,
        RECEIVE_DATA_ST,
        AWAIT_STOP_ST
    } rx_fsm;

    rx_fsm current_state = AWAIT_START_ST;

    // logic [2:0] current_state_bit;

    // always_comb begin
    //     case (current_state)
    //         AWAIT_START_ST  : current_state_bit = 3'b001;
    //         RECEIVE_DATA_ST : current_state_bit = 3'b010;
    //         AWAIT_STOP_ST   : current_state_bit = 3'b100;
    //         default         : current_state_bit = 3'b111;
    //     endcase
    // end 

    // ila_dbg ila_dbg_inst (
    //     .clk    (clk               ), // input wire clk
    //     .probe0 (dbg_has_data_error), // input wire [0:0]  probe0
    //     .probe1 (out_din_data      ), // input wire [7:0]  probe1
    //     .probe2 (out_wren          ), // input wire [0:0]  probe2
    //     .probe3 (out_awfull        ), // input wire [0:0]  probe3
    //     .probe4 (bit_index         ), // input wire [2:0]  probe4
    //     .probe5 (word_counter      ), // input wire [7:0]  probe5
    //     .probe6 (clock_counter     ), // input wire [15:0]  probe6
    //     .probe7 (clock_event       ), // input wire [0:0]  probe7
    //     .probe8 (d_uart_rx         ), // input wire [0:0]  probe8
    //     .probe9 (current_state_bit ), // input wire [2:0]  probe9
    //     .probe10(UART_RX           )  // input wire [2:0]  probe9
    // );

    logic internal_uart_rx;

    generate 
        if (REGISTER_LEN > 1) begin : GEN_REGISTERED_INPUT 
            logic [REGISTER_LEN-1:0] registered_uart_rx;

            always_ff @(posedge clk) begin
                registered_uart_rx <= {registered_uart_rx[REGISTER_LEN-2:0], UART_RX};
            end 

            always_comb begin 
                internal_uart_rx = registered_uart_rx[REGISTER_LEN-1];
            end 

        end 
    endgenerate 



    generate 
        if (REGISTER_LEN == 1) begin : GEN_REGISTERED_SINGLE_INPUT 
            logic [REGISTER_LEN-1:0] registered_uart_rx;

            always_ff @(posedge clk) begin
                registered_uart_rx <= UART_RX;
            end 

            always_comb begin 
                internal_uart_rx = registered_uart_rx[REGISTER_LEN-1];
            end 
            
        end 
    endgenerate 



    generate 
        if (REGISTER_LEN == 0) begin : GEN_NO_REGISTERED_INPUT 
            
            always_comb begin 
                internal_uart_rx = UART_RX;
            end 

        end 
    endgenerate
        


    always_ff @(posedge clk) begin : d_uart_rx_proc
        d_internal_uart_rx <= internal_uart_rx;
    end 



    always_ff @(posedge clk) begin : half_clock_counter_proc
        if (!aresetn) begin 
            clock_counter <= HALF_CLOCK_DURATION;
        end else begin 
            case (current_state)
                AWAIT_START_ST : 
                    if (clock_counter == HALF_CLOCK_DURATION) begin 
                        if (!internal_uart_rx & d_internal_uart_rx) begin 
                            clock_counter <= clock_counter + 1;
                        end 
                    end else begin 
                        clock_counter <= clock_counter + 1;
                    end 

                RECEIVE_DATA_ST: 
                    if (clock_counter < (CLOCK_DURATION-1)) begin 
                        clock_counter <= clock_counter + 1;
                    end else begin 
                        clock_counter <= '{default:0};
                    end 

                AWAIT_STOP_ST:
                    if (clock_counter < (CLOCK_DURATION-1)) begin 
                        clock_counter <= clock_counter + 1;
                    end else begin 
                        clock_counter <= HALF_CLOCK_DURATION-1;
                    end 

                default: 
                    clock_counter <= '{default:0};

            endcase // current_state
        end 
    end 



    always_ff @(posedge clk) begin : clock_event_proc
        if (clock_counter == CLOCK_DURATION-1)   
            clock_event <= 1'b1;
         else  
            clock_event <= 1'b0;
    end



    always_ff @(posedge clk) begin : current_state_proc
        if (!aresetn)  
            current_state <= AWAIT_START_ST;
        else  
            case (current_state) 
                AWAIT_START_ST : 
                    if (clock_event)  
                        if (!internal_uart_rx)  // is this start?
                            current_state <= RECEIVE_DATA_ST;

                RECEIVE_DATA_ST : 
                    if (clock_event)
                        if (bit_index == 'h7)
                            current_state <= AWAIT_STOP_ST;

                AWAIT_STOP_ST : 
                    if (clock_event)
                        if (internal_uart_rx)
                            current_state <= AWAIT_START_ST;

                default        : 
                    current_state <= current_state;
            endcase
    end



    always_ff @(posedge clk) begin 
        case (current_state) 
            RECEIVE_DATA_ST : 
                if (clock_event)
                    bit_index <= bit_index + 1;

            AWAIT_STOP_ST : 
                if (clock_event)
                    bit_index <= '{default:0};

            default: 
                bit_index <= '{default:0};

        endcase
    end 



    always_ff @(posedge clk) begin : out_din_data_proc
        case (current_state) 
            RECEIVE_DATA_ST : 
                if (clock_event)
                    out_din_data <= {internal_uart_rx, out_din_data[(DATA_WIDTH-1):1]};

            default : 
                out_din_data <= out_din_data;
        endcase // current_state
    end 



    // for calculation when out_wren generate
    always_ff @(posedge clk) begin : word_counter_proc
        case (current_state)
            RECEIVE_DATA_ST: 
                if (clock_event) 
                    if (word_counter < (DATA_WIDTH-1)) begin 
                        word_counter <= word_counter + 1;
                    end else begin 
                        word_counter <= '{default:0};
                    end 

            default : 
                word_counter <= word_counter;

        endcase // current_state
    end 


    generate
        if (QUEUE_DEPTH == 0) begin : GEN_NO_DEPTH 

            always_comb begin : m_axis_tdata_processing
                M_AXIS_TDATA  = out_din_data;
            end 

            always_comb begin : m_axis_tvalid_processing 
                M_AXIS_TVALID = out_wren;
            end 

        end 
    endgenerate


    generate 
        if (QUEUE_DEPTH > 0 & QUEUE_DEPTH < 16) begin : GEN_QUEUE_ACTIVE_MIN_DEPTH
        
            fifo_out_sync_xpm #(
                .DATA_WIDTH(DATA_WIDTH   ),
                .MEMTYPE   (QUEUE_MEMTYPE),
                .DEPTH     (16  )
            ) fifo_out_sync_xpm_inst (
                .CLK          (clk          ),
                .RESET        (!aresetn     ),
                
                .OUT_DIN_DATA (out_din_data ),
                .OUT_DIN_KEEP ('b0          ),
                .OUT_DIN_LAST ('b0          ),
                .OUT_WREN     (out_wren     ),
                .OUT_FULL     (             ),
                .OUT_AWFULL   (out_awfull   ),
                
                .M_AXIS_TDATA (M_AXIS_TDATA ),
                .M_AXIS_TKEEP (             ),
                .M_AXIS_TVALID(M_AXIS_TVALID),
                .M_AXIS_TLAST (             ),
                .M_AXIS_TREADY(M_AXIS_TREADY)
            );

            always_ff @ (posedge clk) begin : out_wren_proc 
                if (clock_event) begin 
                    if (word_counter == (DATA_WIDTH-1)) begin 
                        out_wren <= 1'b1;
                    end else begin 
                        out_wren <= 1'b0;
                    end 
                end else begin 
                    out_wren <= 1'b0;
                end 
            end 

        end 
    endgenerate

    generate
        if (QUEUE_DEPTH >= 16) begin : GEN_QUEUE_ACTIVE_USER_DEPTH

            fifo_out_sync_xpm #(
                .DATA_WIDTH(DATA_WIDTH   ),
                .MEMTYPE   (QUEUE_MEMTYPE),
                .DEPTH     (QUEUE_DEPTH  )
            ) fifo_out_sync_xpm_inst (
                .CLK          (clk          ),
                .RESET        (!aresetn     ),
                
                .OUT_DIN_DATA (out_din_data ),
                .OUT_DIN_KEEP ('b0          ),
                .OUT_DIN_LAST ('b0          ),
                .OUT_WREN     (out_wren     ),
                .OUT_FULL     (             ),
                .OUT_AWFULL   (out_awfull   ),
                
                .M_AXIS_TDATA (M_AXIS_TDATA ),
                .M_AXIS_TKEEP (             ),
                .M_AXIS_TVALID(M_AXIS_TVALID),
                .M_AXIS_TLAST (             ),
                .M_AXIS_TREADY(M_AXIS_TREADY)
            );

            always_ff @ (posedge clk) begin : out_wren_proc 
                if (clock_event) begin 
                    if (word_counter == (DATA_WIDTH-1)) begin 
                        out_wren <= 1'b1;
                    end else begin 
                        out_wren <= 1'b0;
                    end 
                end else begin 
                    out_wren <= 1'b0;
                end 
            end 
        
        end 
    endgenerate





endmodule
