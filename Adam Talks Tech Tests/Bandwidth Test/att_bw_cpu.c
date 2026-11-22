// ATT memory bandwidth, CPU side (STREAM-style triad/copy, all cores). Nov 21 2026.
// Each thread works on its own slice of three big arrays (well past cache size).
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <time.h>
#include <unistd.h>
static size_t N; static int T; static double *a,*b,*c; static int mode;
typedef struct { size_t s,e; } R;
static void *work(void *p){ R *r=p; size_t i;
  if(mode==0) for(i=r->s;i<r->e;i++) c[i]=a[i];            // copy: 2 arrays touched
  else        for(i=r->s;i<r->e;i++) a[i]=b[i]+3.0*c[i];   // triad: 3 arrays touched
  return 0; }
static double now(){ struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec*1e-9; }
static double run(int m,int reps){ mode=m; pthread_t th[256]; R r[256]; double best=1e9;
  for(int k=0;k<reps;k++){ double t0=now();
    for(int i=0;i<T;i++){ r[i].s=N*i/T; r[i].e=N*(i+1)/T; pthread_create(&th[i],0,work,&r[i]); }
    for(int i=0;i<T;i++) pthread_join(th[i],0);
    double dt=now()-t0; if(dt<best) best=dt; }
  double bytes=(m==0?2.0:3.0)*N*sizeof(double); return bytes/best/1e9; }
int main(int argc,char**argv){
  size_t mb = argc>1? atol(argv[1]) : 1024;   // MB per array
  T = argc>2? atoi(argv[2]) : (int)sysconf(_SC_NPROCESSORS_ONLN); if(T>256)T=256;
  N = mb*1024*1024/sizeof(double);
  a=malloc(N*8); b=malloc(N*8); c=malloc(N*8); if(!a||!b||!c){puts("alloc failed");return 1;}
  for(size_t i=0;i<N;i++){a[i]=1;b[i]=2;c[i]=0;}
  run(0,1); // warm-up
  printf("CPU copy GB/s: %.1f\nCPU triad GB/s: %.1f\nthreads: %d  array MB: %zu\n", run(0,10), run(1,10), T, mb);
  return 0; }
