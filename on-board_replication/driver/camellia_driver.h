// camellia_driver.h
#ifndef CAMELLIA_DRIVER_H
#define CAMELLIA_DRIVER_H

#include <stdint.h>

int hw_init();
void hw_cleanup();
void camellia_encrypt_gcm(uint32_t key_len_flag, uint32_t *key, uint32_t *iv, 
                          uint8_t *aad, uint32_t aad_len,
                          uint8_t *pt, uint32_t pt_len);

#endif