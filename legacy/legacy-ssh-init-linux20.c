/* Linux 2.0 i386 PID 1 for the sealed historical SSH root. No libc required. */
static int sc0(int n){int r;__asm__ volatile("int $0x80":"=a"(r):"0"(n):"memory");return r;}
static int sc1(int n,int a){int r;__asm__ volatile("int $0x80":"=a"(r):"0"(n),"b"(a):"memory");return r;}
static int sc3(int n,int a,int b,int c){int r;__asm__ volatile("int $0x80":"=a"(r):"0"(n),"b"(a),"c"(b),"d"(c):"memory");return r;}
static int sc5(int n,int a,int b,int c,int d,int e){int r;__asm__ volatile("int $0x80":"=a"(r):"0"(n),"b"(a),"c"(b),"d"(c),"S"(d),"D"(e):"memory");return r;}
struct sockaddr_ { unsigned short family; unsigned char data[14]; };
struct ifreq_ { char name[16]; union { struct sockaddr_ addr; short flags; } u; };
static void zero(void *p,int n){unsigned char *q=p;while(n--) *q++=0;}
static void name(struct ifreq_ *r){zero(r,sizeof(*r));r->name[0]='e';r->name[1]='t';r->name[2]='h';r->name[3]='0';}
static void addr(struct ifreq_ *r,unsigned int ip){name(r);r->u.addr.family=2;r->u.addr.data[2]=ip&255;r->u.addr.data[3]=(ip>>8)&255;r->u.addr.data[4]=(ip>>16)&255;r->u.addr.data[5]=(ip>>24)&255;}
static int con=-1;
static void out(const char *p){int n=0;while(p[n])n++;if(con>=0)sc3(4,con,(int)p,n);}
static void num(int v){char b[16];int n=0,i;if(v<0){out("-");v=-v;}do{b[n++]='0'+v%10;v/=10;}while(v);for(i=n-1;i>=0;i--)sc3(4,con,(int)&b[i],1);out(" ");}
static void network(void){int a[3]={2,2,0},fd=sc3(102,1,(int)a,0),r1,r2,r3,r4;struct ifreq_ r;if(fd<0){num(fd);return;}addr(&r,0x0f02000a);r1=sc3(54,fd,0x8916,(int)&r);addr(&r,0x00ffffff);r2=sc3(54,fd,0x891c,(int)&r);name(&r);r3=sc3(54,fd,0x8913,(int)&r);r.u.flags|=1;r4=sc3(54,fd,0x8914,(int)&r);out("KLAB_NET_IOCTL ");num(fd);num(r1);num(r2);num(r3);num(r4);out("\n");sc1(6,fd);}
static char *envp[]={"PATH=/bin:/sbin:/usr/bin:/usr/sbin",0};
static int run(char *path,char **argv){int pid=sc0(2),st=0;if(pid==0){sc3(11,(int)path,(int)argv,(int)envp);sc1(1,127);}if(pid<0)return pid;sc3(7,pid,(int)&st,0);return st;}
void _start(void){
 con=sc3(5,(int)"/dev/tty1",2,0);
char *showargv[]={"ld-linux.so.2","--library-path","/lib20","/sbin/ifconfig","eth0",0};
 char *netrouteargv[]={"ld-linux.so.2","--library-path","/lib20","/sbin/route","add","-net","10.0.2.0","netmask","255.255.255.0","dev","eth0",0};
 char *routeargv[]={"ld-linux.so.2","--library-path","/lib20","/sbin/route","add","default","gw","10.0.2.2",0};
 char *dbargv[]={"dropbear","-F","-E","-s","-r","/etc/dropbear/dropbear_rsa_host_key","-p","22",0};
 { int mr=sc5(21,(int)"proc",(int)"/proc",(int)"proc",0xC0ED0000,0); out("KLAB_PROC_MOUNT "); num(mr); out("\n"); }
 network(); run("/lib20/ld-linux.so.2",netrouteargv); run("/lib20/ld-linux.so.2",routeargv); run("/lib20/ld-linux.so.2",showargv);
 sc3(11,(int)"/usr/sbin/dropbear",(int)dbargv,(int)envp);
 for(;;) sc0(29);
}
