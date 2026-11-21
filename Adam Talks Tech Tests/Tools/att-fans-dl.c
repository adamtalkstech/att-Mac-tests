// att-fans (ready-made build): same as Tools/att-fans.c, but IOKit is opened at run time
// with dlopen, so it can be built without Xcode. Output format is identical.
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

typedef unsigned int mach_port_t;
typedef mach_port_t io_object_t, io_service_t, io_connect_t;
typedef int kern_return_t;
extern mach_port_t mach_task_self_;

typedef struct { char major, minor, build, reserved; uint16_t release; } smc_vers_t;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } smc_plimit_t;
typedef struct { uint32_t dataSize; uint32_t dataType; uint8_t dataAttributes; } smc_keyinfo_t;
typedef struct {
  uint32_t key; smc_vers_t vers; smc_plimit_t pLimitData; smc_keyinfo_t keyInfo;
  uint8_t result, status, data8; uint32_t data32; uint8_t bytes[32];
} smc_data_t;
_Static_assert(sizeof(smc_data_t) == 80, "SMC struct must be 80 bytes");

static void *(*pMatching)(const char *);
static io_service_t (*pGetService)(mach_port_t, void *);
static kern_return_t (*pOpen)(io_service_t, mach_port_t, uint32_t, io_connect_t *);
static kern_return_t (*pCall)(io_connect_t, uint32_t, const void *, size_t, void *, size_t *);
static kern_return_t (*pClose)(io_connect_t);
static kern_return_t (*pRelease)(io_object_t);
static io_connect_t conn;

static uint32_t fourcc(const char *s) {
  return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16) |
         ((uint32_t)(uint8_t)s[2] << 8) | (uint32_t)(uint8_t)s[3];
}
static int smc_call(smc_data_t *in, smc_data_t *out) {
  size_t osz = sizeof(*out);
  return pCall(conn, 2, in, sizeof(*in), out, &osz);
}
static int read_key(const char *key, uint8_t *buf, uint32_t *size, uint32_t *type) {
  smc_data_t in, out;
  memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
  in.key = fourcc(key); in.data8 = 9;
  if (smc_call(&in, &out) != 0 || out.result) return -1;
  *size = out.keyInfo.dataSize; *type = out.keyInfo.dataType;
  memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
  in.key = fourcc(key); in.keyInfo.dataSize = *size; in.data8 = 5;
  if (smc_call(&in, &out) != 0 || out.result) return -1;
  memcpy(buf, out.bytes, 32);
  return 0;
}
static double read_num(const char *key) {
  uint8_t b[32]; uint32_t sz = 0, t = 0;
  if (read_key(key, b, &sz, &t)) return -1;
  if (t == fourcc("flt ") && sz == 4) { float f; memcpy(&f, b, 4); return f; }
  if (t == fourcc("fpe2") && sz == 2) return ((b[0] << 8) | b[1]) / 4.0;
  if (t == fourcc("ui8 ")) return b[0];
  if (t == fourcc("ui16") && sz == 2) return (b[0] << 8) | b[1];
  return -1;
}
static void fan_key(char *k, int i, const char *suffix) { snprintf(k, 5, "F%d%s", i, suffix); }

int main(int argc, char **argv) {
  void *io = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
  if (!io) { fprintf(stderr, "att-fans: can't open IOKit\n"); return 1; }
  pMatching = dlsym(io, "IOServiceMatching");
  pGetService = dlsym(io, "IOServiceGetMatchingService");
  pOpen = dlsym(io, "IOServiceOpen");
  pCall = dlsym(io, "IOConnectCallStructMethod");
  pClose = dlsym(io, "IOServiceClose");
  pRelease = dlsym(io, "IOObjectRelease");
  if (!pMatching || !pGetService || !pOpen || !pCall) { fprintf(stderr, "att-fans: IOKit calls missing\n"); return 1; }
  io_service_t svc = pGetService(0, pMatching("AppleSMC"));
  if (!svc || pOpen(svc, mach_task_self_, 0, &conn) != 0) { fprintf(stderr, "att-fans: can't open the SMC\n"); return 1; }
  if (pRelease) pRelease(svc);
  double nf = read_num("FNum"); int n = nf > 0 ? (int)nf : 0;
  char k[5];
  if (argc >= 3 && strcmp(argv[1], "-i") == 0) {
    int secs = atoi(argv[2]); if (secs < 1) secs = 5;
    setvbuf(stdout, NULL, _IOLBF, 0);
    for (;;) {
      printf("%ld", (long)time(NULL));
      for (int i = 0; i < n; i++) { fan_key(k, i, "Ac"); printf(" %.0f", read_num(k)); }
      printf("\n"); sleep(secs);
    }
  }
  if (argc >= 2 && strcmp(argv[1], "-m") == 0) {
    printf("%d", n);
    for (int i = 0; i < n; i++) { char k2[5]; fan_key(k, i, "Mn"); fan_key(k2, i, "Mx"); printf(" %.0f-%.0f", read_num(k), read_num(k2)); }
    printf("\n"); return 0;
  }
  printf("%d", n);
  for (int i = 0; i < n; i++) { fan_key(k, i, "Ac"); printf(" %.0f", read_num(k)); }
  printf("\n");
  if (pClose) pClose(conn);
  return 0;
}
