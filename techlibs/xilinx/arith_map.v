/*
 *  yosys -- Yosys Open SYnthesis Suite
 *
 *  Copyright (C) 2012  Clifford Wolf <clifford@clifford.at>
 *
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

(* techmap_celltype = "$lcu" *)
module _80_xilinx_lcu (P, G, CI, CO);
	parameter WIDTH = 2;

	input [WIDTH-1:0] P, G;
	input CI;

	output [WIDTH-1:0] CO;

	wire _TECHMAP_FAIL_ = WIDTH <= 2;

	wire [WIDTH-1:0] C = {CO, CI};
	wire [WIDTH-1:0] S = P & ~G;

`ifndef _EXPLICIT_CARRY
	genvar i;
	generate for (i = 0; i < WIDTH; i = i + 1) begin:slice
		MUXCY muxcy (
			.CI(C[i]),
			.DI(G[i]),
			.S(S[i]),
			.O(CO[i])
		);
	end endgenerate
`else
	// Carry outputs for fabric.
	wire [WIDTH-1:0] LO;
	genvar i;
	generate for (i = 0; i < WIDTH; i = i + 1) begin:slice
		MUXCY muxcy (
			.CI(C[i]),
			.DI(G[i]),
			.S(S[i]),
			.CO(CO[i]),
			.CO2(LO[i])
		);
	end endgenerate
`endif
endmodule

(* techmap_celltype = "$alu" *)
module _80_xilinx_alu (A, B, CI, BI, X, Y, CO);
	parameter A_SIGNED = 0;
	parameter B_SIGNED = 0;
	parameter A_WIDTH = 1;
	parameter B_WIDTH = 1;
	parameter Y_WIDTH = 1;
	parameter _TECHMAP_CONSTVAL_CI_ = 0;
	parameter _TECHMAP_CONSTMSK_CI_ = 0;

	input [A_WIDTH-1:0] A;
	input [B_WIDTH-1:0] B;
	output [Y_WIDTH-1:0] X, Y;

	input CI, BI;
	output [Y_WIDTH-1:0] CO;

	wire _TECHMAP_FAIL_ = Y_WIDTH <= 2;

	wire [Y_WIDTH-1:0] A_buf, B_buf;
	\$pos #(.A_SIGNED(A_SIGNED), .A_WIDTH(A_WIDTH), .Y_WIDTH(Y_WIDTH)) A_conv (.A(A), .Y(A_buf));
	\$pos #(.A_SIGNED(B_SIGNED), .A_WIDTH(B_WIDTH), .Y_WIDTH(Y_WIDTH)) B_conv (.A(B), .Y(B_buf));

	wire [Y_WIDTH-1:0] AA = A_buf;
	wire [Y_WIDTH-1:0] BB = BI ? ~B_buf : B_buf;

	wire [Y_WIDTH-1:0] S = AA ^ BB;
	wire [Y_WIDTH-1:0] DI = AA & BB;

`ifndef _EXPLICIT_CARRY
	wire [Y_WIDTH-1:0] C = {CO, CI};

	genvar i;
	generate for (i = 0; i < Y_WIDTH; i = i + 1) begin:slice
		MUXCY muxcy (
			.CI(C[i]),
			.DI(DI[i]),
			.S(S[i]),
			.O(CO[i])
		);
		XORCY xorcy (
			.CI(C[i]),
			.LI(S[i]),
			.O(Y[i])
		);
	end endgenerate
`else
	wire CINIT;
	// Carry chain.
	//
	// VPR requires that the carry chain never hit the fabric.  The CO input
	// to this techmap is the carry outputs for synthesis, e.g. might hit the
	// fabric.
	//
	// So we maintain two wire sets, CO_CHAIN is the carry that is for VPR,
	// e.g. off fabric dedicated chain.  CO is the carry outputs that are
	// available to the fabric.
	wire [Y_WIDTH-1:0] CO_CHAIN;
	wire [Y_WIDTH-1:0] C = {CO_CHAIN, CINIT};

	// If carry chain is being initialized to a constant, techmap the constant
	// source.  Otherwise techmap the fabric source.
	generate for (i = 0; i < 1; i = i + 1) begin:slice
		CARRY0 #(.CYINIT_FABRIC(1)) carry(
			.CI_INIT(CI),
			.DI(DI[0]),
			.S(S[0]),
			.CO_CHAIN(CO_CHAIN[0]),
			.CO_FABRIC(CO[0]),
			.O(Y[0])
		);
	end endgenerate

	genvar i;
	generate for (i = 1; i < Y_WIDTH-1; i = i + 1) begin:slice
        if(i % 4 == 0) begin
			CARRY0 carry (
				.CI(C[i]),
				.DI(DI[i]),
				.S(S[i]),
				.CO_CHAIN(CO_CHAIN[i]),
				.CO_FABRIC(CO[i]),
				.O(Y[i])
			);
		end
		else
		begin
			CARRY carry (
				.CI(C[i]),
				.DI(DI[i]),
				.S(S[i]),
				.CO_CHAIN(CO_CHAIN[i]),
				.CO_FABRIC(CO[i]),
				.O(Y[i])
			);
		end
	end endgenerate
	generate for (i = Y_WIDTH-1; i < Y_WIDTH; i = i + 1) begin:slice
        if(i % 4 == 0) begin
			CARRY0 top_of_carry (
				.CI(C[i]),
				.DI(DI[i]),
				.S(S[i]),
				.CO_CHAIN(CO_CHAIN[i]),
				.O(Y[i])
			);
		end
		else
		begin
			CARRY top_of_carry (
				.CI(C[i]),
				.DI(DI[i]),
				.S(S[i]),
				.CO_CHAIN(CO_CHAIN[i]),
				.O(Y[i])
			);
		end
        // Turns out CO_FABRIC and O both use [ABCD]MUX, so provide
        // a non-congested path to output the top of the carry chain.
        // Registering the output of the CARRY block would solve this, but not
        // all designs do that.
        if((i+1) % 4 == 0) begin
			CARRY0 carry_output (
				.CI(CO_CHAIN[i]),
				.DI(0),
				.S(0),
				.O(CO[i])
			);
		end
		else
		begin
			CARRY carry_output (
				.CI(CO_CHAIN[i]),
				.DI(0),
				.S(0),
				.O(CO[i])
			);
		end
	end endgenerate
`endif


	assign X = S;
endmodule

