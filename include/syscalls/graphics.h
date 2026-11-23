// ==========================================
// FYDELIS TECH OS — Gráficos & Framebuffer
// Compartilhado: kernel (Assembly) ↔ C puro ↔ GTK 4
// ==========================================
#ifndef GRAPHICS_H
#define GRAPHICS_H

#include <stdint.h>

typedef struct {
    int      largura;
    int      altura;
    int      bits_por_pixel;
    int      pitch;
    uint64_t endereco_framebuffer;
    uint64_t tamanho_framebuffer;
    int      e_linear;
    int      vesa_versao;
} ModoVideo;

// === INICIALIZAÇÃO ===
int  vesa_detectar(void);
int  vesa_inicializar(int largura, int altura, int bpp);
int  gop_inicializar(void); // UEFI GOP
int  framebuffer_mapear(void);

// === DESENHO ===
void desenhar_pixel(int x, int y, uint32_t cor);
void preencher_retangulo(int x, int y, int w, int h, uint32_t cor);
void desenhar_texto(int x, int y, const char* texto, uint32_t cor_texto, uint32_t cor_fundo);
void copiar_area(int dx, int dy, int sx, int sy, int w, int h);

// === CURSOR & RESOLUÇÃO ===
void definir_cursor(int x, int y);
void definir_tamanho_cursor(int largura, int altura);
void atualizar_resolucao(int nova_largura, int nova_altura);

// === INFORMAÇÃO ===
ModoVideo* obter_modo_atual(void);
int  obter_resolucao_nativa(int* largura, int* altura);

#endif // GRAPHICS_H
