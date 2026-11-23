#ifndef FYCRYPTO_H
#define FYCRYPTO_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint8_t opaque[128];
} SHA256_CTX;

typedef struct {
    uint8_t opaque[384];
} HMAC_SHA256_CTX;

typedef struct {
    uint8_t opaque[240];
} AES256_CTX;

typedef struct {
    uint8_t opaque[352];
} AES256_GCM_CTX;

_Static_assert(sizeof(SHA256_CTX) == 128, "SHA256_CTX deve ter 128 bytes");
_Static_assert(sizeof(HMAC_SHA256_CTX) == 384, "HMAC_SHA256_CTX deve ter 384 bytes");
_Static_assert(sizeof(AES256_CTX) == 240, "AES256_CTX deve ter 240 bytes");
_Static_assert(sizeof(AES256_GCM_CTX) == 352, "AES256_GCM_CTX deve ter 352 bytes");

/* SHA-256 */
void sha256_inicia(SHA256_CTX *ctx);
void sha256_adiciona(SHA256_CTX *ctx, const void *dados, size_t tam);
void sha256_finaliza(SHA256_CTX *ctx, uint8_t digest[32]);
void sha256(void *saida, const void *dados, size_t tam);

/* HMAC-SHA256 */
void hmac_sha256_inicia(HMAC_SHA256_CTX *ctx, const void *chave, size_t tam_chave);
void hmac_sha256_adiciona(HMAC_SHA256_CTX *ctx, const void *dados, size_t tam);
void hmac_sha256_finaliza(HMAC_SHA256_CTX *ctx, uint8_t tag[32]);
void hmac_sha256(uint8_t tag[32], const void *chave, size_t tam_chave,
                 const void *dados, size_t tam);

/* AES-256 */
void aes256_inicia(AES256_CTX *ctx, const uint8_t chave[32]);
void aes256_criptografa_bloco(AES256_CTX *ctx, const uint8_t in[16], uint8_t out[16]);
void aes256_descriptografa_bloco(AES256_CTX *ctx, const uint8_t in[16], uint8_t out[16]);
long aes256_cbc_criptografa(AES256_CTX *ctx, const uint8_t iv[16],
                              const void *in, void *out, size_t tam);
long aes256_cbc_descriptografa(AES256_CTX *ctx, const uint8_t iv[16],
                                 const void *in, void *out, size_t tam);

/* AES-256-GCM */
void aes256_gcm_inicia(AES256_GCM_CTX *ctx, const uint8_t chave[32], const uint8_t iv[12]);
void aes256_gcm_ad(AES256_GCM_CTX *ctx, const void *dados_associados, size_t tam);
long aes256_gcm_criptografa(AES256_GCM_CTX *ctx, const void *plano, void *cifrado,
                              size_t tam, uint8_t tag[16]);
long aes256_gcm_descriptografa(AES256_GCM_CTX *ctx, const void *cifrado, void *plano,
                                 size_t tam, const uint8_t tag[16]);

/* PBKDF2-HMAC-SHA256 */
void pbkdf2_sha256(uint8_t *dk, const void *senha, size_t tam_senha,
                   const void *sal, size_t tam_sal,
                   uint64_t iteracoes, size_t dk_len);

/* Utilitários */
void crypto_limpa_memoria(void *ptr, size_t tam);
int crypto_compara_constante_tempo(const void *a, const void *b, size_t tam);

#ifdef __cplusplus
}
#endif

#endif
