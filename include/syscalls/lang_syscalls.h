// ==========================================
// FYDELIS TECH OS — Syscalls: Gerenciamento de Idioma
// Compartilhado: kernel (Assembly) ↔ C puro ↔ GTK 4
// ==========================================
#ifndef LANG_SYSCALLS_H
#define LANG_SYSCALLS_H

#include <stdint.h>
#include <stdbool.h>

// ==========================================
// 🏷️ IDENTIFICADORES DE IDIOMA
// ==========================================
#define LANG_PT_BR      0
#define LANG_EN_US      1
#define LANG_PADRAO     LANG_PT_BR

// ==========================================
// 📦 ESTRUTURA DO PACOTE DE TRADUÇÃO
// ==========================================
typedef struct {
    const char* id;
    const char* nome_exibicao;
    const char* codigo_teclado; // "ptbr" / "us"
    // Barra superior
    const char* titulo_sistema;
    const char* usuario;
    // Barra inferior
    const char* sistema_pronto;
    const char* conectado;
    const char* offline;
    const char* teclado;
    const char* mouse_ativo;
    // Painéis
    const char* painel_sistema;
    const char* painel_rede;
    const char* painel_bt;
    const char* painel_disco;
    const char* fydelis_os;
    const char* kernel_info;
    const char* discos_detectados;
    const char* usb_disponivel;
    const char* usb_indisponivel;
    const char* seguranca_ativa;
    const char* integridade_ok;
    const char* integridade_aviso;
    const char* ip;
    const char* redes_wifi;
    const char* disp_bt;
    const char* unidades_montadas;
    const char* verificar_integridade;
    // Botões
    const char* bloquear;
    const char* configuracoes;
    const char* maquinas_virtuais;
    const char* sair;
    const char* fechar;
    const char* minimizar;
    const char* maximizar;
    // Avisos
    const char* ajuda_f1;
    const char* salvar_f10;
    const char* fechar_esc;
    const char* encerrando;
} PacoteIdioma;

// ==========================================
// 🔌 SYSCALLS — GERENCIAMENTO DE IDIOMA
// ==========================================

/**
 * @brief Define idioma ativo e sincroniza layout do teclado
 * @param lang_id LANG_PT_BR ou LANG_EN_US
 */
void lang_definir(uint8_t lang_id);

/**
 * @brief Retorna ponteiro para o pacote de tradução atual
 */
const PacoteIdioma* lang_atual(void);

/**
 * @brief Retorna ID do idioma ativo
 */
uint8_t lang_id_atual(void);

/**
 * @brief Lista idiomas disponíveis
 * @param contador Quantidade retornada por referência
 * @return Vetor de IDs
 */
const uint8_t* lang_listar_disponiveis(uint8_t* contador);

/**
 * @brief Nome amigável do idioma
 */
const char* lang_nome(uint8_t lang_id);

/**
 * @brief Sincroniza layout do teclado com idioma atual
 * Chamado internamente por lang_definir()
 */
void lang_sincronizar_teclado(void);

#endif // LANG_SYSCALLS_H
