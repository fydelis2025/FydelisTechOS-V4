// ==========================================
// FYDELIS TECH OS — Syscalls: Particionamento & Discos
// Compartilhado: kernel (Assembly) ↔ C puro ↔ GTK 4
// ==========================================
#ifndef PARTITION_SYSCALLS_H
#define PARTITION_SYSCALLS_H

#include <stdint.h>
#include <stddef.h>

#define DISCO_NOME_MAX  32
#define LETRA_UNIDADES  26

typedef struct {
    int      numero;
    char     letra[4];
    char     sistema_arquivos[16];
    uint64_t tamanho_total;
    uint64_t espaco_usado;
    uint64_t espaco_livre;
    int      e_sistema;
    int      e_montada;
    char     caminho_fisico[64];
} ParticaoInfo;

typedef struct {
    char     nome[32];
    char     modelo[32];
    uint64_t tamanho_total;
    uint64_t setores;
    int      tipo_tabela; // 0=MBR, 1=GPT
    int      quantidade_particoes;
    int      e_removivel;
} DiscoInfo;

// === DETECÇÃO E LEITURA ===
int      inicializar_disco(void);
uint64_t obter_tamanho_disco(void);
int      detectar_tabela(const char* disco);
int      listar_unidades(void);
int      listar_particoes(const char* disco, void* buffer, int max);

// === CRIAÇÃO/REMOÇÃO ===
int      criar_unidade(int indice_letra, uint64_t setores);
int      remover_unidade(int indice_letra);
int      criar_particao(const char* disco, int tipo, uint64_t lba_inicio, uint64_t setores);
int      remover_particao(const char* disco, int numero);

// === FORMATAÇÃO ===
int      formatar_unidade(int indice_letra, const char* sistema);
int      formatar_fat32(const char* dispositivo, uint64_t lba, uint64_t setores);
int      formatar_exfat(const char* dispositivo, uint64_t lba, uint64_t setores);

// === BAIXO NÍVEL ===
int      disco_ler_setor(const char* disco, uint64_t lba, void* buffer);
int      disco_escrever_setor(const char* disco, uint64_t lba, const void* buffer);

#endif // PARTITION_SYSCALLS_H
