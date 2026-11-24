#include "../include/fyd_formatos.h"
#include "../include/fydlog.h"

/* =========================================================================
 * ARENA DE EXECUÇÃO E REGISTRO DE ARQUIVOS INSTALADOS (Autônomo no Kernel)
 * ========================================================================= */
#define FYD_MAX_EXEC_MEM    (512 * 1024) /* 512 KiB reservados para rodar apps .fyd */
#define FYD_MAX_PKG_ARQS    32
#define FYD_MAX_PKG_STORAGE (256 * 1024) /* 256 KiB para arquivos extraídos de .fpkg */

static uint8_t fyd_exec_arena[FYD_MAX_EXEC_MEM] __attribute__((aligned(16)));

typedef struct {
    char     caminho[64];
    uint32_t tamanho;
    uint32_t offset_dados;
    int      ativo;
} FydArqInstalado;

static FydArqInstalado fyd_tabela_arqs[FYD_MAX_PKG_ARQS];
static uint8_t         fyd_storage_arqs[FYD_MAX_PKG_STORAGE];
static uint32_t        fyd_storage_usado = 0;

static void fyd_memcpy(void *dst, const void *src, uint64_t n) {
    uint8_t *d = (uint8_t *)dst;
    const uint8_t *s = (const uint8_t *)src;
    for (uint64_t i = 0; i < n; i++) d[i] = s[i];
}

static void fyd_memset(void *dst, uint8_t val, uint64_t n) {
    uint8_t *d = (uint8_t *)dst;
    for (uint64_t i = 0; i < n; i++) d[i] = val;
}

static int fyd_strncmp(const char *a, const char *b, int n) {
    for (int i = 0; i < n; i++) {
        if (a[i] != b[i]) return (unsigned char)a[i] - (unsigned char)b[i];
        if (a[i] == '\0') return 0;
    }
    return 0;
}

static int fyd_strlen(const char *s) {
    int len = 0;
    while (s[len]) len++;
    return len;
}

static void fyd_strcpy_lim(char *dst, const char *src, int max_len) {
    int i = 0;
    if (!dst || !src || max_len <= 0) {
        if (dst && max_len > 0) {
            dst[0] = '\0';
        }
        return;
    }

    while (i < max_len - 1 && src[i]) {
        dst[i] = src[i];
        i++;
    }
    dst[i] = '\0';
}

/* Grava um arquivo extraído de .fpkg na tabela interna do kernel */
static int fyd_registrar_arquivo_extraido(const char *caminho, const void *dados, uint32_t tamanho) {
    if (fyd_storage_usado + tamanho > FYD_MAX_PKG_STORAGE) {
        fydlog_escrever(LOG_ERRO, "fpkg: storage interno de 256KB lotado");
        return -1;
    }

    int slot = -1;
    for (int i = 0; i < FYD_MAX_PKG_ARQS; i++) {
        if (fyd_tabela_arqs[i].ativo &&
            fyd_strncmp(fyd_tabela_arqs[i].caminho, caminho, 64) == 0) {
            slot = i; /* Atualiza arquivo já existente */
            break;
        }
        if (!fyd_tabela_arqs[i].ativo && slot == -1) {
            slot = i;
        }
    }

    if (slot == -1) {
        fydlog_escrever(LOG_ERRO, "fpkg: limite maximo de 32 arquivos atingido");
        return -2;
    }

    fyd_strcpy_lim(fyd_tabela_arqs[slot].caminho, caminho, 64);
    fyd_tabela_arqs[slot].tamanho      = tamanho;
    fyd_tabela_arqs[slot].offset_dados = fyd_storage_usado;
    fyd_tabela_arqs[slot].ativo        = 1;

    fyd_memcpy(&fyd_storage_arqs[fyd_storage_usado], dados, tamanho);
    fyd_storage_usado += tamanho;
    return 0;
}

/* =========================================================================
 * 1. CARREGADOR DE EXECUTÁVEIS (.fyd)
 * ========================================================================= */
int fyd_validar_executavel(const void *buffer, uint64_t tamanho_buf, FydExecHeader *out_hdr) {
    if (!buffer || tamanho_buf < sizeof(FydExecHeader)) {
        fydlog_escrever(LOG_ERRO, "fyd: buffer nulo ou menor que FydExecHeader");
        return -1;
    }

    const FydExecHeader *hdr = (const FydExecHeader *)buffer;
    if (hdr->magic != FYD_EXEC_MAGIC) {
        fydlog_escrever(LOG_ERRO, "fyd: assinatura magica invalida (esperado FYD1)");
        return -2;
    }
    if (sizeof(FydExecHeader) + hdr->tamanho_codigo > tamanho_buf) {
        fydlog_escrever(LOG_ERRO, "fyd: arquivo executavel truncado ou corrompido");
        return -3;
    }
    if (hdr->entry_offset >= hdr->tamanho_codigo) {
        fydlog_escrever(LOG_ERRO, "fyd: entry_offset fora da secao de codigo");
        return -4;
    }

    if (out_hdr) {
        fyd_memcpy(out_hdr, hdr, sizeof(FydExecHeader));
    }
    return 0;
}

int fyd_executar_binario(const void *buffer, uint64_t tamanho_buf) {
    FydExecHeader hdr;
    int err = fyd_validar_executavel(buffer, tamanho_buf, &hdr);
    if (err != 0) return err;

    uint64_t mem_necessaria = hdr.tamanho_codigo + hdr.tamanho_bss;
    if (mem_necessaria > FYD_MAX_EXEC_MEM) {
        fydlog_escrever(LOG_ERRO, "fyd: binario excede arena de execucao de 512KB");
        return -5;
    }

    const uint8_t *codigo_src = ((const uint8_t *)buffer) + sizeof(FydExecHeader);
    fyd_memcpy(fyd_exec_arena, codigo_src, hdr.tamanho_codigo);

    if (hdr.tamanho_bss > 0) {
        fyd_memset(fyd_exec_arena + hdr.tamanho_codigo, 0, hdr.tamanho_bss);
    }

    fydlog_escrever(LOG_INFO, "fyd: executando binario nativo em Long Mode");

    typedef int (*FydEntryFunc)(void);
    FydEntryFunc entry = (FydEntryFunc)(fyd_exec_arena + hdr.entry_offset);
    return entry();
}

/* =========================================================================
 * 2. INSTALADOR DE PACOTES (.fpkg)
 * ========================================================================= */
int fyd_instalar_pacote(const void *buffer, uint64_t tamanho_buf) {
    if (!buffer || tamanho_buf < sizeof(FydPkgHeader)) {
        fydlog_escrever(LOG_ERRO, "fpkg: cabecalho de pacote invalido ou vazio");
        return -1;
    }

    const FydPkgHeader *pkg = (const FydPkgHeader *)buffer;
    if (pkg->magic != FYD_PKG_MAGIC) {
        fydlog_escrever(LOG_ERRO, "fpkg: assinatura magica invalida (esperado FPKG)");
        return -2;
    }

    uint64_t offset = sizeof(FydPkgHeader);
    const uint8_t *base = (const uint8_t *)buffer;

    for (uint16_t i = 0; i < pkg->qtd_arquivos; i++) {
        if (offset + sizeof(FydPkgEntry) > tamanho_buf) {
            fydlog_escrever(LOG_ERRO, "fpkg: entrada de arquivo truncada no pacote");
            return -3;
        }

        const FydPkgEntry *ent = (const FydPkgEntry *)(base + offset);
        offset += sizeof(FydPkgEntry);

        if (offset + ent->tamanho > tamanho_buf) {
            fydlog_escrever(LOG_ERRO, "fpkg: dados do arquivo excedem tamanho do pacote");
            return -4;
        }

        if (fyd_registrar_arquivo_extraido(ent->destino, base + offset, ent->tamanho) != 0) {
            return -5;
        }
        offset += ent->tamanho;
    }

    fydlog_escrever(LOG_INFO, "fpkg: pacote instalado com sucesso em /fyd");
    return (int)pkg->qtd_arquivos;
}

/* =========================================================================
 * 3. PARSER DE CONFIGURAÇÃO (.fcfg)
 * ========================================================================= */
int fyd_cfg_ler_chave(const char *conteudo_cfg, const char *chave, char *valor_out, int max_len) {
    if (!conteudo_cfg || !chave || !valor_out || max_len <= 0) {
        fydlog_escrever(LOG_AVISO, "fcfg: parametros invalidos ao ler configuracao");
        return -1;
    }

    int chave_len = fyd_strlen(chave);
    const char *p = conteudo_cfg;

    while (*p) {
        while (*p == ' ' || *p == '\t') p++;

        if (*p == '#' || *p == '\n' || *p == '\r') {
            while (*p && *p != '\n') p++;
            if (*p == '\n') p++;
            continue;
        }

        if (fyd_strncmp(p, chave, chave_len) == 0 && p[chave_len] == '=') {
            p += chave_len + 1;
            int i = 0;
            while (*p && *p != '\n' && *p != '\r' && i < max_len - 1) {
                valor_out[i++] = *p++;
            }
            valor_out[i] = '\0';
            return 0;
        }

        while (*p && *p != '\n') p++;
        if (*p == '\n') p++;
    }

    valor_out[0] = '\0';
    return -2;
}
