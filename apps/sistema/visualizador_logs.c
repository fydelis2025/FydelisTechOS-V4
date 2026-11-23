#include <stdint.h>
#include "../apps.h"
#include "../../include/fydlog.h"
#include "../../include/cve_guard.h"

/* Paleta Cyberpunk Purple & Neon */
#define LOG_COR_FUNDO      0xFF1A0B36
#define LOG_COR_BARRA      0xFF281352
#define LOG_COR_VISOR      0xFF100622
#define LOG_COR_BORDA      0xFF9D4EDD
#define LOG_COR_CIANO      0xFF00F5D4
#define LOG_COR_VERDE      0xFF00FF9C
#define LOG_COR_AMARELO    0xFFFFD166
#define LOG_COR_VERMELHO   0xFFFF4D6D
#define LOG_COR_TEXTO      0xFFF8FAFC
#define LOG_COR_SUAVE      0xFF94A3B8
#define LOG_COR_BTN        0xFF3B1D75

#define MAX_LINHAS_VISIVEIS 15
#define MAX_CHARS_LINHA     68

/* Modos de exibicao: 0 = Logs .flog | 1 = Tabela CVE Guard */
static int modo_aba = 0;
static int linha_topo = 0;

static int log_strncmp(const char *a, const char *b, int n) {
    for (int i = 0; i < n; i++) {
        if (a[i] != b[i]) return 1;
        if (a[i] == '\0') return 0;
    }
    return 0;
}

static int log_contar_linhas(const char *buf) {
    if (!buf || !buf[0]) return 0;
    int linhas = 1;
    for (int i = 0; buf[i]; i++) {
        if (buf[i] == '\n' && buf[i + 1] != '\0') linhas++;
    }
    return linhas;
}

/* Converte uint64_t para string decimal sem depender da libc */
static void log_uint_para_str(uint64_t val, char *dest) {
    char tmp[24];
    int pos = 0;
    if (val == 0) {
        dest[0] = '0';
        dest[1] = '\0';
        return;
    }
    while (val > 0 && pos < 23) {
        tmp[pos++] = (char)('0' + (val % 10));
        val /= 10;
    }
    int j = 0;
    while (pos > 0) {
        dest[j++] = tmp[--pos];
    }
    dest[j] = '\0';
}

/* Monta linha formatada da regra CVE para caber no visor de 68 colunas */
static void log_formatar_regra_cve(const char *id, const char *padrao, const char *msg, char *out) {
    int p = 0;

    /* Coluna 1: ID (14 chars) */
    for (int i = 0; i < 14; i++) {
        if (id && id[i]) out[p++] = id[i];
        else break;
    }
    while (p < 14) out[p++] = ' ';
    out[p++] = ' ';
    out[p++] = '|';
    out[p++] = ' ';

    /* Coluna 2: Padrao (18 chars) */
    int fim_col2 = p + 18;
    for (int i = 0; i < 18; i++) {
        if (padrao && padrao[i]) out[p++] = padrao[i];
        else break;
    }
    while (p < fim_col2) out[p++] = ' ';
    out[p++] = ' ';
    out[p++] = '|';
    out[p++] = ' ';

    /* Coluna 3: Descricao (restante ate 68 chars) */
    int i = 0;
    while (msg && msg[i] && p < MAX_CHARS_LINHA) {
        out[p++] = msg[i++];
    }
    out[p] = '\0';
}

static uint32_t log_cor_por_nivel(const char *linha) {
    if (linha[0] == '#') return LOG_COR_SUAVE;
    if (log_strncmp(linha, "[INFO]", 6) == 0)      return LOG_COR_VERDE;
    if (log_strncmp(linha, "[AVISO]", 7) == 0)     return LOG_COR_AMARELO;
    if (log_strncmp(linha, "[ERRO]", 6) == 0)      return LOG_COR_VERMELHO;
    if (log_strncmp(linha, "[CRITICO]", 9) == 0)   return LOG_COR_VERMELHO;
    if (log_strncmp(linha, "[CVE-GUARD]", 11) == 0) return LOG_COR_VERMELHO;
    return LOG_COR_TEXTO;
}

static void vlog_abrir(void);
static void vlog_desenhar(void);
static void vlog_on_click(int rel_x, int rel_y);
static void vlog_on_key(char tecla);

FydelisApp app_visualizador_logs = {
    .nome      = "FydLog & CVE Guard - Monitor do Sistema",
    .categoria = CAT_SISTEMA,
    .aberta    = 0,
    .x         = 180,
    .y         = 95,
    .w         = 600,
    .h         = 360,
    .abrir     = vlog_abrir,
    .desenhar  = vlog_desenhar,
    .on_click  = vlog_on_click,
    .on_key    = vlog_on_key
};

static void vlog_abrir(void) {
    app_visualizador_logs.aberta = 1;
    modo_aba = 0;
    const char *buf = fydlog_obter_buffer();
    int total = log_contar_linhas(buf);
    linha_topo = (total > MAX_LINHAS_VISIVEIS) ? (total - MAX_LINHAS_VISIVEIS) : 0;
}

static void vlog_desenhar_aba_cve(int vx, int vy, int vw) {
    char num_str[24];
    char id[32];
    char padrao[128];
    char msg[256];
    char linha_fmt[MAX_CHARS_LINHA + 1];

    uint64_t total_regras  = cve_guard_total_regras();
    uint64_t total_alertas = cve_guard_total_alertas();

    /* Barra de status superior do CVE Guard */
    gui_retangulo(vx + 6, vy + 6, vw - 12, 24, 0xFF210E44);
    gui_texto(vx + 12, vy + 10, "SHIELD: ATIVO", LOG_COR_VERDE);

    gui_texto(vx + 150, vy + 10, "REGRAS:", LOG_COR_CIANO);
    log_uint_para_str(total_regras, num_str);
    gui_texto(vx + 212, vy + 10, num_str, LOG_COR_TEXTO);

    gui_texto(vx + 290, vy + 10, "AMEACAS BLOQUEADAS:", LOG_COR_AMARELO);
    log_uint_para_str(total_alertas, num_str);
    gui_texto(vx + 450, vy + 10, num_str, (total_alertas > 0) ? LOG_COR_VERMELHO : LOG_COR_VERDE);

    /* Cabecalho da tabela */
    int ty = vy + 38;
    gui_texto(vx + 10, ty, "ID REGRA       | ASSINATURA         | DESCRICAO DA AMEACA", LOG_COR_CIANO);
    gui_retangulo(vx + 10, ty + 15, vw - 20, 1, LOG_COR_BORDA);
    ty += 22;

    if (total_regras == 0) {
        gui_texto(vx + 10, ty + 6, "Nenhuma assinatura CVE carregada na tabela do kernel.", LOG_COR_SUAVE);
        return;
    }

    int max_linhas_tabela = 11;
    int desenhadas = 0;

    for (uint64_t i = (uint64_t)linha_topo; i < total_regras && desenhadas < max_linhas_tabela; i++) {
        if (cve_guard_obter_regra(i, id, padrao, msg)) {
            log_formatar_regra_cve(id, padrao, msg, linha_fmt);
            gui_texto(vx + 10, ty + (desenhadas * 17), linha_fmt, LOG_COR_TEXTO);
            desenhadas++;
        }
    }
}

static void vlog_desenhar(void) {
    if (!app_visualizador_logs.aberta) return;

    int x = app_visualizador_logs.x;
    int y = app_visualizador_logs.y;
    int w = app_visualizador_logs.w;
    int h = app_visualizador_logs.h;

    /* Moldura e Barra de Titulo */
    gui_retangulo(x, y, w, h, LOG_COR_FUNDO);
    gui_borda(x, y, w, h, LOG_COR_BORDA);
    gui_retangulo(x + 2, y + 2, w - 4, 26, LOG_COR_BARRA);
    gui_texto(x + 10, y + 7, app_visualizador_logs.nome, LOG_COR_CIANO);

    /* Botao Fechar [X] */
    gui_retangulo(x + w - 24, y + 4, 20, 20, LOG_COR_VERMELHO);
    gui_texto(x + w - 18, y + 6, "X", LOG_COR_TEXTO);

    /* Barra de ferramentas superior */
    int tb_y = y + 34;

    /* Subir */
    gui_retangulo(x + 12, tb_y, 64, 22, LOG_COR_BTN);
    gui_borda(x + 12, tb_y, 64, 22, LOG_COR_BORDA);
    gui_texto(x + 22, tb_y + 4, "Subir", LOG_COR_TEXTO);

    /* Descer */
    gui_retangulo(x + 82, tb_y, 70, 22, LOG_COR_BTN);
    gui_borda(x + 82, tb_y, 70, 22, LOG_COR_BORDA);
    gui_texto(x + 92, tb_y + 4, "Descer", LOG_COR_TEXTO);

    /* Aba 1: Logs .flog */
    gui_retangulo(x + 160, tb_y, 108, 22, (modo_aba == 0) ? 0xFF4C2889 : LOG_COR_BTN);
    gui_borda(x + 160, tb_y, 108, 22, (modo_aba == 0) ? LOG_COR_CIANO : LOG_COR_BORDA);
    gui_texto(x + 170, tb_y + 4, "Logs Sistema", (modo_aba == 0) ? LOG_COR_CIANO : LOG_COR_TEXTO);

    /* Aba 2: CVE Guard */
    gui_retangulo(x + 274, tb_y, 102, 22, (modo_aba == 1) ? 0xFF4C2889 : LOG_COR_BTN);
    gui_borda(x + 274, tb_y, 102, 22, (modo_aba == 1) ? LOG_COR_VERMELHO : LOG_COR_BORDA);
    gui_texto(x + 286, tb_y + 4, "CVE Guard", (modo_aba == 1) ? LOG_COR_VERMELHO : LOG_COR_TEXTO);

    /* Botao contextual (Evento Teste na aba Logs ou Zerar Alertas na aba CVE) */
    if (modo_aba == 0) {
        gui_retangulo(x + 384, tb_y, 120, 22, LOG_COR_BTN);
        gui_borda(x + 384, tb_y, 120, 22, LOG_COR_VERDE);
        gui_texto(x + 392, tb_y + 4, "+ Evento Teste", LOG_COR_VERDE);
    } else {
        gui_retangulo(x + 384, tb_y, 120, 22, LOG_COR_BTN);
        gui_borda(x + 384, tb_y, 120, 22, LOG_COR_AMARELO);
        gui_texto(x + 392, tb_y + 4, "Zerar Alertas", LOG_COR_AMARELO);
    }

    /* Area do visor principal */
    int vx = x + 12;
    int vy = y + 64;
    int vw = w - 24;
    int vh = h - 88;
    gui_retangulo(vx, vy, vw, vh, LOG_COR_VISOR);
    gui_borda(vx, vy, vw, vh, 0xFF4C2889);

    if (modo_aba == 1) {
        vlog_desenhar_aba_cve(vx, vy, vw);
        gui_texto(x + 14, y + h - 18, "CVE Guard x86_64 | Use W/S para rolar assinaturas ou Zerar Alertas.", LOG_COR_SUAVE);
        return;
    }

    const char *buf = fydlog_obter_buffer();
    if (!buf || !buf[0]) {
        gui_texto(vx + 12, vy + 14, "Nenhum registro encontrado em /fyd/dados/logs/sistema.flog.", LOG_COR_SUAVE);
        return;
    }

    int linha_atual = 0;
    const char *p = buf;
    while (*p && linha_atual < linha_topo) {
        if (*p == '\n') linha_atual++;
        p++;
    }

    int desenhadas = 0;
    char linha_tmp[MAX_CHARS_LINHA + 1];

    while (*p && desenhadas < MAX_LINHAS_VISIVEIS) {
        int i = 0;
        while (*p && *p != '\n' && i < MAX_CHARS_LINHA) {
            linha_tmp[i++] = *p++;
        }
        linha_tmp[i] = '\0';

        while (*p && *p != '\n') p++;
        if (*p == '\n') p++;

        uint32_t cor = log_cor_por_nivel(linha_tmp);
        gui_texto(vx + 10, vy + 10 + (desenhadas * 17), linha_tmp, cor);
        desenhadas++;
    }

    gui_texto(x + 14, y + h - 18, "Formato: #!FYDLOG v1 | Use W/S ou os botoes acima para rolar.", LOG_COR_SUAVE);
}

static void vlog_on_click(int rel_x, int rel_y) {
    int total = 0;
    int max_visiveis = MAX_LINHAS_VISIVEIS;

    if (modo_aba == 0) {
        total = log_contar_linhas(fydlog_obter_buffer());
    } else {
        total = (int)cve_guard_total_regras();
        max_visiveis = 11;
    }

    int max_topo = (total > max_visiveis) ? (total - max_visiveis) : 0;

    if (rel_y >= 34 && rel_y <= 56) {
        if (rel_x >= 12 && rel_x <= 76) {
            /* Subir */
            if (linha_topo > 0) linha_topo--;
        } else if (rel_x >= 82 && rel_x <= 152) {
            /* Descer */
            if (linha_topo < max_topo) linha_topo++;
        } else if (rel_x >= 160 && rel_x <= 268) {
            /* Aba Logs Sistema */
            modo_aba = 0;
            total = log_contar_linhas(fydlog_obter_buffer());
            linha_topo = (total > MAX_LINHAS_VISIVEIS) ? (total - MAX_LINHAS_VISIVEIS) : 0;
        } else if (rel_x >= 274 && rel_x <= 376) {
            /* Aba CVE Guard */
            modo_aba = 1;
            linha_topo = 0;
        } else if (rel_x >= 384 && rel_x <= 504) {
            if (modo_aba == 0) {
                fydlog_escrever(LOG_INFO, "Evento de diagnostico registrado pelo Visualizador");
                total = log_contar_linhas(fydlog_obter_buffer());
                linha_topo = (total > MAX_LINHAS_VISIVEIS) ? (total - MAX_LINHAS_VISIVEIS) : 0;
            } else {
                cve_guard_zerar_alertas();
            }
        }
    }
}

static void vlog_on_key(char tecla) {
    int total = 0;
    int max_visiveis = MAX_LINHAS_VISIVEIS;

    if (modo_aba == 0) {
        total = log_contar_linhas(fydlog_obter_buffer());
    } else {
        total = (int)cve_guard_total_regras();
        max_visiveis = 11;
    }

    int max_topo = (total > max_visiveis) ? (total - max_visiveis) : 0;

    if (tecla == 'w' || tecla == 'W') {
        if (linha_topo > 0) linha_topo--;
    } else if (tecla == 's' || tecla == 'S') {
        if (linha_topo < max_topo) linha_topo++;
    }
}
