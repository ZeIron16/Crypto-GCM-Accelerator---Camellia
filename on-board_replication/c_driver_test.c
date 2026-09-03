#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <time.h>

#define CAMELLIA_BASE_ADDR   0x43C00000
#define BRAM_CPU_BASE        0x40000000
#define MAP_SIZE             4096

#define REG_CTRL             0x00  
#define REG_AAD_ADDR         0x04
#define REG_AAD_LEN          0x08
#define REG_PAYLOAD_ADDR     0x0C
#define REG_PAYLOAD_LEN      0x10
#define REG_CIPHER_ADDR      0x14
#define REG_CIPHER_LEN       0x18
#define REG_KEY_LEN          0x1C

#define REG_KEY_HIGH_BASE    0x20  
#define REG_IV_BASE          0x30  
#define REG_TAG_BASE         0x40  
#define REG_KEY_LOW_BASE     0x50  

typedef struct {
    int count;
    uint32_t key_len_flag;  
    uint32_t key[8];
    uint32_t iv[3];
    uint8_t aad[64];
    uint32_t aad_len;
    uint8_t pt[128];
    uint32_t pt_len;
    const char *expected_ct;
    const char *expected_tag;
} test_vector_t;

volatile uint32_t *crypto_regs = NULL;
volatile uint8_t  *shared_bram = NULL;
int mem_fd = -1;

int hw_init() {
    mem_fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (mem_fd < 0) {
        perror("Failed to open /dev/mem (run as root)");
        return -1;
    }

    void *reg_map = mmap(NULL, MAP_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, mem_fd, CAMELLIA_BASE_ADDR);
    if (reg_map == MAP_FAILED) {
        perror("mmap failed for IP registers");
        close(mem_fd);
        return -1;
    }
    crypto_regs = (volatile uint32_t *)reg_map;

    void *bram_map = mmap(NULL, MAP_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, mem_fd, BRAM_CPU_BASE);
    if (bram_map == MAP_FAILED) {
        perror("mmap failed for shared BRAM");
        munmap((void*)crypto_regs, MAP_SIZE);
        close(mem_fd);
        return -1;
    }
    shared_bram = (volatile uint8_t *)bram_map;

    return 0;
}

// Reverses the order of four 32-bit words within every 16-byte block (Mirrors Python's logic)
void copy_to_bram_blocks(volatile uint8_t *dest, const uint8_t *src, uint32_t len) {
    uint32_t pad_len = (len + 15) & ~15; 
    for (uint32_t b = 0; b < pad_len; b += 16) {
        for (int w = 0; w < 4; w++) {
            uint32_t word = 0;
            int src_idx = b + (3 - w) * 4; 
            if (src_idx < len)     word |= (src[src_idx]   << 24);
            if (src_idx+1 < len)   word |= (src[src_idx+1] << 16);
            if (src_idx+2 < len)   word |= (src[src_idx+2] << 8);
            if (src_idx+3 < len)   word |= (src[src_idx+3]);
            *((volatile uint32_t*)(dest + b + w * 4)) = word;
        }
    }
}

// Reads blocks from BRAM, restoring original word order and truncating padding
void copy_from_bram_blocks(uint8_t *dest, volatile uint8_t *src, uint32_t len) {
    uint32_t pad_len = (len + 15) & ~15;
    for (uint32_t b = 0; b < pad_len; b += 16) {
        for (int w = 0; w < 4; w++) {
            uint32_t word = *((volatile uint32_t*)(src + b + w * 4));
            int dest_idx = b + (3 - w) * 4;
            if (dest_idx < len)     dest[dest_idx]   = (word >> 24) & 0xFF;
            if (dest_idx+1 < len)   dest[dest_idx+1] = (word >> 16) & 0xFF;
            if (dest_idx+2 < len)   dest[dest_idx+2] = (word >> 8)  & 0xFF;
            if (dest_idx+3 < len)   dest[dest_idx+3] =  word & 0xFF;
        }
    }
}

void write_reg(uint32_t offset, uint32_t value) {
    crypto_regs[offset / 4] = value;
}

uint32_t read_reg(uint32_t offset) {
    return crypto_regs[offset / 4];
}

void execute_single_vector_verification(test_vector_t *v) {
    uint32_t hw_aad_addr = 0x000;
    uint32_t hw_pt_addr  = 0x200;
    uint32_t hw_ct_addr  = 0x600;

    uint32_t padded_aad_len = (v->aad_len + 15) & ~15;
    uint32_t padded_pt_len  = (v->pt_len + 15) & ~15;

    if (v->aad_len > 0) copy_to_bram_blocks(shared_bram + hw_aad_addr, v->aad, v->aad_len);
    if (v->pt_len  > 0) copy_to_bram_blocks(shared_bram + hw_pt_addr,  v->pt,  v->pt_len);

    write_reg(REG_KEY_LEN, v->key_len_flag);
    for (int i = 0; i < 4; i++) write_reg(REG_KEY_HIGH_BASE + (i * 4), v->key[i]);
    for (int i = 0; i < 4; i++) write_reg(REG_KEY_LOW_BASE  + (i * 4), v->key[i + 4]);
    for (int i = 0; i < 3; i++) write_reg(REG_IV_BASE       + (i * 4), v->iv[i]);

    write_reg(REG_AAD_ADDR,      hw_aad_addr);
    write_reg(REG_AAD_LEN,       padded_aad_len);
    write_reg(REG_PAYLOAD_ADDR,  hw_pt_addr);
    write_reg(REG_PAYLOAD_LEN,   padded_pt_len);
    write_reg(REG_CIPHER_ADDR,   hw_ct_addr);
    write_reg(REG_CIPHER_LEN,    padded_pt_len); 

    write_reg(REG_CTRL, 1);
    while ((read_reg(REG_CTRL) & 0x02) == 0);

    uint8_t ct_output[128];
    if (v->pt_len > 0) {
        copy_from_bram_blocks(ct_output, shared_bram + hw_ct_addr, v->pt_len);
    }

    printf("\n--------------------------------------------------\n");
    printf("[VECTOR] Key length: %d bits | Count: %d\n", (v->key_len_flag == 0) ? 128 : 256, v->count);
    printf("Expected CT : %s\n", v->expected_ct);
    printf("Got CT      : ");
    for (uint32_t i = 0; i < v->pt_len; i++) printf("%02X", ct_output[i]);
    printf("\n");
    printf("Expected Tag: %s\n", v->expected_tag);
    printf("Got Tag     : ");
    for (int i = 0; i < 4; i++) printf("%08X", read_reg(REG_TAG_BASE + (i * 4)));
    printf("\n--------------------------------------------------\n");
}

void hw_cleanup() {
    if (crypto_regs) munmap((void*)crypto_regs, MAP_SIZE);
    if (shared_bram) munmap((void*)shared_bram, MAP_SIZE);
    if (mem_fd >= 0) close(mem_fd);
}

void benchmark_asymptotic_throughput(int iterations) {
    uint32_t payload_bytes = 1024;
    uint64_t total_payload_bytes = 0;
    struct timespec start_time, end_time;
    double total_time_sec = 0.0;

    uint32_t hw_pt_addr = 0x000;
    uint32_t hw_ct_addr = 0x800;

    write_reg(REG_KEY_LEN,      0);
    write_reg(REG_AAD_LEN,      0);
    write_reg(REG_PAYLOAD_ADDR, hw_pt_addr);
    write_reg(REG_PAYLOAD_LEN,  payload_bytes);
    write_reg(REG_CIPHER_ADDR,  hw_ct_addr);
    write_reg(REG_CIPHER_LEN,   payload_bytes); 

    printf("\n[+] Starting asymptotic benchmark (payload = 1024 bytes | %d iterations)...\n", iterations);

    for (int iter = 0; iter < iterations; iter++) {
        clock_gettime(CLOCK_MONOTONIC, &start_time);

        write_reg(REG_CTRL, 1);
        while ((read_reg(REG_CTRL) & 0x02) == 0);

        clock_gettime(CLOCK_MONOTONIC, &end_time);

        double elapsed = (end_time.tv_sec  - start_time.tv_sec) +
                         (end_time.tv_nsec - start_time.tv_nsec) / 1e9;
        total_time_sec      += elapsed;
        total_payload_bytes += payload_bytes;
    }

    double total_bits = (double)total_payload_bytes * 8.0;
    double mbps = (total_bits / total_time_sec) / 1000000.0;

    printf("\n==================================================\n");
    printf("         ASYMPTOTIC BENCHMARK (MAX THROUGHPUT)    \n");
    printf("==================================================\n");
    printf("  Total hardware time  : %f sec\n",          total_time_sec);
    printf("  Total data processed : %.2f Megabits\n",   total_bits / 1000000.0);
    printf("  Throughput           : %.2f Mbps\n",       mbps);
    printf("==================================================\n");
}

int main() {
    if (hw_init() != 0) return -1;

    test_vector_t vectors[4];

    // 128-bit key, Count 0
    vectors[0].count        = 0;
    vectors[0].key_len_flag = 0;
    vectors[0].key[0] = 0x1FB0A8EF; vectors[0].key[1] = 0x32D03496;
    vectors[0].key[2] = 0x3CDAF3F5; vectors[0].key[3] = 0x4AD8DF8E;
    vectors[0].key[4] = 0x1FB0A8EF; vectors[0].key[5] = 0x32D03496;
    vectors[0].key[6] = 0x3CDAF3F5; vectors[0].key[7] = 0x4AD8DF8E;
    vectors[0].iv[0]  = 0x8889AB26; vectors[0].iv[1]  = 0x50F69A90; vectors[0].iv[2]  = 0x7DE2F664;
    vectors[0].aad_len = 32;
    uint8_t aad0[] = {0x77,0xA4,0x98,0x20,0xD1,0xE9,0xA7,0x97,0xE7,0x60,0x03,0xA0,0xD1,0x1B,0xA7,0x03,
                      0x9B,0x40,0xEC,0x00,0x3B,0xBF,0xC1,0x59,0xBA,0x34,0x25,0xF3,0x92,0x6F,0x8C,0x14};
    memcpy(vectors[0].aad, aad0, 32);
    vectors[0].pt_len = 16;
    uint8_t pt0[] = {0xA5,0x2B,0x5E,0xBC,0x6E,0x7B,0xFF,0x6A,0xF1,0xB3,0x17,0x3B,0x8B,0xA1,0x2F,0x78};
    memcpy(vectors[0].pt, pt0, 16);
    vectors[0].expected_ct  = "C4AEE6847B0EFAD801ABC2215D198FB8";
    vectors[0].expected_tag = "008219FE25249D0AB75100CF0B803AB4";

    // 128-bit key, Count 1 
    vectors[1].count        = 1;
    vectors[1].key_len_flag = 0;
    vectors[1].key[0] = 0xAF1C7E90; vectors[1].key[1] = 0x46326F40;
    vectors[1].key[2] = 0xB6E6DDD1; vectors[1].key[3] = 0x05E98470;
    vectors[1].key[4] = 0xAF1C7E90; vectors[1].key[5] = 0x46326F40;
    vectors[1].key[6] = 0xB6E6DDD1; vectors[1].key[7] = 0x05E98470;
    vectors[1].iv[0]  = 0x2004CCDA; vectors[1].iv[1]  = 0x2BBB7756; vectors[1].iv[2]  = 0xBF0513CB;
    vectors[1].aad_len = 16;
    uint8_t aad1[] = {0x9B,0xFE,0xFB,0x9B,0x53,0xB0,0x54,0xFE,0xB2,0xB3,0xF8,0x19,0x11,0x05,0x22,0xE5};
    memcpy(vectors[1].aad, aad1, 16);
    vectors[1].pt_len = 48;
    // Fixed typo in pt1 payload block
    uint8_t pt1[] = {0xDA,0x9D,0x9F,0x47,0x3A,0x0D,0xAA,0xD4,0x9E,0x49,0x3B,0x57,0x71,0x89,0xDD,0xF2,
                     0xA3,0xF6,0xC3,0x05,0x27,0x34,0xD7,0x68,0xEC,0x53,0xD4,0x58,0x40,0xB0,0x3C,0x6F,
                     0xDC,0x0D,0x3E,0x66,0xF8,0xD9,0xCC,0xFF,0xBB,0x56,0x1F,0xCE,0x2B,0x10,0x2E,0xCC};
    memcpy(vectors[1].pt, pt1, 48);
    vectors[1].expected_ct  = "92CD06C8227095079B1F2117E05179207A6DD0002AF4A8CE4477A7E44EFF523794DC128F3FC6CA5E03D4766E4540189F";
    vectors[1].expected_tag = "8C3D2E10313EC2335F76A6279F90806C";

    // 128-bit key, Count 9
    vectors[2].count        = 9;
    vectors[2].key_len_flag = 0;
    vectors[2].key[0] = 0x1541CCA6; vectors[2].key[1] = 0xA52AAD99;
    vectors[2].key[2] = 0x30361040; vectors[2].key[3] = 0x65986F18;
    vectors[2].key[4] = 0x1541CCA6; vectors[2].key[5] = 0xA52AAD99;
    vectors[2].key[6] = 0x30361040; vectors[2].key[7] = 0x65986F18;
    vectors[2].iv[0]  = 0xD574C27B; vectors[2].iv[1]  = 0xA8EC407A; vectors[2].iv[2]  = 0xD5F5EFD2;
    vectors[2].aad_len = 16;
    // Fixed typo in aad2 payload block
    uint8_t aad2[] = {0xF8,0x37,0xC5,0x6A,0x23,0x93,0x92,0xDE,0xA7,0xAB,0xE9,0xED,0x56,0x37,0xE6,0x13};
    memcpy(vectors[2].aad, aad2, 16);
    vectors[2].pt_len = 16;
    uint8_t pt2[] = {0x23,0x64,0x59,0x22,0x69,0x44,0x8B,0x10,0x3C,0x51,0xBB,0x4C,0xF6,0x8F,0xF5,0x28};
    memcpy(vectors[2].pt, pt2, 16);
    vectors[2].expected_ct  = "59FB8F4D8E50F974D1AD4E3C17E184CA";
    vectors[2].expected_tag = "A76282859637655B362903A969ECE6D5";

    // 256-bit key, Count 6
    vectors[3].count        = 6;
    vectors[3].key_len_flag = 2;
    vectors[3].key[0] = 0x785C5693; vectors[3].key[1] = 0x6D8CA2ED;
    vectors[3].key[2] = 0xD0CD2277; vectors[3].key[3] = 0xD8015F68;
    vectors[3].key[4] = 0xB6D2308E; vectors[3].key[5] = 0x425523A5;
    vectors[3].key[6] = 0x72DD297C; vectors[3].key[7] = 0xEFD55C7C;
    vectors[3].iv[0]  = 0x1615155D; vectors[3].iv[1]  = 0x796132F6; vectors[3].iv[2]  = 0x1C61B2AF;
    vectors[3].aad_len = 16;
    uint8_t aad3[] = {0xBC,0x0A,0x51,0xEB,0x1F,0x8C,0xF8,0xB9,0xED,0x6F,0xD6,0xE5,0xF1,0xFD,0xA7,0x16};
    memcpy(vectors[3].aad, aad3, 16);
    vectors[3].pt_len = 16;
    uint8_t pt3[] = {0xEF,0x13,0x90,0xED,0x09,0x92,0xBD,0x2D,0xF8,0xA2,0xC7,0xDA,0x83,0xEB,0x10,0x98};
    memcpy(vectors[3].pt, pt3, 16);
    vectors[3].expected_ct  = "E8C6F9A270064707A9B7BA6E8B4FA684";
    vectors[3].expected_tag = "4B839C7B1A4234BF0F8A6FAECD7DB082";

    printf("[+] Step 1: Functional verification against JSON test vectors...\n");
    for (int i = 0; i < 4; i++) {
        execute_single_vector_verification(&vectors[i]);
    }

    // 20000 encryptions alternating key sizes and payload lengths
    benchmark_asymptotic_throughput(20000);

    hw_cleanup();
    return 0;
}