// att_ssd.c - internal SSD speed tester for ATT Mac tests (v1, Nov 22 2026). No Homebrew, no fio.
// Built on each Mac with clang (Xcode Command Line Tools), like the memory bandwidth test.
// Every file is opened with the Mac's file cache OFF (F_NOCACHE), so reads come from the SSD, not RAM.
//   att_ssd seq  <file> <MB> <threads> <runs>   -> "SEQ write_MBps read_MBps" (best of runs)
//   att_ssd rand <file> <seconds> <qd>          -> "RAND qd read_MBps write_MBps"  (file from seq)
//   att_ssd sus  <file> <GB>                    -> "S sec MBps GBdone" every second, then "SUSDONE secs"
//   att_ssd make <file> <MB>                    -> writes a file of random data (copy test source)
//   att_ssd copy <src> <dst>                    -> "COPY seconds" real read+write copy, 8MB blocks (APFS can't clone it)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/time.h>
#include <stdint.h>
#define MB (1024LL*1024LL)
static double now(void){ struct timeval t; gettimeofday(&t,0); return t.tv_sec + t.tv_usec/1e6; }
static void nocache(int fd){
#ifdef F_NOCACHE
  fcntl(fd, F_NOCACHE, 1);
#endif
}
static void *abuf(size_t n){ void *p; if(posix_memalign(&p, 16384, n)) { perror("mem"); exit(1); }
  uint64_t x=88172645463325252ULL; for(size_t i=0;i<n/8;i++){ x^=x<<13; x^=x>>7; x^=x<<17; ((uint64_t*)p)[i]=x; } return p; }
static int openf(const char *f, int fl){ int fd=open(f, fl, 0644); if(fd<0){ perror(f); exit(1);} nocache(fd); return fd; }

typedef struct { int fd; long long off, len; int wr; } seqarg;
static void *seqw(void *a_){ seqarg *a=a_; char *b=abuf(MB); for(long long o=0;o<a->len;o+=MB){
    ssize_t r = a->wr ? pwrite(a->fd,b,MB,a->off+o) : pread(a->fd,b,MB,a->off+o); if(r!=MB){ perror("io"); exit(1);} } free(b); return 0; }
static double seqpass(const char *f, long long mb, int th, int wr){
  int fd=openf(f, wr? (O_RDWR|O_CREAT) : O_RDONLY); pthread_t t[64]; seqarg a[64]; long long per=(mb/th)*MB;
  double t0=now(); for(int i=0;i<th;i++){ a[i]=(seqarg){fd,i*per,per,wr}; pthread_create(&t[i],0,seqw,&a[i]); }
  for(int i=0;i<th;i++) pthread_join(t[i],0); if(wr) fsync(fd); double s=now()-t0; close(fd); return (per*th/(double)MB)/s; }

typedef struct { int fd; long long blocks; double until; int wr; long long done; unsigned seed; } rarg;
static void *rw(void *a_){ rarg *a=a_; char *b=abuf(4096); while(now()<a->until){ for(int k=0;k<64;k++){
    long long blk = (long long)(rand_r(&a->seed)) % a->blocks; long long off=blk*4096;
    ssize_t r = a->wr ? pwrite(a->fd,b,4096,off) : pread(a->fd,b,4096,off); if(r!=4096){ perror("rio"); exit(1);} a->done++; } }
  free(b); return 0; }
static double randpass(const char *f, int secs, int qd, int wr){
  int fd=openf(f, O_RDWR); long long size=lseek(fd,0,SEEK_END); pthread_t t[64]; rarg a[64];
  double t0=now(), until=t0+secs; for(int i=0;i<qd;i++){ a[i]=(rarg){fd,size/4096,until,wr,0,(unsigned)(i*7919+1)}; pthread_create(&t[i],0,rw,&a[i]); }
  long long tot=0; for(int i=0;i<qd;i++){ pthread_join(t[i],0); tot+=a[i].done; } if(wr) fsync(fd); double s=now()-t0; close(fd);
  return tot*4096.0/MB/s; }

int main(int c, char **v){
  if(c<3){ fprintf(stderr,"see the top of att_ssd.c\n"); return 1; }
  if(!strcmp(v[1],"seq")){ long long mb=atoll(v[3]); int th=atoi(v[4]), runs=atoi(v[5]); double bw=0, br=0;
    for(int r=0;r<runs;r++){ double w=seqpass(v[2],mb,th,1); double rd=seqpass(v[2],mb,th,0); if(w>bw)bw=w; if(rd>br)br=rd; sleep(5); }
    printf("SEQ %.0f %.0f\n", bw, br); return 0; }
  if(!strcmp(v[1],"rand")){ int secs=atoi(v[3]), qd=atoi(v[4]); if(qd>64) qd=64;
    double r=randpass(v[2],secs,qd,0); sleep(3); double w=randpass(v[2],secs,qd,1); printf("RAND %d %.1f %.1f\n", qd, r, w); return 0; }
  if(!strcmp(v[1],"make")){ long long mb=atoll(v[3]); int fd=openf(v[2],O_WRONLY|O_CREAT|O_TRUNC); char *b=abuf(8*MB);
    for(long long o=0;o<mb;o+=8){ if(write(fd,b,8*MB)!=8*MB){ perror("make"); return 1; } } fsync(fd); close(fd); return 0; }
  if(!strcmp(v[1],"copy")){ if(c<4) return 1; int in=openf(v[2],O_RDONLY), out=openf(v[3],O_WRONLY|O_CREAT|O_TRUNC); char *b=abuf(8*MB);
    double t0=now(); ssize_t r; while((r=read(in,b,8*MB))>0){ if(write(out,b,r)!=r){ perror("copy"); return 1; } }
    fsync(out); close(in); close(out); printf("COPY %.1f\n", now()-t0); return 0; }
  if(!strcmp(v[1],"sus")){ long long gb=atoll(v[3]); int fd=openf(v[2],O_WRONLY|O_CREAT|O_TRUNC); char *b=abuf(8*MB);
    long long total=gb*1024, done=0, lastdone=0; double t0=now(), last=t0; int sec=0;
    while(done<total){ if(write(fd,b,8*MB)!=8*MB){ perror("sus"); return 1; } done+=8; double t=now();
      if(t-last>=1.0){ sec++; printf("S %d %.0f %.2f\n", sec, (done-lastdone)/(t-last), done/1024.0); fflush(stdout); last=t; lastdone=done; } }
    fsync(fd); close(fd); printf("SUSDONE %.1f\n", now()-t0); return 0; }
  return 1;
}
