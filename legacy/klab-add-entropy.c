typedef unsigned long usize;
struct pool { int entropy_count, buf_size; unsigned int buf[16]; };
static long sc3(long n,long a,long b,long c){long r;__asm__ volatile("int $0x80":"=a"(r):"a"(n),"b"(a),"c"(b),"d"(c):"memory");return r;}
static void ex(int n){sc3(1,n,0,0);for(;;);}
void start_c(usize *sp){int ac=(int)*sp,fd,n;char **av=(char**)(sp+1);struct pool p;p.entropy_count=512;p.buf_size=64;if(ac!=2)ex(2);fd=(int)sc3(5,(long)av[1],0,0);if(fd<0)ex(3);n=(int)sc3(3,fd,(long)p.buf,64);sc3(6,fd,0,0);if(n!=64)ex(4);p.buf_size=n;p.entropy_count=n*8;fd=(int)sc3(5,(long)"/dev/random",2,0);if(fd<0)ex(5);n=(int)sc3(54,fd,0x40085203,(long)&p);sc3(6,fd,0,0);ex(n<0?6:0);}
__attribute__((naked)) void _start(void){__asm__ volatile("mov %esp,%eax; push %eax; call start_c");}
