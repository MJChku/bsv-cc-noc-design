//**************************************************************************
// Median filter bencmark
//--------------------------------------------------------------------------
//
// This benchmark performs a 1D three element median filter. The
// input data (and reference data) should be generated using the
// median_gendata.pl perl script and dumped to a file named
// dataset1.h You should not change anything except the
// HOST_DEBUG and PREALLOCATE macros for your timing run.

#include "util.h"
#include "median.h"

//--------------------------------------------------------------------------
// Input/Reference Data

#include "dataset1.h"

//--------------------------------------------------------------------------
// Shared output data

volatile int results_data[DATA_SIZE];
volatile int main1_done = 0;
volatile int main1_insts = 0;
volatile int main1_cycles = 0;

//--------------------------------------------------------------------------
// Main

void median_first_half( int n, int input[], volatile int results[] )
{
  int A, B, C, i;

  // Zero the begining
  results[0]   = 0;
  results[n-1] = 0;

  // Do the filter
  for ( i = 1; i < n/2; i++ ) {

    A = input[i-1];
    B = input[i];
    C = input[i+1];

    if ( A < B ) {
      if ( B < C )     
        results[i] = B;
      else if ( C < A )
        results[i] = A;
      else
        results[i] = C;
    }

    else {
      if ( A < C )     
        results[i] = A;
      else if ( C < B )
        results[i] = B;
      else             
        results[i] = C;
    }

  }

}

void median_second_half( int n, int input[], volatile int results[] )
{
  int A, B, C, i;

  // Do the filter
  for ( i = n/2; i < (n-1); i++ ) {

    A = input[i-1];
    B = input[i];
    C = input[i+1];

    if ( A < B ) {
      if ( B < C )     
        results[i] = B;
      else if ( C < A )
        results[i] = A;
      else
        results[i] = C;
    }

    else {
      if ( A < C )     
        results[i] = A;
      else if ( C < B )
        results[i] = B;
      else             
        results[i] = C;
    }

  }

  // Zero the end
  results[n-1] = 0;
}

int main0( )
{

  printStr("Benchmark mc_median\n");

  // start counting instructions and cycles
  int cycles, insts;
  cycles = getCycle();
  insts = getInsts();

  // do the median filter
  median_first_half( DATA_SIZE, input_data, results_data );

  // stop counting instructions and cycles
  cycles = getCycle() - cycles;
  insts = getInsts() - insts;

  // wait for main1 to finish
  while( main1_done == 0 );

  // print the cycles and inst count
  printStr("Cycles (core 0) = "); printInt(cycles); printChar('\n');
  printStr("Insts  (core 0) = "); printInt(insts); printChar('\n');
  printStr("Cycles (core 1) = "); printInt(main1_cycles); printChar('\n');
  printStr("Insts  (core 1) = "); printInt(main1_insts); printChar('\n');
  cycles = (cycles > main1_cycles) ? cycles : main1_cycles;
  insts = insts + main1_insts;
  printStr("Cycles  (total) = "); printInt(cycles); printChar('\n');
  printStr("Insts   (total) = "); printInt(insts); printChar('\n');

  // Check the results
  int ret = verify( DATA_SIZE, results_data, verify_data );
	printStr("Return "); printInt(ret); printChar('\n');
	return ret;
}

int main1( )
{
  // start counting instructions and cycles
  int cycles, insts;
  cycles = getCycle();
  insts = getInsts();

  // do the median filter
  median_second_half( DATA_SIZE, input_data, results_data );

  // stop counting instructions and cycles
  cycles = getCycle() - cycles;
  insts = getInsts() - insts;
  main1_cycles = cycles;
  main1_insts = insts;
  main1_done = 1;

  // Return success
  return 0;
}

int main(int argc, char *argv[]) {
	int core = getCoreId();
    if( core == 0 ) {
        main0();
        t0_done = 1;
    } else if(core == 1) {
        main1();
        t1_done = 1;
    }
    while( !(t0_done && t1_done)){};
	return 0;
}
