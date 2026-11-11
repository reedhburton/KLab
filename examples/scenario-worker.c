#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
    const char *name = argc > 1 ? argv[1] : "worker";
    printf("worker=%s pid=%ld pointer_bits=%zu\n", name, (long)getpid(), sizeof(void*) * 8U);
    fflush(stdout);
    return 0;
}
