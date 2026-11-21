// att-fans.c - reads the Mac's fan speeds straight from the SMC (fan controller).
// Works on Apple Silicon and Intel. No password needed.
//
// Built automatically by Tools/att-card.zsh the first time it's needed
// (needs Xcode or the Command Line Tools). You don't run this by hand;
// to check a Mac's fans, run:  zsh ~/Downloads/"Adam Talks Tech Tests"/Tools/att-fans.zsh
//
//   att-fans            -> one line: <fan count> <fan0 rpm> <fan1 rpm> ...
//   att-fans -m         -> one line: <fan count> then "min-max" for each fan
//   att-fans -i 5       -> every 5 s: <unix time> <fan0 rpm> <fan1 rpm> ... (until killed)
// Fanless Macs (MacBook Air) print 0.

#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

typedef struct { char major, minor, build, reserved; uint16_t release; } smc_vers_t;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } smc_plimit_t;
typedef struct { uint32_t dataSize; uint32_t dataType; uint8_t dataAttributes; } smc_keyinfo_t;
typedef struct {
  uint32_t key;
  smc_vers_t vers;
  smc_plimit_t pLimitData;
  smc_keyinfo_t keyInfo;
  uint8_t result, status, data8;
  uint32_t data32;
  uint8_t bytes[32];
} smc_data_t;

static io_connect_t conn;

static uint32_t fourcc(const char *s) {
  return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16) |
         ((uint32_t)(uint8_t)s[2] << 8) | (uint32_t)(uint8_t)s[3];
}

static int smc_call(smc_data_t *in, smc_data_t *out) {
  size_t osz = sizeof(*out);
  return IOConnectCallStructMethod(conn, 2, in, sizeof(*in), out, &osz);
}

static int read_key(const char *key, uint8_t *buf, uint32_t *size, uint32_t *type) {
  smc_data_t in, out;
  memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
  in.key = fourcc(key);
  in.data8 = 9;                                   // read key info
  if (smc_call(&in, &out) != kIOReturnSuccess || out.result) return -1;
  *size = out.keyInfo.dataSize;
  *type = out.keyInfo.dataType;
  memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
  in.key = fourcc(key);
  in.keyInfo.dataSize = *size;
  in.data8 = 5;                                   // read bytes
  if (smc_call(&in, &out) != kIOReturnSuccess || out.result) return -1;
  memcpy(buf, out.bytes, 32);
  return 0;
}

static double read_num(const char *key) {
  uint8_t b[32]; uint32_t sz = 0, t = 0;
  if (read_key(key, b, &sz, &t)) return -1;
  if (t == fourcc("flt ") && sz == 4) { float f; memcpy(&f, b, 4); return f; }   // Apple Silicon
  if (t == fourcc("fpe2") && sz == 2) return ((b[0] << 8) | b[1]) / 4.0;        // Intel
  if (t == fourcc("ui8 ")) return b[0];
  if (t == fourcc("ui16") && sz == 2) return (b[0] << 8) | b[1];
  return -1;
}

static int fan_count(void) {
  double n = read_num("FNum");
  return n > 0 ? (int)n : 0;
}

static void fan_key(char *k, int i, const char *suffix) { snprintf(k, 5, "F%d%s", i, suffix); }

int main(int argc, char **argv) {
  io_service_t svc = IOServiceGetMatchingService(0, IOServiceMatching("AppleSMC"));
  if (!svc || IOServiceOpen(svc, mach_task_self(), 0, &conn) != kIOReturnSuccess) {
    fprintf(stderr, "att-fans: can't open the SMC\n");
    return 1;
  }
  IOObjectRelease(svc);
  int n = fan_count();
  char k[5];

  if (argc >= 3 && strcmp(argv[1], "-i") == 0) {
    int secs = atoi(argv[2]); if (secs < 1) secs = 5;
    setvbuf(stdout, NULL, _IOLBF, 0);
    for (;;) {
      printf("%ld", (long)time(NULL));
      for (int i = 0; i < n; i++) { fan_key(k, i, "Ac"); printf(" %.0f", read_num(k)); }
      printf("\n");
      sleep(secs);
    }
  }
  if (argc >= 2 && strcmp(argv[1], "-m") == 0) {
    printf("%d", n);
    for (int i = 0; i < n; i++) {
      char k2[5]; fan_key(k, i, "Mn"); fan_key(k2, i, "Mx");
      printf(" %.0f-%.0f", read_num(k), read_num(k2));
    }
    printf("\n");
    return 0;
  }
  printf("%d", n);
  for (int i = 0; i < n; i++) { fan_key(k, i, "Ac"); printf(" %.0f", read_num(k)); }
  printf("\n");
  IOServiceClose(conn);
  return 0;
}
