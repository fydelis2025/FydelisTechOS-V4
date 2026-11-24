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

static int fyd_construir_huff(fyd_huff_t *ht) {
    int code = 0;
    int sym_idx = 0;
    int total = 0;

    for (int idx = 1; idx <= 16; idx++) {
        total += ht->counts[idx];
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

static void fyd_bits_init(fyd_bits_t *bits, const uint8_t *data, size_t size, size_t pos) {
    bits->data = data;
    bits->size = size;
    bits->pos = pos;
    bits->bit_buf = 0;
    bits->bit_cnt = 0;
    bits->eof_stream = 0;
}

static void fyd_bits_reset_ac(fyd_bits_t *bits) {
    bits->bit_buf = 0;
    bits->bit_cnt = 0;
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

static int fyd_bits_ler(fyd_bits_t *bits, int nbits, int *out_val) {
    if (nbits == 0) {
        *out_val = 0;
        return 1;
    }
    if (!fyd_bits_preencher(bits, nbits)) return 0;
    int shift = bits->bit_cnt - nbits;
    *out_val = (int)((bits->bit_buf >> shift) & ((1u << nbits) - 1u));
    bits->bit_cnt -= nbits;
    return 1;
}

static int fyd_bits_ler_1(fyd_bits_t *bits, int *out_bit) {
    if (!fyd_bits_preencher(bits, 1)) return 0;
    bits->bit_cnt--;
    *out_bit = (int)((bits->bit_buf >> bits->bit_cnt) & 1u);
    return 1;
}

static int fyd_huff_decodificar_simbolo(fyd_bits_t *bits, const fyd_huff_t *ht, int *out_sym) {
    if (!ht || !ht->carregada) return 0;
    int code = 0;
    for (int len = 1; len <= 16; len++) {
        int bit = 0;
        if (!fyd_bits_ler_1(bits, &bit)) return 0;
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

/* Estende o sinal de um valor de 'num_bits' bits conforme a especificacao JPEG */
static int32_t fyd_estender_sinal(int val, int num_bits) {
    if (num_bits <= 0) return 0;
    int vt = 1 << (num_bits - 1);
    if (val < vt) {
        vt = (-1 << num_bits) + 1;
        val += vt;
    }
    return (int32_t)val;
}

static int fyd_decodificar_bloco(fyd_bits_t *bits,
                                 const fyd_huff_t *ht_dc,
                                 const fyd_huff_t *ht_ac,
                                 const uint16_t qt[64],
                                 int32_t *dc_prev,
                                 int32_t out_bloco[64]) {
    for (int idx = 0; idx < 64; idx++) out_bloco[idx] = 0;

    int s_len = 0;
    if (!fyd_huff_decodificar_simbolo(bits, ht_dc, &s_len)) return 0;
    if (s_len > 15) return 0;

    int diff_bits = 0;
    if (!fyd_bits_ler(bits, s_len, &diff_bits)) return 0;
    int32_t dc_val = *dc_prev + fyd_estender_sinal(diff_bits, s_len);
    *dc_prev = dc_val;
    out_bloco[0] = dc_val * (int32_t)qt[0];

    int coeff_idx = 1;
    while (coeff_idx < 64) {
        int rs = 0;
        if (!fyd_huff_decodificar_simbolo(bits, ht_ac, &rs)) return 0;
        if (rs == 0x00) {
            /* EOB: restante do bloco e zero */
            break;
        }
        int run = (rs >> 4) & 0x0F;
        int size = rs & 0x0F;

        if (rs == 0xF0) {
            /* ZRL: 16 zeros */
            coeff_idx += 16;
            continue;
        }

        coeff_idx += run;
        if (coeff_idx >= 64) break;
        if (size > 15) return 0;

        int ac_bits = 0;
        if (!fyd_bits_ler(bits, size, &ac_bits)) return 0;
        int32_t ac_val = fyd_estender_sinal(ac_bits, size);
        out_bloco[FYD_ZIGZAG[coeff_idx]] = ac_val * (int32_t)qt[coeff_idx];
        coeff_idx++;
    }
    return 1;
}

/* IDCT 8x8 em ponto fixo (escala 12 bits: 4096 = 1.0).
 * Baseado na transformada separavel em 1D nas linhas e colunas. */
static void fyd_idct_8x8(const int32_t in[64], int32_t out[64]) {
    const int32_t C1 = 4017;
    const int32_t C2 = 3784;
    const int32_t C3 = 3406;
    const int32_t C6 = 1567;
    const int32_t S2 = 1567;
    const int32_t S6 = 3784;

    int32_t temp[64];

    for (int row = 0; row < 8; row++) {
        int base = row * 8;
        int32_t x0 = in[base + 0] << 8;
        int32_t x1 = in[base + 4] << 8;
        int32_t x2 = in[base + 2] << 8;
        int32_t x3 = in[base + 6] << 8;
        int32_t x4 = in[base + 1] << 8;
        int32_t x5 = in[base + 7] << 8;
        int32_t x6 = in[base + 5] << 8;
        int32_t x7 = in[base + 3] << 8;

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

        temp[base + 0] = e0 + u0;
        temp[base + 7] = e0 - u0;
        temp[base + 1] = e1 + v0;
        temp[base + 6] = e1 - v0;
        temp[base + 2] = e2 + v1;
        temp[base + 5] = e2 - v1;
        temp[base + 3] = e3 + u3;
        temp[base + 4] = e3 - u3;
    }

    for (int col = 0; col < 8; col++) {
        int32_t x0 = temp[0 * 8 + col];
        int32_t x1 = temp[4 * 8 + col];
        int32_t x2 = temp[2 * 8 + col];
        int32_t x3 = temp[6 * 8 + col];
        int32_t x4 = temp[1 * 8 + col];
        int32_t x5 = temp[7 * 8 + col];
        int32_t x6 = temp[5 * 8 + col];
        int32_t x7 = temp[3 * 8 + col];

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

        out[0 * 8 + col] = (e0 + u0 + 4096) >> 13;
        out[7 * 8 + col] = (e0 - u0 + 4096) >> 13;
        out[1 * 8 + col] = (e1 + v0 + 4096) >> 13;
        out[6 * 8 + col] = (e1 - v0 + 4096) >> 13;
        out[2 * 8 + col] = (e2 + v1 + 4096) >> 13;
        out[5 * 8 + col] = (e2 - v1 + 4096) >> 13;
        out[3 * 8 + col] = (e3 + u3 + 4096) >> 13;
        out[4 * 8 + col] = (e3 - u3 + 4096) >> 13;
    }
}

static int fyd_parse_dqt(fyd_jpg_ctx_t *ctx, const uint8_t *seg, size_t len) {
    size_t offset = 0;
    while (offset < len) {
        uint8_t pq_tq = seg[offset++];
        uint8_t prec = (pq_tq >> 4) & 0x0F;
        uint8_t tq = pq_tq & 0x0F;
        if (tq >= FYD_JPG_MAX_QT || prec != 0) {
            return 0;
        }
        if (offset + 64 > len) return 0;
        for (int coeff = 0; coeff < 64; coeff++) {
            ctx->qt[tq][coeff] = seg[offset + coeff];
        }
        ctx->qt_ok[tq] = 1;
        offset += 64;
    }
    return 1;
}

static int fyd_parse_dht(fyd_jpg_ctx_t *ctx, const uint8_t *seg, size_t len) {
    size_t offset = 0;
    while (offset < len) {
        if (offset + 17 > len) return 0;
        uint8_t tc_th = seg[offset++];
        uint8_t tc = (tc_th >> 4) & 0x0F;
        uint8_t th = tc_th & 0x0F;
        if (th >= FYD_JPG_MAX_HUFF || (tc != 0 && tc != 1)) return 0;

        fyd_huff_t *ht = (tc == 0) ? &ctx->huff_dc[th] : &ctx->huff_ac[th];
        ht->counts[0] = 0;
        int total = 0;
        for (int bit_len = 1; bit_len <= 16; bit_len++) {
            ht->counts[bit_len] = seg[offset++];
            total += ht->counts[bit_len];
        }
        if (total > 256 || offset + (size_t)total > len) return 0;
        for (int sym_i = 0; sym_i < total; sym_i++) {
            ht->symbols[sym_i] = seg[offset++];
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

    for (int comp_i = 0; comp_i < nf; comp_i++) {
        uint8_t id = seg[6 + comp_i * 3 + 0];
        uint8_t hv = seg[6 + comp_i * 3 + 1];
        uint8_t qt = seg[6 + comp_i * 3 + 2];
        uint8_t h_samp = (hv >> 4) & 0x0F;
        uint8_t v_samp = hv & 0x0F;
        if (h_samp == 0 || v_samp == 0 || h_samp > 2 || v_samp > 2 || qt >= FYD_JPG_MAX_QT) return 0;

        ctx->comps[comp_i].id = id;
        ctx->comps[comp_i].h_samp = h_samp;
        ctx->comps[comp_i].v_samp = v_samp;
        ctx->comps[comp_i].qt_idx = qt;
        ctx->comps[comp_i].dc_prev = 0;
    }
    return 1;
}

static int fyd_parse_sos(fyd_jpg_ctx_t *ctx, const uint8_t *seg, size_t len) {
    if (len < 1) return 0;
    int ns = (int)seg[0];
    if (ns != ctx->num_comps || len < (size_t)(1 + ns * 2 + 3)) return 0;

    for (int comp_i = 0; comp_i < ns; comp_i++) {
        uint8_t cs = seg[1 + comp_i * 2 + 0];
        uint8_t td_ta = seg[1 + comp_i * 2 + 1];
        uint8_t td = (td_ta >> 4) & 0x0F;
        uint8_t ta = td_ta & 0x0F;
        if (td >= FYD_JPG_MAX_HUFF || ta >= FYD_JPG_MAX_HUFF) return 0;

        int achou = -1;
        for (int scan_c = 0; scan_c < ctx->num_comps; scan_c++) {
            if (ctx->comps[scan_c].id == cs) {
                achou = scan_c;
                break;
            }
        }
        if (achou < 0) return 0;
        ctx->comps[achou].dc_idx = td;
        ctx->comps[achou].ac_idx = ta;
    }

    uint8_t ss = seg[1 + ns * 2 + 0];
    uint8_t se = seg[1 + ns * 2 + 1];
    uint8_t ahal = seg[1 + ns * 2 + 2];
    if (ss != 0 || se != 63 || ahal != 0) return 0;

    return 1;
}

static void fyd_consumir_restart_se_houver(fyd_bits_t *bits, fyd_jpg_ctx_t *ctx) {
    for (int comp_i = 0; comp_i < ctx->num_comps; comp_i++) {
        ctx->comps[comp_i].dc_prev = 0;
    }
    fyd_bits_reset_ac(bits);

    while (bits->pos + 1 < bits->size) {
        if (bits->data[bits->pos] == 0xFF) {
            uint8_t marcador = bits->data[bits->pos + 1];
            if (marcador == 0x00) {
                bits->pos += 2;
                continue;
            }
            if (marcador >= 0xD0 && marcador <= 0xD7) {
                bits->pos += 2;
                bits->eof_stream = 0;
                return;
            }
            break;
        }
        bits->pos++;
    }
}

int fyd_mjpeg_decodificar(const uint8_t *dados, size_t tam, fyd_imagem_buf_t *saida) {
    if (!dados || tam < 4 || !saida || !saida->pixels) return 0;
    if (saida->largura <= 0 || saida->altura <= 0) return 0;

    int pitch = saida->pitch_pixels > 0 ? saida->pitch_pixels : saida->largura;
    if (pitch < saida->largura) return 0;

    fyd_jpg_ctx_t ctx;
    for (int qt_i = 0; qt_i < FYD_JPG_MAX_QT; qt_i++) ctx.qt_ok[qt_i] = 0;
    for (int hf_i = 0; hf_i < FYD_JPG_MAX_HUFF; hf_i++) {
        ctx.huff_dc[hf_i].carregada = 0;
        ctx.huff_ac[hf_i].carregada = 0;
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

        if (marcador == 0xD8) {
            tem_soi = 1;
            continue;
        }
        if (marcador == 0xD9) {
            break;
        }
        if (marcador >= 0xD0 && marcador <= 0xD7) {
            continue;
        }

        if (pos + 1 >= tam) return 0;
        uint16_t seg_len = (uint16_t)(((uint16_t)dados[pos] << 8) | dados[pos + 1]);
        pos += 2;
        if (seg_len < 2 || pos + (size_t)seg_len - 2 > tam) return 0;

        const uint8_t *seg = dados + pos;
        size_t payload_len = (size_t)seg_len - 2;

        if (marcador == 0xDB) {
            if (!fyd_parse_dqt(&ctx, seg, payload_len)) return 0;
        } else if (marcador == 0xC4) {
            if (!fyd_parse_dht(&ctx, seg, payload_len)) return 0;
        } else if (marcador == 0xC0) {
            if (!fyd_parse_sof0(&ctx, seg, payload_len)) return 0;
            if (ctx.largura > saida->largura || ctx.altura > saida->altura) return 0;
            tem_sof = 1;
        } else if (marcador == 0xDD) {
            if (payload_len < 2) return 0;
            ctx.restart_interval = (uint16_t)(((uint16_t)seg[0] << 8) | seg[1]);
        } else if (marcador == 0xDA) {
            if (!tem_sof) return 0;
            if (!fyd_parse_sos(&ctx, seg, payload_len)) return 0;
            inicio_scan = pos + payload_len;
            break;
        }

        pos += payload_len;
    }

    if (!tem_soi || !tem_sof || inicio_scan == 0) return 0;

    for (int comp_i = 0; comp_i < ctx.num_comps; comp_i++) {
        uint8_t qt_i = ctx.comps[comp_i].qt_idx;
        uint8_t dc_i = ctx.comps[comp_i].dc_idx;
        uint8_t ac_i = ctx.comps[comp_i].ac_idx;
        if (!ctx.qt_ok[qt_i] || !ctx.huff_dc[dc_i].carregada || !ctx.huff_ac[ac_i].carregada) {
            return 0;
        }
    }

    int max_h = 1, max_v = 1;
    for (int comp_i = 0; comp_i < ctx.num_comps; comp_i++) {
        if ((int)ctx.comps[comp_i].h_samp > max_h) max_h = (int)ctx.comps[comp_i].h_samp;
        if ((int)ctx.comps[comp_i].v_samp > max_v) max_v = (int)ctx.comps[comp_i].v_samp;
    }

    int mcu_w = max_h * 8;
    int mcu_h = max_v * 8;
    int mcus_x = (ctx.largura + mcu_w - 1) / mcu_w;
    int mcus_y = (ctx.altura + mcu_h - 1) / mcu_h;

    int32_t blocos_y[4][64];
    int32_t blocos_cb[4][64];
    int32_t blocos_cr[4][64];
    int32_t idct_out[64];

    fyd_bits_t bits;
    fyd_bits_init(&bits, dados, tam, inicio_scan);

    uint16_t mcu_desde_rst = 0;

    for (int mcu_y = 0; mcu_y < mcus_y; mcu_y++) {
        for (int mcu_x = 0; mcu_x < mcus_x; mcu_x++) {
            if (ctx.restart_interval > 0 && mcu_desde_rst == ctx.restart_interval) {
                fyd_consumir_restart_se_houver(&bits, &ctx);
                mcu_desde_rst = 0;
            }

            for (int comp_i = 0; comp_i < ctx.num_comps; comp_i++) {
                int h_samp = (int)ctx.comps[comp_i].h_samp;
                int v_samp = (int)ctx.comps[comp_i].v_samp;
                const fyd_huff_t *ht_dc = &ctx.huff_dc[ctx.comps[comp_i].dc_idx];
                const fyd_huff_t *ht_ac = &ctx.huff_ac[ctx.comps[comp_i].ac_idx];
                const uint16_t *qt = ctx.qt[ctx.comps[comp_i].qt_idx];

                for (int by_i = 0; by_i < v_samp; by_i++) {
                    for (int bx_i = 0; bx_i < h_samp; bx_i++) {
                        int32_t coeff[64];
                        if (!fyd_decodificar_bloco(&bits, ht_dc, ht_ac, qt,
                                                   &ctx.comps[comp_i].dc_prev, coeff)) {
                            return 0;
                        }
                        fyd_idct_8x8(coeff, idct_out);

                        int b_idx = by_i * h_samp + bx_i;
                        int32_t *dst_b = (comp_i == 0) ? blocos_y[b_idx] :
                                         (comp_i == 1) ? blocos_cb[b_idx] : blocos_cr[b_idx];
                        for (int sample_i = 0; sample_i < 64; sample_i++) {
                            dst_b[sample_i] = idct_out[sample_i] + 128;
                        }
                    }
                }
            }

            mcu_desde_rst++;

            int base_px = mcu_x * mcu_w;
            int base_py = mcu_y * mcu_h;

            for (int py = 0; py < mcu_h; py++) {
                int sy = base_py + py;
                if (sy >= ctx.altura) break;

                for (int px = 0; px < mcu_w; px++) {
                    int sx = base_px + px;
                    if (sx >= ctx.largura) break;

                    uint8_t red = 0, green = 0, blue = 0;

                    if (ctx.num_comps == 1) {
                        int h0 = (int)ctx.comps[0].h_samp;
                        int bx0 = px / 8;
                        int by0 = py / 8;
                        int lx0 = px % 8;
                        int ly0 = py % 8;
                        uint8_t luma = fyd_clamp_u8(blocos_y[by0 * h0 + bx0][ly0 * 8 + lx0]);
                        red = green = blue = luma;
                    } else {
                        int h0 = (int)ctx.comps[0].h_samp;
                        int bx0 = px / 8;
                        int by0 = py / 8;
                        int lx0 = px % 8;
                        int ly0 = py % 8;
                        int32_t luma = blocos_y[by0 * h0 + bx0][ly0 * 8 + lx0];

                        int h1 = (int)ctx.comps[1].h_samp;
                        int cx1 = (px * h1) / max_h;
                        int cy1 = (py * (int)ctx.comps[1].v_samp) / max_v;
                        int32_t cb_val = blocos_cb[(cy1 / 8) * h1 + (cx1 / 8)][(cy1 % 8) * 8 + (cx1 % 8)] - 128;

                        int h2 = (int)ctx.comps[2].h_samp;
                        int cx2 = (px * h2) / max_h;
                        int cy2 = (py * (int)ctx.comps[2].v_samp) / max_v;
                        int32_t cr_val = blocos_cr[(cy2 / 8) * h2 + (cx2 / 8)][(cy2 % 8) * 8 + (cx2 % 8)] - 128;

                        int32_t r_i = luma + ((1436 * cr_val) >> 10);
                        int32_t g_i = luma - ((352 * cb_val + 731 * cr_val) >> 10);
                        int32_t b_i = luma + ((1815 * cb_val) >> 10);

                        red = fyd_clamp_u8(r_i);
                        green = fyd_clamp_u8(g_i);
                        blue = fyd_clamp_u8(b_i);
                    }

                    saida->pixels[sy * pitch + sx] =
                        0xFF000000u | ((uint32_t)red << 16) | ((uint32_t)green << 8) | (uint32_t)blue;
                }
            }
        }
    }

    saida->largura = ctx.largura;
    saida->altura = ctx.altura;
    return 1;
}
