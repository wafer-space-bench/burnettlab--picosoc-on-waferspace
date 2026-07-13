// SPDX-FileCopyrightText: © 2025 XXX Authors
// SPDX-License-Identifier: Apache-2.0

`default_nettype none

module chip_core #(
    parameter NUM_INPUT_PADS,
    parameter NUM_BIDIR_PADS,
    parameter NUM_ANALOG_PADS
    )(
    `ifdef USE_POWER_PINS
    inout  wire VDD,
    inout  wire VSS,
    `endif
    
    input  wire clk,       // clock
    input  wire rst_n,     // reset (active low)
    
    input  wire [NUM_INPUT_PADS-1:0] input_in,   // Input value
    output wire [NUM_INPUT_PADS-1:0] input_pu,   // Pull-up
    output wire [NUM_INPUT_PADS-1:0] input_pd,   // Pull-down

    input  wire [NUM_BIDIR_PADS-1:0] bidir_in,   // Input value
    output wire [NUM_BIDIR_PADS-1:0] bidir_out,  // Output value
    output wire [NUM_BIDIR_PADS-1:0] bidir_oe,   // Output enable
    output wire [NUM_BIDIR_PADS-1:0] bidir_cs,   // Input type (0=CMOS Buffer, 1=Schmitt Trigger)
    output wire [NUM_BIDIR_PADS-1:0] bidir_sl,   // Slew rate (0=fast, 1=slow)
    output wire [NUM_BIDIR_PADS-1:0] bidir_ie,   // Input enable
    output wire [NUM_BIDIR_PADS-1:0] bidir_pu,   // Pull-up
    output wire [NUM_BIDIR_PADS-1:0] bidir_pd,   // Pull-down

    inout  wire [NUM_ANALOG_PADS-1:0] analog  // Analog
);

    // How many 32-bit words worth of memory do we have? We have instantiated eight 512-byte SRAMs at time of writing, each of which could store 128 32-bit words (but we need to instantiate them in groups of 4 so they can collectively form a 32-bit word in parallel). Total number of 32-bit words right now is 128 * 8 = 1024.
    parameter integer MEM_WORDS = 1024;

    // See here for usage: https://gf180mcu-pdk.readthedocs.io/en/latest/IPs/IO/gf180mcu_fd_io/digital.html
    
    // Disable pull-up and pull-down for input
    assign input_pu = '0;
    assign input_pd = '0;

    // Set the bidir as output
    assign bidir_oe = {flash_io0_oe, flash_io1_oe, flash_io2_oe, flash_io3_oe, 1'b0, '1}; // 5th 0 is to enable ser_rx input
    assign bidir_cs = '0; // all CMOS buffer type
    assign bidir_sl = '0; // all fast slew date
    assign bidir_ie = ~bidir_oe;
    assign bidir_pu = '0;
    assign bidir_pd = '0;
    
    logic _unused;
    assign _unused = &bidir_in;


//    assign bidir_out[31:8] = count[23:0] ^ {mem_rdata};
//    assign bidir_out[7:0] = count[31:24];
//	assign bidir_out = count ^ {8'b0, mem_rdata};
	assign bidir_out = {flash_io0_do, flash_io1_do, flash_io2_do, flash_io3_do, 1'b0, ser_tx, flash_csb, flash_clk, count ^ mem_rdata};

	// SRAM inputs
	wire sram_sel;
	assign sram_sel = 1'b1;


    logic [NUM_BIDIR_PADS-1:0] count;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            count <= '0;
        end else begin
            if (&input_in) begin
                count <= count + 1;
            end
        end
    end

	// inputs for picorv
	wire mem_ready;
	wire [31:0] mem_rdata;

	// outputs for picorv
	wire mem_valid;
	wire mem_instr;
	wire [31:0] mem_addr;
	wire [31:0] mem_wdata;
	wire [ 3:0] mem_wstrb;
	wire pico_trace_valid_w;
	wire [35:0] pico_trace_data_w;
	wire [31:0] irq_eoi_o_wide;


	// outputs for spimemio
	wire spimem_ready;
	wire [31:0] spimem_rdata;
	wire flash_csb;
	wire flash_clk;
	wire flash_io0_oe;
	wire flash_io1_oe;
	wire flash_io2_oe;
	wire flash_io3_oe;
	wire flash_io0_do;
	wire flash_io1_do;
	wire flash_io2_do;
	wire flash_io3_do;

	// inputs for spimemo
	wire flash_io0_di = 0;
	wire flash_io1_di = 0;
	wire flash_io2_di = 0;
	wire flash_io3_di = 0;

	wire spimemio_cfgreg_sel = mem_valid && (mem_addr == 32'h 0200_0000);
	wire [31:0] spimemio_cfgreg_do;

	reg [31:0] irq;
	wire irq_stall = 0;
	wire irq_uart = 0;

	always @* begin
		irq = 0;
		irq[3] = irq_stall;
		irq[4] = irq_uart;
		irq[5] = 0;
		irq[6] = 0;
		irq[7] = 0;
	end

	picorv32 #(
		.STACKADDR(4*MEM_WORDS),
		.PROGADDR_RESET(32'h 0010_0000),
		.PROGADDR_IRQ(32'h 0000_0000),
		.BARREL_SHIFTER(1),
		.COMPRESSED_ISA(1),
		.ENABLE_COUNTERS(1),
		.ENABLE_MUL(0),
		.ENABLE_DIV(0),
		.ENABLE_FAST_MUL(0),
		.ENABLE_IRQ(1),
		.ENABLE_IRQ_QREGS(0)
	) cpu (
		.clk         (clk        ),
		.resetn      (rst_n     ),
		.mem_valid   (mem_valid  ),
		.mem_instr   (mem_instr  ),
		.mem_ready   (mem_ready  ),
		.mem_addr    (mem_addr   ),
		.mem_wdata   (mem_wdata  ),
		.mem_wstrb   (mem_wstrb  ),
		.mem_rdata   (mem_rdata  ),
		.irq         (irq        )
	);


	spimemio spimemio (
		.clk    (clk),
		.resetn (rst_n),
		.valid  (mem_valid && mem_addr >= 4*MEM_WORDS && mem_addr < 32'h 0200_0000),
		.ready  (spimem_ready),
		.addr   (mem_addr[23:0]),
		.rdata  (spimem_rdata),

		.flash_csb    (flash_csb   ),
		.flash_clk    (flash_clk   ),

		.flash_io0_oe (flash_io0_oe),
		.flash_io1_oe (flash_io1_oe),
		.flash_io2_oe (flash_io2_oe),
		.flash_io3_oe (flash_io3_oe),

		.flash_io0_do (flash_io0_do),
		.flash_io1_do (flash_io1_do),
		.flash_io2_do (flash_io2_do),
		.flash_io3_do (flash_io3_do),

		.flash_io0_di (bidir_in[0]),
		.flash_io1_di (bidir_in[1]),
		.flash_io2_di (bidir_in[2]),
		.flash_io3_di (bidir_in[3]),

		.cfgreg_we(spimemio_cfgreg_sel ? mem_wstrb : 4'b 0000),
		.cfgreg_di(mem_wdata),
		.cfgreg_do(spimemio_cfgreg_do)
	);

	wire ser_tx;
	wire ser_rx = 0;

	wire        simpleuart_reg_div_sel = mem_valid && (mem_addr == 32'h 0200_0004);
	wire [31:0] simpleuart_reg_div_do;
	
	wire        simpleuart_reg_dat_sel = mem_valid && (mem_addr == 32'h 0200_0008);
	wire        simpleuart_reg_dat_wait;
	wire [31:0] simpleuart_reg_dat_do;

	simpleuart simpleuart (
		.clk         (clk         ),
		.resetn      (rst_n      ),

		.ser_tx      (ser_tx      ),
		.ser_rx      (bidir_in[4]      ),

		.reg_div_we  (simpleuart_reg_div_sel ? mem_wstrb : 4'b 0000),
		.reg_div_di  (mem_wdata),
		.reg_div_do  (simpleuart_reg_div_do),

		.reg_dat_we  (simpleuart_reg_dat_sel ? mem_wstrb[0] : 1'b 0),
		.reg_dat_re  (simpleuart_reg_dat_sel && !mem_wstrb),
		.reg_dat_di  (mem_wdata),
		.reg_dat_do  (simpleuart_reg_dat_do),
		.reg_dat_wait(simpleuart_reg_dat_wait)
	);


    simple_sram #(
    ) sram (
        `ifdef USE_POWER_PINS
        .VDD                   (VDD),
        .VSS                   (VSS),
        `endif
        .clk   (clk),
        .resetn(rst_n),
        .valid (sram_sel),	// input
        .ready (mem_ready),	// output
        .wstrb (mem_wstrb),
        .addr  (mem_addr),
        .wdata (mem_wdata),
        .rdata (mem_rdata)
    );


endmodule

`default_nettype wire

