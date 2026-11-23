#ifndef FYD_MJPEG_H
#define FYD_MJPEG_H

#include <stdint.h>
#include <stddef.h>

typedef struct {
    uint32_t *pixels;
    int       largura;
    int       altura;
    int       pitch_pixels; /* largura da linha em pixels (ex.: largura ou stride) */
} fyd_imagem_buf_t;

/* Decodifica um quadro JPEG/MJPEG baseline (SOF0) em saida->pixels (0xFFRRGGBB).
 * Entrada: saida->pixels != NULL, saida->largura e saida->altura definem o limite
 * maximo suportado pelo buffer de destino (serao atualizados para as dimensoes reais).
 * Retorno: 1 em sucesso, 0 em erro/formato nao suportado. */
int fyd_mjpeg_decodificar(const uint8_t *dados, size_t tam, fyd_imagem_buf_t *saida);

#endif