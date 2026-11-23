#ifndef FYD_FORMATOS_H
#define FYD_FORMATOS_H

#include <stdint.h>

/* =========================================================================
 * 1. FORMATO .fyd — Executável Nativo FydelisTech OS (64-bit)
 * ========================================================================= */
#define FYD_EXEC_MAGIC 0x31445946U /* "FYD1" em little-endian */

typedef struct __attribute__((packed)) {
    uint32_t magic;          /* Deve ser FYD_EXEC_MAGIC ("FYD1") */
    uint16_t versao_so;      /* Ex: 0x0402 para v4.2 */
    uint16_t tipo_app;       /* 0 = CLI (FydelTerm), 1 = GUI (Desktop) */
    uint64_t entry_offset;   /* Offset do ponto de entrada relativo ao início do código */
    uint64_t tamanho_codigo; /* Tamanho em bytes da seção de código (.text + .rodata) */
    uint64_t tamanho_bss;    /* Memória extra a zerar para variáveis não inicializadas */
    uint32_t checksum_crc32; /* Verificação de integridade do binário */
    char     nome[32];       /* Nome interno do aplicativo */
} FydExecHeader;

/* =========================================================================
 * 2. FORMATO .fpkg — Pacote de Instalação / Atualização (fydpkg)
 * ========================================================================= */
#define FYD_PKG_MAGIC  0x474B5046U /* "FPKG" em little-endian */

typedef struct __attribute__((packed)) {
    uint32_t magic;          /* Deve ser FYD_PKG_MAGIC ("FPKG") */
    uint16_t versao_pkg;     /* Versão do pacote (ex: 100 = v1.0.0) */
    uint16_t qtd_arquivos;   /* Quantidade de arquivos embutidos no pacote */
    uint32_t tamanho_total;  /* Tamanho total do payload após este cabeçalho */
    char     pacote_id[32];  /* Ex: "calc-nativa", "kernel-update" */
    char     categoria[16];  /* Ex: "acessorios", "sistema", "rede" */
} FydPkgHeader;

typedef struct __attribute__((packed)) {
    char     destino[64];    /* Caminho completo de destino (ex: "/fyd/apps/calc.fyd") */
    uint32_t tamanho;        /* Tamanho em bytes deste arquivo */
    uint32_t permissoes;     /* 0x01 = leitura, 0x02 = escrita, 0x04 = execução */
} FydPkgEntry;

/* =========================================================================
 * 3. FORMATO .fcfg — Configuração Nativa em /fyd/config (Chave=Valor)
 * ========================================================================= */
#define FYD_CFG_HEADER "#!FYDCFG v1"

/* Protótipos das funções do kernel (kernel/fyd_formatos.c) */
int fyd_validar_executavel(const void *buffer, uint64_t tamanho_buf, FydExecHeader *out_hdr);
int fyd_executar_binario(const void *buffer, uint64_t tamanho_buf);
int fyd_instalar_pacote(const void *buffer, uint64_t tamanho_buf);
int fyd_cfg_ler_chave(const char *conteudo_cfg, const char *chave, char *valor_out, int max_len);

#endif
