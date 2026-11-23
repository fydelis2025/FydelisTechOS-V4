// ==========================================
// FYDELIS TECH OS — Syscalls: Mouse & PS/2
// Compartilhado: kernel (Assembly) ↔ C puro ↔ GTK 4
// ==========================================
#ifndef MOUSE_SYSCALLS_H
#define MOUSE_SYSCALLS_H

#include <stdint.h>
#include <stdbool.h>

// === BOTÕES — máscara de bits ===
#define MOUSE_BOTAO_ESQ    0x01
#define MOUSE_BOTAO_DIR    0x02
#define MOUSE_BOTAO_MEIO   0x04

// === LIMITES DE TELA (definidos no driver) ===
#define MOUSE_MIN_X        0
#define MOUSE_MIN_Y        0
#define MOUSE_MAX_TEXTO_X  79
#define MOUSE_MAX_TEXTO_Y  24

// === ESTRUTURA DE ESTADO ===
typedef struct {
    int32_t x;
    int32_t y;
    uint32_t botoes; // bitmask MOUSE_BOTAO_*
    int8_t  roda;    // +1 cima / -1 baixo
    bool    presente;
} MouseEstado;

// === SYSCALLS (exportadas do mouse.asm) ===

/**
 * @brief Tenta detectar o mouse PS/2
 * @return 1 = encontrado, 0 = não respondeu
 */
int mouse_detectar(void);

/**
 * @brief Inicializa mouse — habilita transmissão e posiciona no centro
 * @return 1 = sucesso, 0 = falha
 */
int mouse_inicializar(void);

/**
 * @brief Obtém posição atual
 * @param x Ponteiro para receber coordenada horizontal
 * @param y Ponteiro para receber coordenada vertical
 */
void mouse_ler_posicao(int32_t* x, int32_t* y);

/**
 * @brief Lê estado dos botões
 * @return Máscara com MOUSE_BOTAO_*
 */
uint32_t mouse_ler_botoes(void);

/**
 * @brief Define posição manualmente (com limites automáticos)
 */
void mouse_definir_posicao(int32_t x, int32_t y);

/**
 * @brief Manipulador de interrupção — chamado internamente pelo kernel
 * Atualiza posição e botões a cada pacote do controlador
 */
void mouse_tratar_irq(void);

// === PONTE / UTILITÁRIAS ===

/**
 * @brief Lê estado completo de uma vez
 */
void mouse_estado_completo(MouseEstado* out);

/**
 * @brief Converte posição do modo texto (0-79, 0-24) para gráfico (pixels)
 */
void mouse_para_pixels(const MouseEstado* texto, int32_t* px, int32_t* py,
                       int32_t largura_tela, int32_t altura_tela);

/**
 * @brief Verifica se botão específico está pressionado
 */
static inline bool mouse_apertou(uint32_t botoes, uint32_t mascara) {
    return (botoes & mascara) != 0;
}

#endif // MOUSE_SYSCALLS_H
