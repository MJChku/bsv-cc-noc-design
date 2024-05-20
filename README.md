# Bluespec RISC-V Multi-Core Processor

## Overview
This project is a multi-core RISC-V processor designed in Bluespec. It supports the RISC-V 32I Instruction Set Architecture (ISA) and includes L1-instruction cache and L1-data cache, a multi-core setup with MSI cache coherence, and a distributed shared L2 cache architecture. The nodes in the system are interconnected through a Network-on-Chip (NoC), each node contains a pipelined core, L1 cache, a slice of L2 cache and a coherence protocol processor.

### Key Features
- **RISC-V 32I ISA Support**
- **Cache Hierarchy**:
  - **L1 Cache**: Separate instruction and data caches for each core. Instruction caches are not kept coherent. 
  - **L2 Cache**: A distributed shared cache where each node contains a slice of L2 cache along with a directory and a coherence protocol processor for maintaining cache coherence.
- **Multi-Core with MSI Coherence Protocol**: Supports multiple cores using the MSI (Modified, Shared, Invalid) protocol to ensure cache coherence.
- **Distributed System Architecture**: Each node consists of a core, associated L1 cache, a slice of L2 cache, and a directory. 
- **Network-on-Chip (NoC)**: Interconnects nodes, enabling cross communication within the processor.

## Getting Started

### Prerequisites
- **Bluespec Compiler**: Ensure you have the Bluespec compiler installed on your system.

# Build the project and test
`make`

`make -C testMultiCore`

`./mc_pipelined.sh <benchmark_name>32` ( try find benchmark name in `testMultiCore/src` ) 
