#include "fyd_codecs.h"

#pragma pack(push, 1)
typedef struct {
    char     riff[4];
    uint32_t tam_arquivo;
    char     wave[4];
    char     fmt[4];
    uint32_t tam_fmt;
    uint16_t formato_audio;
    uint16_t canais;
    uint32_t taxa_hz;
    uint32_t bytes_por_seg;
    uint16_t bloco_align;
    uint16_t bits_por_amostra;
} fyd_wav_cabecalho_t;
#pragma pack(pop)

/* Localiza o chunk "data" após o cabeçalho WAV para não ler header como áudio */
static int wav_achar_data(const uint8_t *dados, size_t tam,
                          const uint8_t **out_pcm, size_t *out_bytes) {
    if (!dados || !out_pcm || !out_bytes || tam < sizeof(fyd_wav_cabecalho_t) + 8)
        return 0;

    const fyd_wav_cabecalho_t *h = (const fyd_wav_cabecalho_t *)dados;
    if (h->riff[0] != 'R' || h->riff[1] != 'I' || h->riff[2] != 'F' || h->riff[3] != 'F' ||
        h->wave[0] != 'W' || h->wave[1] != 'A' || h->wave[2] != 'V' || h->wave[3] != 'E' ||
        h->fmt[0]  != 'f' || h->fmt[1]  != 'm' || h->fmt[2]  != 't' || h->fmt[3]  != ' ' ||
        h->formato_audio != 1 || h->canais == 0 || h->bits_por_amostra != 16)
        return 0;

    size_t pos = 12 + 8 + (size_t)h->tam_fmt;
    while (pos + 8 <= tam) {
        const uint8_t *c = dados + pos;
        uint32_t c_tam = (uint32_t)c[4] |
                         ((uint32_t)c[5] << 8) |
                         ((uint32_t)c[6] << 16) |
                         ((uint32_t)c[7] << 24);
        if (c[0] == 'd' && c[1] == 'a' && c[2] == 't' && c[3] == 'a') {
            pos += 8;
            if (pos + (size_t)c_tam > tam) c_tam = (uint32_t)(tam - pos);
            *out_pcm = dados + pos;
            *out_bytes = (size_t)c_tam;
            return 1;
        }
        pos += 8 + (size_t)c_tam + (c_tam & 1u);
    }
    return 0;
}

int fyd_wav_decodificar(const uint8_t *dados, size_t tam, fyd_audio_buf_t *saida) {
    if (!dados || !saida || !saida->esquerdo || saida->capacidade == 0) return 0;

    const fyd_wav_cabecalho_t *h = (const fyd_wav_cabecalho_t *)dados;
    const uint8_t *pcm = 0;
    size_t pcm_bytes = 0;
    if (!wav_achar_data(dados, tam, &pcm, &pcm_bytes)) return 0;

    size_t passo_bytes = (size_t)h->canais * 2u;
    size_t total_amostras = pcm_bytes / passo_bytes;
    if (total_amostras > saida->capacidade) total_amostras = saida->capacidade;

    const int16_t *amostras = (const int16_t *)pcm;
    for (size_t i = 0; i < total_amostras; i++) {
        if (h->canais == 1) {
            saida->esquerdo[i] = amostras[i];
            if (saida->direito) saida->direito[i] = amostras[i];
        } else {
            saida->esquerdo[i] = amostras[i * 2u];
            if (saida->direito) saida->direito[i] = amostras[i * 2u + 1u];
        }
    }

    saida->quantidade = total_amostras;
    saida->taxa_hz = h->taxa_hz;
    saida->canais = (uint8_t)h->canais;
    return 1;
}

/* Lê cabeçalho de quadro MP3 (sync 0xFFE) e informa parâmetros do fluxo */
int fyd_mp3_decodificar(const uint8_t *dados, size_t tam, fyd_audio_buf_t *saida) {
    if (!dados || tam < 4 || !saida || !saida->esquerdo || saida->capacidade == 0) return 0;

    const uint32_t taxas[3] = { 44100u, 48000u, 32000u };
    for (size_t i = 0; i + 3 < tam; i++) {
        if (dados[i] == 0xFF && (dados[i + 1] & 0xE0) == 0xE0) {
            uint8_t sr_idx = (dados[i + 2] >> 2) & 0x03;
            uint8_t modo   = (dados[i + 3] >> 6) & 0x03;
            if (sr_idx < 3) {
                saida->taxa_hz = taxas[sr_idx];
                saida->canais = (modo == 3) ? 1u : 2u;
                saida->quantidade = 0;
                return 1;
            }
        }
    }
    return 0;
}

/* Lê dimensões SOF de um quadro JPEG/MJPEG e prepara o buffer de saída */
int fyd_mjpeg_decodificar(const uint8_t *dados, size_t tam, fyd_imagem_buf_t *saida) {
    if (!dados || tam < 4 || !saida || !saida->pixels) return 0;

    size_t i = 0;
    int achou_soi = 0;
    while (i + 1 < tam) {
        if (dados[i] != 0xFF) { i++; continue; }
        uint8_t tipo = dados[i + 1];
        i += 2;

        if (tipo == 0xD8) {
            achou_soi = 1;
            continue;
        }
        if (tipo == 0xD9 || tipo == 0xDA) {
            break;
        }
        if (tipo == 0x00 || (tipo >= 0xD0 && tipo <= 0xD7)) {
            continue;
        }
        if (i + 1 >= tam) break;

        uint16_t seg_tam = (uint16_t)((dados[i] << 8) | dados[i + 1]);
        if (seg_tam < 2 || i + seg_tam > tam) break;

        if ((tipo & 0xF0) == 0xC0 && tipo != 0xC4 && tipo != 0xC8 && tipo != 0xCC) {
            if (seg_tam >= 7) {
                int altura  = (int)((dados[i + 3] << 8) | dados[i + 4]);
                int largura = (int)((dados[i + 5] << 8) | dados[i + 6]);
                if (largura <= 0 || altura <= 0 ||
                    largura > saida->largura || altura > saida->altura)
                    return 0;
                saida->largura = largura;
                saida->altura = altura;
                return achou_soi;
            }
        }
        i += seg_tam;
    }
    return 0;
}