#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

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

void camellia_encrypt_gcm(test_vector_t *v) {
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