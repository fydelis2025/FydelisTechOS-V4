#include <stdint.h>
#include <stddef.h>
#include "fyd_mjpeg.h"

/* Limite estatico sem malloc para evitar estourar pilha de kernel */
#define FYD_MAX_QUADRO_W 640
#define FYD_MAX_QUADRO_H 480

extern uint32_t fb_largura;
extern uint32_t fb_altura;
extern uint32_t *fb_ptr;       /* ou substitua pelo ponteiro real do seu framebuffer */
extern uint32_t fb_pitch_px;   /* largura da linha em pixels (se nao existir, use fb_largura) */

static uint32_t g_mjpeg_pixels[FYD_MAX_QUADRO_W * FYD_MAX_QUADRO_H];

int fyd_desenhar_quadro_mjpeg(const uint8_t *jpg_dados, size_t jpg_tam,
                              int dst_x, int dst_y) {
    if (!jpg_dados || jpg_tam < 4) return 0;

    uint32_t tela_w = fb_largura ? fb_largura : 1024u;
    uint32_t tela_h = fb_altura  ? fb_altura  : 768u;
    uint32_t pitch  = fb_pitch_px ? fb_pitch_px : tela_w;

    if (!fb_ptr) return 0;

    fyd_imagem_buf_t img;
    img.pixels       = g_mjpeg_pixels;
    img.largura      = FYD_MAX_QUADRO_W;
    img.altura       = FYD_MAX_QUADRO_H;
    img.pitch_pixels = FYD_MAX_QUADRO_W;

    if (!fyd_mjpeg_decodificar(jpg_dados, jpg_tam, &img)) {
        return 0;
    }

    for (int y = 0; y < img.altura; y++) {
        int ty = dst_y + y;
        if (ty < 0) continue;
        if ((uint32_t)ty >= tela_h) break;

        for (int x = 0; x < img.largura; x++) {
            int tx = dst_x + x;
            if (tx < 0) continue;
            if ((uint32_t)tx >= tela_w) break;

            uint32_t cor = img.pixels[y * img.pitch_pixels + x];
            fb_ptr[(uint32_t)ty * pitch + (uint32_t)tx] = cor;
        }
    }

    return 1;
}