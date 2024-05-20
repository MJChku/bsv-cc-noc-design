#include "util.h"
static volatile int input_data[8] = {0,1,2,3,4,5,6,7};
static volatile int buffer_data[8] = {0,0,0,0,0,0,0,0};
static volatile int flag = 0;
static volatile int t0_done = 0;
static volatile int t1_done = 0;

int getchar();
int putchar(int c);

char *s = "Success\n";
char *f = "Failure\n";

int program_thread0(){
  for(int i=0; i<8; i++){
    buffer_data[i] = input_data[i];
  }
  flag = 1;
  return 0;
}

int program_thread1(){
  while(flag==0){};
  int sum = 0;
  for(int i=0; i<8; i++){
    sum += buffer_data[i];
  }
  char *p;
  if(sum == 28){
    printStr(s);
  }else{
    printStr(f);
  }
  return 0;
}


int main(int a){
    if (getCoreId() == 0){
        program_thread0();
        t0_done = 1;
    } else
    {
      program_thread1();
      t1_done = 1;
    }
    // join operator
    while(!(t0_done && t1_done)){
    };
    return 0;
}
