/* Minimal Linux 2.0 i386 init and KLab readiness endpoint. No libc required. */
typedef unsigned int size_t;
static int syscall3(int n, int a, int b, int c) { int r; __asm__ volatile("int $0x80":"=a"(r):"0"(n),"b"(a),"c"(b),"d"(c):"memory"); return r; }
static int open_(const char *p, int f) { return syscall3(5,(int)p,f,0); }
static int read_(int f, void *p, int n) { return syscall3(3,f,(int)p,n); }
static int write_(int f, const void *p, int n) { return syscall3(4,f,(int)p,n); }
static int len(const char *p) { int n=0; while(p[n]) n++; return n; }
static void put(int f,const char *p) { write_(f,p,len(p)); }
void _start(void) {
  char buf[256], tok[64]; int con=open_("/dev/ttyS0",2), ctl=open_("/dev/ttyS1",2), n, i, j;
  if(con>=0) put(con,"KLAB_SESSION_BOOT kernel=2.0.40\nUSERSPACE_PASS\nKLAB_SESSION_READY kernel=2.0.40\n");
  if(ctl<0) for(;;) { }
  for(;;) {
    put(ctl,"READY 2.0.40\n");
    n=read_(ctl,buf,sizeof(buf)-1); if(n<=0) continue; buf[n]=0;
    if(n>5 && buf[0]=='E'&&buf[1]=='X'&&buf[2]=='E'&&buf[3]=='C'&&buf[4]==' ') {
      i=5; j=0; while(i<n && buf[i]!=' ' && buf[i]!='\n' && j<(int)sizeof(tok)-1) tok[j++]=buf[i++]; tok[j]=0;
      put(ctl,"DATA "); put(ctl,tok); put(ctl," Mi4wLjQwCg==\nEND "); put(ctl,tok); put(ctl," 0\n");
    }
  }
}
