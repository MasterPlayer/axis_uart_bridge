`timescale 1ns / 1ps


module axis_uart_bridge #(
    parameter UART_SPEED           = 115200   ,
    parameter FREQ_HZ              = 100000000,
    parameter N_BYTES              = 32       ,
    parameter QUEUE_DEPTH          = 32       ,
    parameter QUEUE_MEMTYPE        = "auto"   , // "distributed", "auto"
    parameter UART_TX_REGISTER_LEN = 1        ,
    parameter UART_RX_REGISTER_LEN = 1
) (
    input                          aclk         ,
    input                          aresetn      ,
    input        [(N_BYTES*8)-1:0] S_AXIS_TDATA ,
    input                          S_AXIS_TVALID,
    output logic                   S_AXIS_TREADY,
    output logic [(N_BYTES*8)-1:0] M_AXIS_TDATA ,
    output logic                   M_AXIS_TVALID,
    input                          M_AXIS_TREADY,
    input                          UART_RX      ,
    output logic                   UART_TX
);

    localparam version = 16'h0100;

    initial begin : drc_check
        reg drc_error;
        drc_error = 0;

        if (FREQ_HZ < UART_SPEED*4) begin
            $error("[%s %0d-%0d] Clock frequency cannot been less than UART_SPEED*4 %m", "AXIS_UART_BRIDGE", 1, 1);
            drc_error = 1;
        end 

        if (FREQ_HZ == 0) begin
            $error("[%s %0d-%0d] CLK frequency cannot been equal 0 %m", "AXIS_UART_BRIDGE", 1, 2);
            drc_error = 1;
        end 

        if (UART_SPEED == 0) begin
            $error("[%s %0d-%0d] UART speed cannot been equal 0 %m", "AXIS_UART_BRIDGE", 1, 3);
            drc_error = 1;
        end 

        if (QUEUE_MEMTYPE != "block") begin 
            if (QUEUE_MEMTYPE != "distributed") begin 
                if (QUEUE_MEMTYPE != "auto") begin 
                    if (QUEUE_MEMTYPE != "ultra") begin 
                        $error("[%s %0d-%0d] Memory type <%s> is not supported %m", "AXIS_UART_BRIDGE", 1, 4, QUEUE_MEMTYPE);
                        drc_error = 1;
                    end 
                end 
            end
        end 

        if (UART_TX_REGISTER_LEN < 0) begin
            $error("[%s %0d-%0d] TX register length <%d> is not specified for this unit  %m", "AXIS_UART_BRIDGE", 1, 5);
            drc_error = 1;
        end 

        if (UART_RX_REGISTER_LEN < 0) begin
            $error("[%s %0d-%0d] RX register length %d is not specified for this unit  %m", "AXIS_UART_BRIDGE", 1, 6);
            drc_error = 1;
        end 

        if (N_BYTES == 0) begin
            $error("[%s %0d-%0d] Number %d of bytes in data bus cannot used  %m", "AXIS_UART_BRIDGE", 1, 7, N_BYTES);
            drc_error = 1;
        end 

        if (QUEUE_DEPTH < 0) begin
            $error("[%s %0d-%0d] Queue depth %d cannot used  %m", "AXIS_UART_BRIDGE", 1, 7, QUEUE_DEPTH);
            drc_error = 1;
        end 

        if (drc_error)
            #1 $finish;

    end 


    axis_uart_bridge_rx #(
        .UART_SPEED   (UART_SPEED          ),
        .FREQ_HZ      (FREQ_HZ             ),
        .N_BYTES      (N_BYTES             ),
        .QUEUE_DEPTH  (QUEUE_DEPTH         ),
        .QUEUE_MEMTYPE(QUEUE_MEMTYPE       ),
        .REGISTER_LEN (UART_RX_REGISTER_LEN)
    ) axis_uart_bridge_rx_inst (
        .clk          (aclk         ),
        .aresetn      (aresetn      ),
        .M_AXIS_TDATA (M_AXIS_TDATA ),
        .M_AXIS_TVALID(M_AXIS_TVALID),
        .M_AXIS_TREADY(M_AXIS_TREADY),
        .UART_RX      (UART_RX      )
    );

    axis_uart_bridge_tx #(
        .UART_SPEED   (UART_SPEED          ),
        .FREQ_HZ      (FREQ_HZ             ),
        .N_BYTES      (N_BYTES             ),
        .QUEUE_DEPTH  (QUEUE_DEPTH         ),
        .QUEUE_MEMTYPE(QUEUE_MEMTYPE       ),
        .REGISTER_LEN (UART_TX_REGISTER_LEN)
    ) axis_uart_bridge_tx_inst (
        .clk          (aclk         ),
        .reset        (~aresetn     ),
        .S_AXIS_TDATA (S_AXIS_TDATA ),
        .S_AXIS_TVALID(S_AXIS_TVALID),
        .S_AXIS_TREADY(S_AXIS_TREADY),
        .UART_TX      (UART_TX      )
    );


endmodule
