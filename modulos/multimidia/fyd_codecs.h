#ifndef FYD_CODECS_H
#define FYD_CODECS_H

#include <stdint.h>
#include <stddef.h>

typedef struct {
    int16_t *esquerdo;
    int16_t *direito;
    size_t   capacidade;
    size_t   quantidade;
    uint32_t taxa_hz;
    uint8_t  canais;
} fyd_audio_buf_t;

typedef struct {
    uint32_t *pixels;
    int       largura;
    int       altura;
    int       pitch_pixels;
} fyd_imagem_buf_t;

typedef struct fyd_codec {
    const char *nome;
    int (*decodificar_audio)(const uint8_t *dados, size_t tam, fyd_audio_buf_t *saida);
    int (*decodificar_video)(const uint8_t *dados, size_t tam, fyd_imagem_buf_t *saida);
} fyd_codec_t;

int fyd_wav_decodificar(const uint8_t *dados, size_t tam, fyd_audio_buf_t *saida);
int fyd_mp3_decodificar(const uint8_t *dados, size_t tam, fyd_audio_buf_t *saida);
int fyd_mjpeg_decodificar(const uint8_t *dados, size_t tam, fyd_imagem_buf_t *saida);

#endif