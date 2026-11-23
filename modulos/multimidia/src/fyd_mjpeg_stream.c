#include "fyd_mjpeg_stream.h"

int fyd_mjpeg_proximo_quadro(const uint8_t *stream, size_t stream_tam,
                             size_t *cursor_pos,
                             const uint8_t **out_jpg, size_t *out_jpg_tam) {
    if (!stream || !cursor_pos || !out_jpg || !out_jpg_tam) return 0;
    if (*cursor_pos + 3 >= stream_tam) return 0;

    size_t i = *cursor_pos;
    size_t inicio = 0;
    int achou_soi = 0;

    while (i + 1 < stream_tam) {
        if (stream[i] == 0xFF && stream[i + 1] == 0xD8) {
            inicio = i;
            achou_soi = 1;
            i += 2;
            break;
        }
        i++;
    }

    if (!achou_soi) {
        *cursor_pos = stream_tam;
        return 0;
    }

    while (i + 1 < stream_tam) {
        if (stream[i] == 0xFF && stream[i + 1] == 0xD9) {
            size_t fim = i + 2;
            *out_jpg = stream + inicio;
            *out_jpg_tam = fim - inicio;
            *cursor_pos = fim;
            return 1;
        }
        i++;
    }

    /* Quadro incompleto no fim do buffer */
    *cursor_pos = stream_tam;
    return 0;
}

int fyd_mjpeg_ler_e_decodificar(const uint8_t *stream, size_t stream_tam,
                                size_t *cursor_pos, fyd_imagem_buf_t *saida) {
    const uint8_t *jpg = 0;
    size_t jpg_tam = 0;

    if (!fyd_mjpeg_proximo_quadro(stream, stream_tam, cursor_pos, &jpg, &jpg_tam)) {
        return 0;
    }
    return fyd_mjpeg_decodificar(jpg, jpg_tam, saida);
}