#ifndef GPU_H
#define GPU_H

#include <stdint.h>

// Cores no formato 0xAARRGGBB
#define COR_ROXO_ESCURO  0xFF1F050F
#define COR_ROXO_NEON    0xFFDD4E9D
#define COR_CIANO_NEON   0xFF00FFFF
#define COR_BRANCO       0xFFFFFFFF
#define COR_CINZA        0xFF444444

// Inicialização
int  gpu_inicializar(void);

// Desenho
void gpu_preencher_retangulo(int x1, int y1, int x2, int y2, uint32_t cor);

// Utilitários
static inline void gpu_preencher_tela(uint32_t cor, int larg, int alt) {
    gpu_preencher_retangulo(0, 0, larg, alt, cor);
}

#endif
