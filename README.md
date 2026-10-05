# Floating-Point-Unit-Design

A Verilog implementation of an IEEE 754 Single-Precision (32-bit) Floating Point Arithmetic Logic Unit (ALU).

## Features
- **Addition & Subtraction** (`FP_AddrSub.v`): Handles denormalized inputs, exponents alignment, signed operations, and post-normalization.
- **Multiplication** (`FP_Mul.v`): *In Progress*
- **Division** (`FP_Div.v`): *In Progress*
- **Formatting**: Separate unpacker (`FP_Unpacker.v`) and packer (`FP_Packer.v`) with Guard, Round, and Sticky bits for accurate rounding.