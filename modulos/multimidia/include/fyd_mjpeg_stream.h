#ifndef FYD_MJPEG_STREAM_H
#define FYD_MJPEG_STREAM_H

#include <stdint.h>
#include <stddef.h>
#include "fyd_mjpeg.h"

/* Localiza o proximo quadro JPEG (0xFFD8 .. 0xFFD9) dentro de um buffer MJPEG.
 * *cursor_pos e atualizado para o byte apos o EOI (0xFFD9).
 * Retorno: 1 se encontrou um quadro completo, 0 se acabou ou nao ha quadro valido. */
int fyd_mjpeg_proximo_quadro(const uint8_t *stream, size_t stream_tam,
                             size_t *cursor_pos,
                             const uint8_t **out_jpg, size_t *out_jpg_tam);

/* Decodifica o proximo quadro do stream diretamente no buffer de imagem.
 * Retorno: 1 em sucesso, 0 em erro/fim do fluxo. */
int fyd_mjpeg_ler_e_decodificar(const uint8_t *stream, size_t stream_tam,
                                size_t *cursor_pos, fyd_imagem_buf_t *saida);

#endif