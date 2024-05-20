#include "util.h"

static volatile int input_data[8] = {0,1,2,3,4,5,6,7};
static volatile int flag = 0;
static volatile int acc_thread0 = 0;

char *s = "Success\n";
char *f = "Failure\n";
char *w = "Waiting\n";
char *t1 = "Thread1\n";
int program_thread0(){
    for (int i = 0; i < 4; i++) {
        acc_thread0 += input_data[i];
    }

    char *p;

    while (flag == 0){
        for (p = w; p < w + 8; p++) putchar(*p);
    }// Wait until thread1 produced the value
    if (flag + acc_thread0 == 28) {
        for (p = s; p < s + 8; p++) putchar(*p);
        return 0;
    } else {
        for (p = f; p < f + 8; p++) putchar(*p);
        return 1;
    }
}


int program_thread1(){
    int a = 0;
    char *p;
    for (p = t1; p < t1 + 8; p++) putchar(*p);
    for (int i = 0; i < 4; i++){
        a += input_data[4+i];
    }
    flag = a;
    return 0;
}

int main(int a){
    if (getCoreId() == 0) {
        program_thread0();
        t0_done = 1;
    } else
    {
        program_thread1();
        t1_done = 1;
    }
    while (!(t0_done && t1_done)){
    };
    return 0;
}
