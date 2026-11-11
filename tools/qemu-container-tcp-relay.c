#include <arpa/inet.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
static int connect_target(const char *host,int port){int s=socket(AF_INET,SOCK_STREAM,0);struct sockaddr_in a={0};a.sin_family=AF_INET;a.sin_port=htons(port);inet_pton(AF_INET,host,&a.sin_addr);if(connect(s,(void*)&a,sizeof(a))<0)return -1;return s;}
static void pump(int a,int b){char buf[65536];fd_set r;for(;;){FD_ZERO(&r);FD_SET(a,&r);FD_SET(b,&r);int m=a>b?a:b;if(select(m+1,&r,0,0,0)<=0)break;int x=FD_ISSET(a,&r)?a:b,y=x==a?b:a;ssize_t n=read(x,buf,sizeof(buf));if(n<=0)break;for(ssize_t o=0;o<n;){ssize_t w=write(y,buf+o,n-o);if(w<=0)goto done;o+=w;}}done: close(a);close(b);}
int main(int c,char**v){if(c!=4)return 2;int port=atoi(v[1]),target=atoi(v[3]);signal(SIGCHLD,SIG_IGN);int s=socket(AF_INET,SOCK_STREAM,0),one=1;setsockopt(s,SOL_SOCKET,SO_REUSEADDR,&one,sizeof(one));struct sockaddr_in a={0};a.sin_family=AF_INET;a.sin_port=htons(port);a.sin_addr.s_addr=htonl(INADDR_ANY);if(bind(s,(void*)&a,sizeof(a))||listen(s,16))return 3;for(;;){int x=accept(s,0,0);if(x<0)continue;if(!fork()){close(s);int y=connect_target(v[2],target);if(y<0)_exit(4);pump(x,y);_exit(0);}close(x);}}
