typedef unsigned int u32; typedef unsigned short u16; typedef unsigned long usize;
struct sockaddr_in { u16 family, port; u32 addr; unsigned char zero[8]; };
struct timespec { long sec, nsec; };
enum { SYS_exit=1, SYS_read=3, SYS_write=4, SYS_close=6, SYS_nanosleep=162, SYS_socketcall=102 };
enum { SC_socket=1, SC_bind=2, SC_connect=3, SC_listen=4, SC_accept=5, SC_setsockopt=14 };
static long sc3(long n,long a,long b,long c){long r;__asm__ volatile("int $0x80":"=a"(r):"a"(n),"b"(a),"c"(b),"d"(c):"memory");return r;}
static long call(long n,long*a){return sc3(SYS_socketcall,n,(long)a,0);} static void ex(int n){sc3(SYS_exit,n,0,0);for(;;);}
static int wr(int f,const void*p,usize n){const char*s=p;while(n){long r=sc3(SYS_write,f,(long)s,n);if(r<=0)return 1;s+=r;n-=r;}return 0;}
static int rd(int f,void*p,usize n){return (int)sc3(SYS_read,f,(long)p,n);} static int closefd(int f){return (int)sc3(SYS_close,f,0,0);}
static usize len(const char*s){usize n=0;while(s[n])n++;return n;} static int eq(const char*a,const char*b){while(*a&&*a==*b){a++;b++;}return *a==*b;}
static int num(const char*s){int n=0;while(*s>='0'&&*s<='9')n=n*10+*s++-'0';return n;} static u16 sw16(u16 x){return (u16)((x<<8)|(x>>8));}
static u32 ip4(const char*s){u32 v=0;int part=0,n=0;for(;;s++){if(*s>='0'&&*s<='9'){part=part*10+*s-'0';if(part>255)return 0;}else if(*s=='.'||!*s){v|=(u32)part<<(n*8);part=0;if(++n==4)return *s?0:v;}else return 0;}}
static void out(const char*s){wr(1,s,len(s));} static void sleep50(void){struct timespec t={0,50000000};sc3(SYS_nanosleep,(long)&t,0,0);}
static int sock(void){long a[3]={2,1,0};return (int)call(SC_socket,a);} static int server(int port){int s=sock(),c,n;long a[5];struct sockaddr_in sa={2,sw16((u16)port),0,{0}};char b[256];if(s<0)return 2;a[0]=s;a[1]=(long)&sa;a[2]=16;if(call(SC_bind,a)<0)return 3;a[0]=s;a[1]=1;if(call(SC_listen,a)<0)return 4;out("SERVER_READY\n");a[0]=s;a[1]=0;a[2]=0;c=(int)call(SC_accept,a);if(c<0)return 5;n=rd(c,b,255);if(n<=0)return 6;b[n]=0;out("SERVER_RX ");out(b);out("\n");wr(c,"ACK:",4);wr(c,b,n);closefd(c);closefd(s);out("SERVER_DONE\n");return 0;}
static int client(const char*ip,int port,const char*msg){int s=-1,n,i;long a[3];struct sockaddr_in sa={2,sw16((u16)port),ip4(ip),{0}};char b[320];for(i=0;i<200;i++){s=sock();if(s<0)return 2;a[0]=s;a[1]=(long)&sa;a[2]=16;if(call(SC_connect,a)==0)break;closefd(s);s=-1;sleep50();}if(s<0)return 3;if(wr(s,msg,len(msg)))return 4;n=0;for(;;){int r=rd(s,b+n,319-n);if(r<0){closefd(s);return 5;}if(r==0||n+r>=319){n+=r;break;}n+=r;}closefd(s);if(n<=0)return 5;b[n]=0;out("CLIENT_RX ");out(b);out("\n");return 0;}
void start_c(usize*sp){int ac=(int)*sp;char**av=(char**)(sp+1);if(ac==4&&eq(av[1],"server"))ex(server(num(av[2])));if(ac==5&&eq(av[1],"client"))ex(client(av[2],num(av[3]),av[4]));out("usage\n");ex(2);} __attribute__((naked)) void _start(void){__asm__ volatile("mov %esp,%eax; push %eax; call start_c");}
