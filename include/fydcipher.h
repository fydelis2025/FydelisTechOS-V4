#ifndef FYDELIS_CIPHER_H
#define FYDELIS_CIPHER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ═══════════════════════════════════════════════════════════
//  DADOS DO ALGORITMO (Fydelis-Cipher v2 — 24 rodadas / XTS)
// ═══════════════════════════════════════════════════════════
#define FYCIPHER_BLOCO_TAM   16    // 128 bits
#define FYCIPHER_CHAVE_TAM   32    // 256 bits
#define FYCIPHER_RODADAS     24    // 24 rodadas Feistel 4 ramos + ARX

// Contexto — chave expandida (208 bytes exatos):
//   [0..15]   whitening W0..W3 (4 x uint32_t = 16 bytes)
//   [16..207] subchaves[24][2] (48 x uint32_t = 192 bytes)
typedef struct {
    uint32_t whitening[4];
    uint32_t subchaves[FYCIPHER_RODADAS][2];
} FydelisCipherCtx;

_Static_assert(sizeof(FydelisCipherCtx) == 208,
               "FydelisCipherCtx deve ter exatamente 208 bytes");

// ═══════════════════════════════════════════════════════════
//  FUNÇÕES PÚBLICAS
// ═══════════════════════════════════════════════════════════

/**
 * Expande a chave principal de 256 bits nas palavras de whitening
 * e nas 48 subchaves das 24 rodadas.
 */
void fydcipher_inicia(FydelisCipherCtx *ctx,
                      const uint8_t chave[FYCIPHER_CHAVE_TAM]);

/**
 * Criptografa UM bloco de 16 bytes.
 */
void fydcipher_criptografa(const FydelisCipherCtx *ctx,
                           const uint8_t entrada[FYCIPHER_BLOCO_TAM],
                           uint8_t saida[FYCIPHER_BLOCO_TAM]);

/**
 * Descriptografa UM bloco de 16 bytes.
 */
void fydcipher_descriptografa(const FydelisCipherCtx *ctx,
                              const uint8_t entrada[FYCIPHER_BLOCO_TAM],
                              uint8_t saida[FYCIPHER_BLOCO_TAM]);

/**
 * Modo XTS (setor de disco) — criptografa in-place com tweak por setor.
 * tam deve ser múltiplo de 16 bytes.
 * Retorna: 0 = ok, -1 = tamanho inválido.
 */
long fydcipher_xts_criptografa(const FydelisCipherCtx *ctx,
                               uint64_t numero_setor,
                               void *dados,
                               size_t tam);

/**
 * Modo XTS (setor de disco) — descriptografa in-place com tweak por setor.
 * tam deve ser múltiplo de 16 bytes.
 * Retorna: 0 = ok, -1 = tamanho inválido.
 */
long fydcipher_xts_descriptografa(const FydelisCipherCtx *ctx,
                                  uint64_t numero_setor,
                                  void *dados,
                                  size_t tam);

#ifdef __cplusplus
}
#endif

#endif // FYDELIS_CIPHER_H
