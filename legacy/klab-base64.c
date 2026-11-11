typedef unsigned long usize;
#if defined(__x86_64__)
static long sc3(long n,long a,long b,long c){long r;__asm__ volatile("syscall":"=a"(r):"a"(n),"D"(a),"S"(b),"d"(c):"rcx","r11","memory");return r;}
static long rd(int f,void*p,usize n){return sc3(0,f,(long)p,n);} static long wr(int f,const void*p,usize n){return sc3(1,f,(long)p,n);} static long op(const char*p){return sc3(2,(long)p,0,0);} static void ex(int n){sc3(60,n,0,0);for(;;);}
#elif defined(__i386__)
static long sc3(long n,long a,long b,long c){long r;__asm__ volatile("int $0x80":"=a"(r):"a"(n),"b"(a),"c"(b),"d"(c):"memory");return r;}
static long rd(int f,void*p,usize n){return sc3(3,f,(long)p,n);} static long wr(int f,const void*p,usize n){return sc3(4,f,(long)p,n);} static long op(const char*p){return sc3(5,(long)p,0,0);} static void ex(int n){sc3(1,n,0,0);for(;;);}
#else
#error unsupported architecture
#endif
static const char tab[]="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static int put(const char*p,usize n){while(n){long r=wr(1,p,n);if(r<=0)return 1;p+=r;n-=r;}return 0;}
static int enc(int fd){unsigned char in[3];usize have=0;long n;char out[4];while((n=rd(fd,in+have,3-have))>0){have+=(usize)n;if(have<3)continue;out[0]=tab[in[0]>>2];out[1]=tab[((in[0]&3)<<4)|(in[1]>>4)];out[2]=tab[((in[1]&15)<<2)|(in[2]>>6)];out[3]=tab[in[2]&63];if(put(out,4))return 1;have=0;}if(n<0)return 1;if(have){out[0]=tab[in[0]>>2];out[1]=tab[(in[0]&3)<<4|(have>1?in[1]>>4:0)];out[2]=have>1?tab[(in[1]&15)<<2]:'=';out[3]='=';if(put(out,4))return 1;}return put("\n",1);}
static int val(unsigned char c){if(c>='A'&&c<='Z')return c-'A';if(c>='a'&&c<='z')return c-'a'+26;if(c>='0'&&c<='9')return c-'0'+52;if(c=='+')return 62;if(c=='/')return 63;if(c=='=')return -2;return -1;}
static int dec(int fd){unsigned char buf[4096],o[3];int q[4],qn=0;long n;usize i;while((n=rd(fd,buf,sizeof buf))>0)for(i=0;i<(usize)n;i++){int x=val(buf[i]);if(x==-1)continue;q[qn++]=x;if(qn==4){if(q[0]<0||q[1]<0)return 1;o[0]=(q[0]<<2)|(q[1]>>4);if(put((char*)o,1))return 1;if(q[2]>=0){o[0]=(q[1]<<4)|(q[2]>>2);if(put((char*)o,1))return 1;if(q[3]>=0){o[0]=(q[2]<<6)|q[3];if(put((char*)o,1))return 1;}}qn=0;}}return n<0||qn!=0;}
void start_c(usize *sp){int argc=(int)*sp,decode=0,fd=0;char **argv=(char**)(sp+1);if(argc>1&&argv[1][0]=='-'&&argv[1][1]=='d'&&!argv[1][2]){decode=1;argv++;argc--;}if(argc>1){fd=(int)op(argv[1]);if(fd<0)ex(1);}ex(decode?dec(fd):enc(fd));}
__attribute__((naked)) void _start(void){
#if defined(__x86_64__)
__asm__ volatile("mov %rsp,%rdi; andq $-16,%rsp; call start_c");
#else
__asm__ volatile("mov %esp,%eax; push %eax; call start_c");
#endif
}
