#define _POSIX_C_SOURCE 200809L
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
static void msleep(long ms){ struct timespec t={ms/1000,(ms%1000)*1000000L}; nanosleep(&t,NULL); }
static int server(int port,int count){
 int s=socket(AF_INET,SOCK_STREAM,0), one=1; if(s<0)return 2; setsockopt(s,SOL_SOCKET,SO_REUSEADDR,&one,sizeof(one));
 struct sockaddr_in a={0}; a.sin_family=AF_INET; a.sin_addr.s_addr=htonl(INADDR_ANY); a.sin_port=htons((unsigned short)port);
 if(bind(s,(struct sockaddr*)&a,sizeof(a))<0||listen(s,8)<0){perror("server");return 3;} printf("SERVER_READY port=%d count=%d\n",port,count); fflush(stdout);
 for(int i=0;i<count;i++){ int c=accept(s,NULL,NULL); if(c<0){perror("accept");return 4;} char b[256]={0}; ssize_t n=read(c,b,sizeof(b)-1); if(n<=0){close(c);return 5;} printf("SERVER_RX %s\n",b); char out[320]; int m=snprintf(out,sizeof(out),"ACK:%s",b); if(write(c,out,(size_t)m)!=m){close(c);return 6;} close(c); }
 close(s); puts("SERVER_DONE"); return 0;
}
static int client(const char *ip,int port,const char *msg){
 int s=-1; struct sockaddr_in a={0}; a.sin_family=AF_INET; a.sin_port=htons((unsigned short)port); if(inet_pton(AF_INET,ip,&a.sin_addr)!=1)return 2;
 for(int i=0;i<200;i++){ s=socket(AF_INET,SOCK_STREAM,0); if(s<0)return 3; if(connect(s,(struct sockaddr*)&a,sizeof(a))==0)break; close(s); s=-1; msleep(50); }
 if(s<0){fprintf(stderr,"connect timeout to %s:%d\n",ip,port);return 4;} if(write(s,msg,strlen(msg))!=(ssize_t)strlen(msg))return 5;
 char b[320]={0}, expect[320]; ssize_t n=read(s,b,sizeof(b)-1); close(s); if(n<=0)return 6; snprintf(expect,sizeof(expect),"ACK:%s",msg); printf("CLIENT_RX %s\n",b); return strcmp(b,expect)?7:0;
}
int main(int argc,char **argv){ if(argc>=2&&!strcmp(argv[1],"server")&&argc==4)return server(atoi(argv[2]),atoi(argv[3])); if(argc==5&&!strcmp(argv[1],"client"))return client(argv[2],atoi(argv[3]),argv[4]); fprintf(stderr,"usage: %s server PORT COUNT | client IP PORT MSG\n",argv[0]); return 2; }
