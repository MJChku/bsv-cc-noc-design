// See LICENSE for license details.

#ifndef __UTIL_H
#define __UTIL_H

//--------------------------------------------------------------------------
// Macros

// Set HOST_DEBUG to 1 if you are going to compile this for a host
// machine (ie Athena/Linux) for debug purposes and set HOST_DEBUG
// to 0 if you are compiling with the smips-gcc toolchain.

#ifndef HOST_DEBUG
#define HOST_DEBUG 0
#endif

#include <stdint.h>

#if HOST_DEBUG

#include <stdio.h>
	static void printArray(const char name[], int n, const int arr[]) {
	  int i;
	  printf( " %10s :", name );
	  for ( i = 0; i < n; i++ )
		printf( " %3d ", arr[i] );
	  printf( "\n" );
	}
	static uint32_t getInsts() { return 0; }
	static uint32_t getCycle() { return 0; }
	static uint32_t getCoreId() { return 0; }

#else // HOST_DEBUG = 0

#endif // HOST_DEBUG

#define CACHE_LINE_SIZE 64
#define CACHE_ALIGN __attribute__((align(CACHE_LINE_SIZE)))

#ifdef TSO
#define FENCE() asm volatile ("fence\n" : : : "memory")
#else
#define FENCE()
#endif

// void printInt(int c);
// void printChar(char c);
// void printStr(const char *x);

static int verify(int n, const volatile int* test, const int* verify) {
  // correct: return 0
  // wrong: return wrong idx + 1
  int i;
  for (i = 0; i < n; i++)
  {
    int t = test[i];
    int v = verify[i];
    if (t != v) return i+1;
  }
  return 0;
}

static volatile int t0_done = 0;
static volatile int t1_done = 0;

static void printChar(char c) {
	putchar(c);
}

static void printStr(const char *str) {
	while (*str) {
		putchar(*str++);
	}
}


static void printInt(int num) {
	putchar('0'); putchar('x');
    if (num == 0) {
        putchar('0');
        return;
    }

    if (num < 0) {
        putchar('-');
        num = -num; // Convert to positive to handle the rest
    }

    // Determine the size of an integer in bits and prepare to extract hexadecimal digits
    int numBits = sizeof(num) * 8;
    int shiftAmount = numBits - 4; // Start with the most significant hex digit
    int started = 0; // This flag will be used to avoid printing leading zeros

    while (shiftAmount >= 0) {
        int digit = (num >> shiftAmount) & 0xF; // Extract the current hex digit
        if (digit != 0 || started) {
            if (digit < 10) {
                putchar('0' + digit);
            } else {
                putchar('A' + (digit - 10));
            }
            started = 1; // We have started printing digits
        }
        shiftAmount -= 4; // Move to the next digit
    }
}

static uint32_t getInsts() {
	uint32_t inst_num = 0;
	// asm volatile ("csrr %0, instret" : "=r"(inst_num) : );
	return inst_num;
}

static uint32_t getCycle() {
	uint32_t cyc_num = 0;
	asm volatile ("csrr %0, cycle" : "=r"(cyc_num) : );
	return cyc_num;
}

static uint32_t getCoreId() {
	uint32_t id = 0;
	asm volatile ("csrr %0, mhartid" : "=r"(id) : );
	return id;
}

#ifdef __riscv
#include "encoding.h"
#endif

#endif //__UTIL_H
