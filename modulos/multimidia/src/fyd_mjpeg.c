#include "fyd_mjpeg.h"

#define FYD_JPG_MAX_COMPS 4
#define FYD_JPG_MAX_HUFF  4
#define FYD_JPG_MAX_QT    4

typedef struct {
    uint8_t  counts[17];     /* quantidade de codigos por comprimento 1..16 */
    uint8_t  symbols[256];   /* simbolos ordenados */
    int      min_code[17];   /* menor codigo inteiro para cada tamanho 1..16 */
    int      max_code[17];   /* maior codigo inteiro para cada tamanho 1..16 (-1 se vazio) */
    int      val_ptr[17];    /* indice inicial em symbols[] para cada tamanho */
    uint8_t  carregada;
} fyd_huff_t;

typedef struct {
    uint8_t  id;
    uint8_t  h_samp;
    uint8_t  v_samp;
    uint8_t  qt_idx;
    uint8_t  dc_idx;
    uint8_t  ac_idx;
    int32_t  dc_prev;
} fyd_comp_t;

typedef struct {
    const uint8_t *data;
    size_t         size;
    size_t         pos;
    uint32_t       bit_buf;
    int            bit_cnt;
    uint8_t        eof_stream;
} fyd_bits_t;

typedef struct {
    uint16_t   qt[FYD_JPG_MAX_QT][64];
    uint8_t    qt_ok[FYD_JPG_MAX_QT];
    fyd_huff_t huff_dc[FYD_JPG_MAX_HUFF];
    fyd_huff_t huff_ac[FYD_JPG_MAX_HUFF];
    fyd_comp_t comps[FYD_JPG_MAX_COMPS];
    int        num_comps;
    int        largura;
    int        altura;
    uint16_t   restart_interval;
} fyd_jpg_ctx_t;

/* Ordem natural (raster) de cada posicao no padrao Zig-Zag JPEG */
static const uint8_t FYD_ZIGZAG[64] = {
     0,  1,  8, 16,  9,  2,  3, 10,
    17, 24, 32, 25, 18, 11,  4,  5,
    12, 19, 26, 33, 40, 48, 41, 34,
    27, 20, 13,  6,  7, 14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36,
    29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46,
    53, 60, 61, 54, 47, 55, 62, 63
};

static uint8_t fyd_clamp_u8(int32_t valor_bruto) {
    if (valor_bruto < 0) return 0;
    if (valor_bruto > 255) return 255;
    return (uint8_t)valor_bruto;
}

static int fyd_ construir_huff(fyd_huff_t *ht) {
    int code = 0;
    int sym_idx = 0;
    int total = 0;

    for (int i = 1; i <= 16; i++) {
        total += ht->counts[i];
    }
    if (total > 256) return 0;

    for (int len = 1; len <= 16; len++) {
        int cnt = ht->counts[len];
        if (cnt == 0) {
            ht->min_code[len] = 0;
            ht->max_code[len] = -1;
            ht->val_ptr[len] = sym_idx;
        } else {
            ht->val_ptr[len] = sym_idx;
            ht->min_code[len] = code;
            ht->max_code[len] = code + cnt - 1;
            code += cnt;
            sym_idx += cnt;
        }
        code <<= 1;
    }
    ht->carregada = 1;
    return 1;
}

static void fyd_bits_init(fyd_bits_t *b, const uint8_t *data, size_t size, size_t pos) {
    b->data = data;
    b->size = size;
    b->pos = pos;
    b->bit_buf = 0;
    b->bit_cnt = 0;
    b->eof_stream = 0;
}

static void fyd_bits_reset_ac(fyd_bits_t *b) {
    b->bit_buf = 0;
    b->bit_cnt = 0;
}

static int fyd_bits_preencher(fyd_bits_t *bits, int min_bits) {
    while (bits->bit_cnt < min_bits) {
        if (bits->pos >= bits->size) {
            bits->eof_stream = 1;
            /* Preenche zeros virtuais ao fim do buffer para nao travar */
            bits->bit_buf <<= (24 - bits->bit_cnt);
            bits->bit_cnt = 24;
            return 1;
        }
        uint8_t byte_val = bits->data[bits->pos++];
        if (byte_val == 0xFF) {
            if (bits->pos >= bits->size) {
                bits->eof_stream = 1;
                return 0;
            }
            uint8_t proximo_byte = bits->data[bits->pos++];
            if (proximo_byte == 0x00) {
                /* Byte stuffing valido: 0xFF real */
                byte_val = 0xFF;
            } else if (proximo_byte >= 0xD0 && proximo_byte <= 0xD7) {
                /* Marcador RST encontrado durante leitura */
                bits->pos -= 2;
                bits->eof_stream = 1;
                bits->bit_buf <<= (24 - bits->bit_cnt);
                bits->bit_cnt = 24;
                return 1;
            } else {
                /* Outro marcador JPEG (ex.: EOI 0xD9) */
                bits->pos -= 2;
                bits->eof_stream = 1;
                bits->bit_buf <<= (24 - bits->bit_cnt);
                bits->bit_cnt = 24;
                return 1;
            }
        }
        bits->bit_buf = (bits->bit_buf << 8) | (uint32_t)byte_val;
        bits->bit_cnt += 8;
    }
    return 1;
}

static int fyd_bits_ler(fyd_bits_t *b, int nbits, int *out_val) {
    if (nbits == 0) {
        *out_val = 0;
        return 1;
    }
    if (!fyd_bits_preencher(b, nbits)) return 0;
    int shift = b->bit_cnt - nbits;
    *out_val = (int)((b->bit_buf >> shift) & ((1u << nbits) - 1u));
    b->bit_cnt -= nbits;
    return 1;
}

static int fyd_bits_ler_1(fyd_bits_t *b, int *out_bit) {
    if (!fyd_bits_preencher(b, 1)) return 0;
    b->bit_cnt--;
    *out_bit = (int)((b->bit_buf >> b->bit_cnt) & 1u);
    return 1;
}

static int fyd_huff_decodificar_simbolo(fyd_bits_t *b, const fyd_huff_t *ht, int *out_sym) {
    if (!ht || !ht->carregada) return 0;
    int code = 0;
    for (int len = 1; len <= 16; len++) {
        int bit = 0;
        if (!fyd_bits_ler_1(b, &bit)) return 0;
        code = (code << 1) | bit;
        if (ht->max_code[len] >= 0 && code <= ht->max_code[len]) {
            int idx = ht->val_ptr[len] + (code - ht->min_code[len]);
            if (idx < 0 || idx >= 256) return 0;
            *out_sym = (int)ht->symbols[idx];
            return 1;
        }
    }
    return 0;
}

/* Estende o sinal de um valor de 's' bits conforme a especificacao JPEG */
static int32_t fyd_estender_sinal(int val, int s) {
    if (s <= 0) return 0;
    int vt = 1 << (s - 1);
    if (val < vt) {
        vt = (-1 << s) + 1;
        val += vt;
    }
    return (int32_t)val;
}

static int fyd_decodificar_bloco(fyd_bits_t *b,
                                 const fyd_huff_t *ht_dc,
                                 const fyd_huff_t *ht_ac,
                                 const uint16_t qt[64],
                                 int32_t *dc_prev,
                                 int32_t out_bloco[64]) {
    for (int i = 0; i < 64; i++) out_bloco[i] = 0;

    int s = 0;
    if (!fyd_huff_decodificar_simbolo(b, ht_dc, &s)) return 0;
    if (s > 15) return 0;

    int diff_bits = 0;
    if (!fyd_bits_ler(b, s, &diff_bits)) return 0;
    int32_t dc = *dc_prev + fyd_estender_sinal(diff_bits, s);
    *dc_prev = dc;
    out_bloco[0] = dc * (int32_t)qt[0];

    int k = 1;
    while (k < 64) {
        int rs = 0;
        if (!fyd_huff_decodificar_simbolo(b, ht_ac, &rs)) return 0;
        if (rs == 0x00) {
            /* EOB: restante do bloco e zero */
            break;
        }
        int run = (rs >> 4) & 0x0F;
        int size = rs & 0x0F;

        if (rs == 0xF0) {
            /* ZRL: 16 zeros */
            k += 16;
            continue;
        }

        k += run;
        if (k >= 64) break;
        if (size > 15) return 0;

        int ac_bits = 0;
        if (!fyd_bits_ler(b, size, &ac_bits)) return 0;
        int32_t ac_val = fyd_estender_sinal(ac_bits, size);
        out_bloco[FYD_ZIGZAG[k]] = ac_val * (int32_t)qt[k];
        k++;
    }
    return 1;
}

/* IDCT 8x8 em ponto fixo (escala 12 bits: 4096 = 1.0).
 * Baseado na transformada separavel em 1D nas linhas e colunas. */
static void fyd_idct_8x8(const int32_t in[64], int32_t out[64]) {
    /* Constantes em Q12:
     * c1 = cos(pi/16) * 4096 = 4017
     * c2 = cos(2*pi/16) * 4096 = 3784
     * c3 = cos(3*pi/16) * 4096 = 3406
     * c6 = cos(6*pi/16) * 4096 = 1567
     * s2 = sin(2*pi/16) * 4096 = 1567
     * s6 = sin(6*pi/16) * 4096 = 3784 */
    const int32_t C1 = 4017;
    const int32_t C2 = 3784;
    const int32_t C3 = 3406;
    const int32_t C6 = 1567;
    const int32_t S2 = 1567;
    const int32_t S6 = 3784;

    int32_t temp[64];

    /* 1D IDCT em cada linha */
    for (int r = 0; r < 8; r++) {
        int base = r * 8;
        int32_t x0 = in[base + 0] << 8;
        int32_t x1 = in[base + 4] << 8;
        int32_t x2 = in[base + 2] << 8;
        int32_t x3 = in[base + 6] << 8;
        int32_t x4 = in[base + 1] << 8;
        int32_t x5 = in[base + 7] << 8;
        int32_t x6 = in[base + 5] << 8;
        int32_t x7 = in[base + 3] << 8;

        /* Parte par */
        int32_t t0 = x0 + x1;
        int32_t t1 = x0 - x1;
        int32_t t2 = ((x2 * S6 - x3 * C6) >> 12);
        int32_t t3 = ((x2 * C6 + x3 * S6) >> 12);
        int32_t e0 = t0 + t3;
        int32_t e3 = t0 - t3;
        int32_t e1 = t1 + t2;
        int32_t e2 = t1 - t2;

        /* Parte impar */
        int32_t o0 = x4 + x7;
        int32_t o1 = x5 + x6;
        int32_t o2 = x5 - x6;
        int32_t o3 = x4 - x7;

        int32_t u0 = o0 + o1;
        int32_t u1 = o0 - o1;
        int32_t u2 = ((o2 * C2 + o3 * S2) >> 12);
        int32_t u3 = ((o3 * C2 - o2 * S2) >> 12);

        int32_t v0 = ((u1 * C1 + u2 * C3) >> 12);
        int32_t v1 = ((u2 * C1 - u1 * C3) >> 12);

        temp[base + 0] = e0 + u0;
        temp[base + 7] = e0 - u0;
        temp[base + 1] = e1 + v0;
        temp[base + 6] = e1 - v0;
        temp[base + 2] = e2 + v1;
        temp[base + 5] = e2 - v1;
        temp[base + 3] = e3 + u3;
        temp[base + 4] = e3 - u3;
    }

    /* 1D IDCT em cada coluna */
    for (int c = 0; c < 8; c++) {
        int32_t x0 = temp[0 * 8 + c];
        int32_t x1 = temp[4 * 8 + c];
        int32_t x2 = temp[2 * 8 + c];
        int32_t x3 = temp[6 * 8 + c];
        int32_t x4 = temp[1 * 8 + c];
        int32_t x5 = temp[7 * 8 + c];
        int32_t x6 = temp[5 * 8 + c];
        int32_t x7 = temp[3 * 8 + c];

        int32_t t0 = x0 + x1;
        int32_t t1 = x0 - x1;
        int32_t t2 = ((x2 * S6 - x3 * C6) >> 12);
        int32_t t3 = ((x2 * C6 + x3 * S6) >> 12);
        int32_t e0 = t0 + t3;
        int32_t e3 = t0 - t3;
        int32_t e1 = t1 + t2;
        int32_t e2 = t1 - t2;

        int32_t o0 = x4 + x7;
        int32_t o1 = x5 + x6;
        int32_t o2 = x5 - x6;
        int32_t o3 = x4 - x7;

        int32_t u0 = o0 + o1;
        int32_t u1 = o0 - o1;
        int32_t u2 = ((o2 * C2 + o3 * S2) >> 12);
        int32_t u3 = ((o3 * C2 - o2 * S2) >> 12);

        int32_t v0 = ((u1 * C1 + u2 * C3) >> 12);
        int32_t v1 = ((u2 * C1 - u1 * C3) >> 12);

        out[0 * 8 + c] = (e0 + u0 + 4096) >> 13;
        out[7 * 8 + c] = (e0 - u0 + 4096) >> 13;
        out[1 * 8 + c] = (e1 + v0 + 4096) >> 13;
        out[6 * 8 + c] = (e1 - v0 + 4096) >> 13;
        out[2 * 8 + c] = (e2 + v1 + 4096) >> 13;
        out[5 * 8 + c] = (e2 - v1 + 4096) >> 13;
        out[3 * 8 + c] = (e3 + u3 + 4096) >> 13;
        out[4 * 8 + c] = (e3 - u3 + 4096) >> 13;
    }
}

static int fyd_parse_dqt(fyd_jpg_ctx_t *ctx, const uint8_t *seg, size_t len) {
    size_t i = 0;
    while (i < len) {
        uint8_t pq_tq = seg[i++];
        uint8_t prec = (pq_tq >> 4) & 0x0F;
        uint8_t tq = pq_tq & 0x0F;
        if (tq >= FYD_JPG_MAX_QT || prec != 0) {
            /* Suporte completo implementado para precisao 8 bits (prec == 0) */
            return 0;
        }
        if (i + 64 > len) return 0;
        for (int k = 0; k < 64; k++) {
            ctx->qt[tq][k] = seg[i + k];
        }
        ctx->qt_ok[tq] = 1;
        i += 64;
    }
    return 1;
}

static int fyd_parse_dht(fyd_jpg_ctx_t *ctx, const uint8_t *seg, size_t len) {
    size_t i = 0;
    while (i < len) {
        if (i + 17 > len) return 0;
        uint8_t tc_th = seg[i++];
        uint8_t tc = (tc_th >> 4) & 0x0F; /* 0 = DC, 1 = AC */
        uint8_t th = tc_th & 0x0F;
        if (th >= FYD_JPG_MAX_HUFF || (tc != 0 && tc != 1)) return 0;

        fyd_huff_t *ht = (tc == 0) ? &ctx->huff_dc[th] : &ctx->huff_ac[th];
        ht->counts[0] = 0;
        int total = 0;
        for (int b = 1; b <= 16; b++) {
            ht->counts[b] = seg[i++];
            total += ht->counts[b];
        }
        if (total > 256 || i + (size_t)total > len) return 0;
        for (int s = 0; s < total; s++) {
            ht->symbols[s] = seg[i++];
        }
        if (!fyd_construir_huff(ht)) return 0;
    }
    return 1;
}

static int fyd_parse_sof0(fyd_jpg_ctx_t *ctx, const uint8_t *seg, size_t len) {
    if (len < 6) return 0;
    uint8_t prec = seg[0];
    if (prec != 8) return 0;

    int altura  = (int)(((uint16_t)seg[1] << 8) | seg[2]);
    int largura = (int)(((uint16_t)seg[3] << 8) | seg[4]);
    int nf      = (int)seg[5];

    if (largura <= 0 || altura <= 0) return 0;
    if (nf != 1 && nf != 3) return 0;
    if (len < (size_t)(6 + nf * 3)) return 0;

    ctx->largura = largura;
    ctx->altura = altura;
    ctx->num_comps = nf;

    for (int i = 0; i < nf; i++) {
        uint8_t id = seg[6 + i * 3 + 0];
        uint8_t hv = seg[6 + i * 3 + 1];
        uint8_t qt = seg[6 + i * 3 + 2];
        uint8_t h = (hv >> 4) & 0x0F;
        uint8_t v = hv & 0x0F;
        if (h == 0 || v == 0 || h > 2 || v > 2 || qt >= FYD_JPG_MAX_QT) return 0;

        ctx->comps[i].id = id;
        ctx->comps[i].h_samp = h;
        ctx->comps[i].v_samp = v;
        ctx->comps[i].qt_idx = qt;
        ctx->comps[i].dc_prev = 0;
    }
    return 1;
}

static int fyd_parse_sos(fyd_jpg_ctx_t *ctx, const uint8_t *seg, size_t len) {
    if (len < 1) return 0;
    int ns = (int)seg[0];
    if (ns != ctx->num_comps || len < (size_t)(1 + ns * 2 + 3)) return 0;

    for (int i = 0; i < ns; i++) {
        uint8_t cs = seg[1 + i * 2 + 0];
        uint8_t td_ta = seg[1 + i * 2 + 1];
        uint8_t td = (td_ta >> 4) & 0x0F;
        uint8_t ta = td_ta & 0x0F;
        if (td >= FYD_JPG_MAX_HUFF || ta >= FYD_JPG_MAX_HUFF) return 0;

        int achou = -1;
        for (int c = 0; c < ctx->num_comps; c++) {
            if (ctx->comps[c].id == cs) {
                achou = c;
                break;
            }
        }
        if (achou < 0) return 0;
        ctx->comps[achou].dc_idx = td;
        ctx->comps[achou].ac_idx = ta;
    }

    /* Ss, Se, Ah/Al: para baseline padrao devem ser 0, 63, 0 */
    uint8_t ss = seg[1 + ns * 2 + 0];
    uint8_t se = seg[1 + ns * 2 + 1];
    uint8_t ahal = seg[1 + ns * 2 + 2];
    if (ss != 0 || se != 63 || ahal != 0) return 0;

    return 1;
}

static void fyd_consumir_restart_se_houver(fyd_bits_t *b, fyd_jpg_ctx_t *ctx) {
    for (int c = 0; c < ctx->num_comps; c++) {
        ctx->comps[c].dc_prev = 0;
    }
    fyd_bits_reset_ac(b);

    /* Avanca ate proximo marcador 0xFF 0xDn se presente */
    while (b->pos + 1 < b->size) {
        if (b->data[b->pos] == 0xFF) {
            uint8_t m = b->data[b->pos + 1];
            if (m == 0x00) {
                b->pos += 2;
                continue;
            }
            if (m >= 0xD0 && m <= 0xD7) {
                b->pos += 2;
                b->eof_stream = 0;
                return;
            }
            break;
        }
        b->pos++;
    }
}

int fyd_mjpeg_decodificar(const uint8_t *dados, size_t tam, fyd_imagem_buf_t *saida) {
    if (!dados || tam < 4 || !saida || !saida->pixels) return 0;
    if (saida->largura <= 0 || saida->altura <= 0) return 0;

    int pitch = saida->pitch_pixels > 0 ? saida->pitch_pixels : saida->largura;
    if (pitch < saida->largura) return 0;

    fyd_jpg_ctx_t ctx;
    for (int i = 0; i < FYD_JPG_MAX_QT; i++) ctx.qt_ok[i] = 0;
    for (int i = 0; i < FYD_JPG_MAX_HUFF; i++) {
        ctx.huff_dc[i].carregada = 0;
        ctx.huff_ac[i].carregada = 0;
    }
    ctx.num_comps = 0;
    ctx.largura = 0;
    ctx.altura = 0;
    ctx.restart_interval = 0;

    size_t pos = 0;
    int tem_soi = 0;
    int tem_sof = 0;
    size_t inicio_scan = 0;

    while (pos + 1 < tam) {
        if (dados[pos] != 0xFF) {
            pos++;
            continue;
        }
        while (pos < tam && dados[pos] == 0xFF) pos++;
        if (pos >= tam) break;

        uint8_t marcador = dados[pos++];
        if (marcador == 0x00) continue;

        if (marcador == 0xD8) { /* SOI */
            tem_soi = 1;
            continue;
        }
        if (marcador == 0xD9) { /* EOI */
            break;
        }
        if (marcador >= 0xD0 && marcador <= 0xD7) { /* RSTn */
            continue;
        }

        if (pos + 1 >= tam) return 0;
        uint16_t seg_len = (uint16_t)(((uint16_t)dados[pos] << 8) | dados[pos + 1]);
        pos += 2;
        if (seg_len < 2 || pos + (size_t)seg_len - 2 > tam) return 0;

        const uint8_t *seg = dados + pos;
        size_t payload_len = (size_t)seg_len - 2;

        if (marcador == 0xDB) { /* DQT */
            if (!fyd_parse_dqt(&ctx, seg, payload_len)) return 0;
        } else if (marcador == 0xC4) { /* DHT */
            if (!fyd_parse_dht(&ctx, seg, payload_len)) return 0;
        } else if (marcador == 0xC0) { /* SOF0 */
            if (!fyd_parse_sof0(&ctx, seg, payload_len)) return 0;
            if (ctx.largura > saida->largura || ctx.altura > saida->altura) return 0;
            tem_sof = 1;
        } else if (marcador == 0xDD) { /* DRI */
            if (payload_len < 2) return 0;
            ctx.restart_interval = (uint16_t)(((uint16_t)seg[0] << 8) | seg[1]);
        } else if (marcador == 0xDA) { /* SOS */
            if (!tem_sof) return 0;
            if (!fyd_parse_sos(&ctx, seg, payload_len)) return 0;
            inicio_scan = pos + payload_len;
            break;
        }

        pos += payload_len;
    }

    if (!tem_soi || !tem_sof || inicio_scan == 0) return 0;

    /* Verifica tabelas usadas pelos componentes */
    for (int c = 0; c < ctx.num_comps; c++) {
        uint8_t qt_i = ctx.comps[c].qt_idx;
        uint8_t dc_i = ctx.comps[c].dc_idx;
        uint8_t ac_i = ctx.comps[c].ac_idx;
        if (!ctx.qt_ok[qt_i] || !ctx.huff_dc[dc_i].carregada || !ctx.huff_ac[ac_i].carregada) {
            return 0;
        }
    }

    int max_h = 1, max_v = 1;
    for (int c = 0; c < ctx.num_comps; c++) {
        if ((int)ctx.comps[c].h_samp > max_h) max_h = (int)ctx.comps[c].h_samp;
        if ((int)ctx.comps[c].v_samp > max_v) max_v = (int)ctx.comps[c].v_samp;
    }

    int mcu_w = max_h * 8;
    int mcu_h = max_v * 8;
    int mcus_x = (ctx.largura + mcu_w - 1) / mcu_w;
    int mcus_y = (ctx.altura + mcu_h - 1) / mcu_h;

    /* Buffers locais em pilha/quadro para ate 4 blocos por componente (ex.: 2x2) */
    int32_t blocos_y[4][64];
    int32_t blocos_cb[4][64];
    int32_t blocos_cr[4][64];
    int32_t idct_out[64];

    fyd_bits_t bits;
    fyd_bits_init(&bits, dados, tam, inicio_scan);

    uint16_t mcu_desde_rst = 0;

    for (int my = 0; my < mcus_y; my++) {
        for (int mx = 0; mx < mcus_x; mx++) {
            if (ctx.restart_interval > 0 && mcu_desde_rst == ctx.restart_interval) {
                fyd_consumir_restart_se_houver(&bits, &ctx);
                mcu_desde_rst = 0;
            }

            for (int c = 0; c < ctx.num_comps; c++) {
                int h = (int)ctx.comps[c].h_samp;
                int v = (int)ctx.comps[c].v_samp;
                const fyd_huff_t *ht_dc = &ctx.huff_dc[ctx.comps[c].dc_idx];
                const fyd_huff_t *ht_ac = &ctx.huff_ac[ctx.comps[c].ac_idx];
                const uint16_t *qt = ctx.qt[ctx.comps[c].qt_idx];

                for (int by = 0; by < v; by++) {
                    for (int bx = 0; bx < h; bx++) {
                        int32_t coeff[64];
                        if (!fyd_decodificar_bloco(&bits, ht_dc, ht_ac, qt,
                                                   &ctx.comps[c].dc_prev, coeff)) {
                            return 0;
                        }
                        fyd_idct_8x8(coeff, idct_out);

                        int b_idx = by * h + bx;
                        int32_t *dst_b = (c == 0) ? blocos_y[b_idx] :
                                         (c == 1) ? blocos_cb[b_idx] : blocos_cr[b_idx];
                        for (int k = 0; k < 64; k++) {
                            dst_b[k] = idct_out[k] + 128;
                        }
                    }
                }
            }

            mcu_desde_rst++;

            /* Escreve a MCU no buffer de pixels de saida */
            int base_px = mx * mcu_w;
            int base_py = my * mcu_h;

            for (int py = 0; py < mcu_h; py++) {
                int sy = base_py + py;
                if (sy >= ctx.altura) break;

                for (int px = 0; px < mcu_w; px++) {
                    int sx = base_px + px;
                    if (sx >= ctx.largura) break;

                    uint8_t r = 0, g = 0, b_val = 0;

                    if (ctx.num_comps == 1) {
                        int h0 = (int)ctx.comps[0].h_samp;
                        int bx = px / 8;
                        int by = py / 8;
                        int lx = px % 8;
                        int ly = py % 8;
                        uint8_t y = fyd_clamp_u8(blocos_y[by * h0 + bx][ly * 8 + lx]);
                        r = g = b_val = y;
                    } else {
                        int h0 = (int)ctx.comps[0].h_samp;
                        int bx0 = px / 8;
                        int by0 = py / 8;
                        int lx0 = px % 8;
                        int ly0 = py % 8;
                        int32_t y = blocos_y[by0 * h0 + bx0][ly0 * 8 + lx0];

                        int h1 = (int)ctx.comps[1].h_samp;
                        int cx1 = (px * h1) / max_h;
                        int cy1 = (py * (int)ctx.comps[1].v_samp) / max_v;
                        int32_t cb = blocos_cb[(cy1 / 8) * h1 + (cx1 / 8)][(cy1 % 8) * 8 + (cx1 % 8)] - 128;

                        int h2 = (int)ctx.comps[2].h_samp;
                        int cx2 = (px * h2) / max_h;
                        int cy2 = (py * (int)ctx.comps[2].v_samp) / max_v;
                        int32_t cr = blocos_cr[(cy2 / 8) * h2 + (cx2 / 8)][(cy2 % 8) * 8 + (cx2 % 8)] - 128;

                        /* Conversao YCbCr -> RGB em ponto fixo (escala 1024) */
                        int32_t r_i = y + ((1436 * cr) >> 10);
                        int32_t g_i = y - ((352 * cb + 731 * cr) >> 10);
                        int32_t b_i = y + ((1815 * cb) >> 10);

                        r = fyd_clamp_u8(r_i);
                        g = fyd_clamp_u8(g_i);
                        b_val = fyd_clamp_u8(b_i);
                    }

                    saida->pixels[sy * pitch + sx] =
                        0xFF000000u | ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b_val;
                }
            }
        }
    }

    saida->largura = ctx.largura;
    saida->altura = ctx.altura;
    return 1;
}
