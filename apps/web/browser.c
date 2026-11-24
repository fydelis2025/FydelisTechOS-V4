#include "../../apps/apps.h"
#include <stdint.h>
#include <stddef.h>

extern void gui_retangulo(int x, int y, int w, int h, uint32_t cor);
extern void gui_borda(int x, int y, int w, int h, uint32_t cor);
extern void gui_texto(int x, int y, const char *str, uint32_t cor);

extern uint32_t fb_largura;
extern uint32_t fb_altura;

/* ==== LIGAR ao seu HTTP client ==== */
extern int  http_get(const char *url);        /* dispara GET assíncrono */
extern int  http_estado(void);                /* 0=IDLE 1=CONECTANDO 2=BAIXANDO 3=OK -1=ERRO */
extern const char *http_corpo(void);          /* ponteiro para o body recebido */
extern int  http_corpo_len(void);
extern void http_reset(void);                 /* limpa estado p/ nova navegação */

/* ==== Dimensões reais do framebuffer ==== */
#define TELA_W ((int)(fb_largura ? fb_largura : 1024))
#define TELA_H ((int)(fb_altura  ? fb_altura  : 768))

/* Cores */
#define BRW_COR_PAINEL      0xFF1E0E3D
#define BRW_COR_TOPO        0xFF120826
#define BRW_COR_VIEW        0xFF120726
#define BRW_COR_INPUT       0xFF160A2E
#define BRW_COR_BTN         0xFF3B1D75
#define BRW_COR_ROXO        0xFF9D4EDD
#define BRW_COR_CIANO       0xFF00F5D4
#define BRW_COR_VERDE       0xFF00FF9C
#define BRW_COR_AMARELO     0xFFFFD166
#define BRW_COR_VERMELHO    0xFFFF4D6D
#define BRW_COR_TEXTO       0xFFF8FAFC
#define BRW_COR_SUAVE       0xFFCBD5E1

/* Estados da janela */
#define BRW_WIN_NORMAL      0
#define BRW_WIN_MAXIMIZADA  1
#define BRW_WIN_MINIMIZADA  2

#define BRW_URL_MAX 256
#define BRW_HIST_MAX 16

typedef struct {
    char url[BRW_URL_MAX];
    int  len;
} brw_hist_item_t;

/* ---------- Estado interno ---------- */
static char brw_url[BRW_URL_MAX] = "fydelis://home";
static int  brw_url_len = 14;
static int  brw_foco_url = 0;
static int  brw_pagina_id = 0;        /* 0=home 1=rede 2=cve 3=externa */

static int  brw_win_estado = BRW_WIN_NORMAL;
static int  brw_salvo_x = 170, brw_salvo_y = 85, brw_salvo_w = 560, brw_salvo_h = 360;

static int  brw_scroll = 0;           /* offset vertical em px da página externa */
static int  brw_scroll_max = 0;

/* Histórico */
static brw_hist_item_t brw_hist[BRW_HIST_MAX];
static int brw_hist_pos = -1;         /* índice atual */
static int brw_hist_count = 0;

/* ---------- Utilidades ---------- */
static int brw_str_eq(const char *a, const char *b) {
    int i = 0;
    while (a[i] && b[i]) {
        if (a[i] != b[i]) return 0;
        i++;
    }
    return a[i] == b[i];
}

static void brw_str_cpy(char *dst, const char *src, int max) {
    int i = 0;
    if (!dst || !src || max <= 0) {
        if (dst && max > 0) {
            dst[0] = '\0';
        }
        return;
    }

    while (i < max - 1 && src[i]) {
        dst[i] = src[i];
        i++;
    }
    dst[i] = '\0';
}

static void brw_set_url(const char *nova) {
    brw_str_cpy(brw_url, nova, BRW_URL_MAX);
    brw_url_len = 0;
    while (brw_url[brw_url_len]) brw_url_len++;
}

/* ---------- Histórico ---------- */
static void brw_hist_push(const char *url) {
    if (brw_hist_pos + 1 < BRW_HIST_MAX) {
        brw_hist_count = brw_hist_pos + 1;
    } else {
        for (int i = 0; i < BRW_HIST_MAX - 1; i++) brw_hist[i] = brw_hist[i + 1];
        brw_hist_count = BRW_HIST_MAX - 1;
    }
    brw_hist_pos = brw_hist_count;
    brw_str_cpy(brw_hist[brw_hist_pos].url, url, BRW_URL_MAX);
    brw_hist[brw_hist_pos].len = brw_url_len;
    brw_hist_count++;
}

static int brw_pode_voltar(void)  { return brw_hist_pos > 0; }
static int brw_pode_avancar(void) { return brw_hist_pos >= 0 && brw_hist_pos < brw_hist_count - 1; }

/* ---------- Geometria e Estados da Janela ---------- */
static void brw_geom(int *x, int *y, int *w, int *h) {
    if (brw_win_estado == BRW_WIN_MAXIMIZADA) {
        *x = 0;
        *y = 34;
        *w = TELA_W;
        *h = TELA_H - 72;
        app_browser.x = *x;
        app_browser.y = *y;
        app_browser.w = *w;
        app_browser.h = *h;
    } else {
        *x = app_browser.x;
        *y = app_browser.y;
        *w = app_browser.w;
        *h = app_browser.h;
    }
}

/* ---------- Navegação ---------- */
static void browser_navegar(void) {
    brw_scroll = 0;

    if (brw_str_eq(brw_url, "fydelis://home") || brw_str_eq(brw_url, "home")) {
        brw_pagina_id = 0;
    } else if (brw_str_eq(brw_url, "fydelis://rede") || brw_str_eq(brw_url, "rede")) {
        brw_pagina_id = 1;
    } else if (brw_str_eq(brw_url, "fydelis://cve") || brw_str_eq(brw_url, "cve")) {
        brw_pagina_id = 2;
    } else {
        brw_pagina_id = 3;
        http_reset();
        http_get(brw_url);
    }
}

static void browser_ir_para(const char *url) {
    brw_set_url(url);
    brw_foco_url = 0;
    browser_navegar();
    brw_hist_push(url);
}

static void browser_voltar(void) {
    if (!brw_pode_voltar()) return;
    brw_hist_pos--;
    brw_set_url(brw_hist[brw_hist_pos].url);
    brw_foco_url = 0;
    browser_navegar();
}

static void browser_avancar(void) {
    if (!brw_pode_avancar()) return;
    brw_hist_pos++;
    brw_set_url(brw_hist[brw_hist_pos].url);
    brw_foco_url = 0;
    browser_navegar();
}

static void browser_abrir(void) {
    app_browser.aberta = 1;
    if (brw_win_estado == BRW_WIN_MINIMIZADA) {
        app_browser.x = brw_salvo_x;
        app_browser.y = brw_salvo_y;
        app_browser.w = brw_salvo_w;
        app_browser.h = brw_salvo_h;
        brw_win_estado = BRW_WIN_NORMAL;
    }
    if (brw_hist_pos < 0) {
        brw_hist_push("fydelis://home");
        browser_navegar();
    }
}

void browser_alternar_minimizar(void) {
    if (!app_browser.aberta) {
        browser_abrir();
        return;
    }
    if (brw_win_estado == BRW_WIN_MINIMIZADA) {
        app_browser.x = brw_salvo_x;
        app_browser.y = brw_salvo_y;
        app_browser.w = brw_salvo_w;
        app_browser.h = brw_salvo_h;
        brw_win_estado = BRW_WIN_NORMAL;
    } else {
        if (brw_win_estado == BRW_WIN_NORMAL) {
            brw_salvo_x = app_browser.x;
            brw_salvo_y = app_browser.y;
            brw_salvo_w = app_browser.w;
            brw_salvo_h = app_browser.h;
        }
        brw_win_estado = BRW_WIN_MINIMIZADA;
    }
}

int browser_esta_minimizado(void) {
    return (app_browser.aberta && brw_win_estado == BRW_WIN_MINIMIZADA);
}

/* ---------- Botões da barra de título ---------- */
/* Layout na barra (direita p/ esquerda): [X][+][_] */
#define BRW_BTN_FECHAR(_x,_w) ((_x) + (_w) - 24)
#define BRW_BTN_MAX(_x,_w)    ((_x) + (_w) - 46)
#define BRW_BTN_MIN(_x,_w)    ((_x) + (_w) - 68)

/* ---------- Desenho ---------- */
static void brw_btn(int x, int y, int w, int h, uint32_t fundo, uint32_t borda,
                    const char *label, int lx, int ly, uint32_t cor_label) {
    gui_retangulo(x, y, w, h, fundo);
    gui_borda(x, y, w, h, borda);
    if (label) gui_texto(x + lx, y + ly, label, cor_label);
}

static void browser_desenhar(void) {
    if (!app_browser.aberta) return;
    if (brw_win_estado == BRW_WIN_MINIMIZADA) return;

    int x, y, w, h;
    brw_geom(&x, &y, &w, &h);

    /* Moldura */
    gui_retangulo(x, y, w, h, BRW_COR_PAINEL);
    gui_borda(x, y, w, h, BRW_COR_CIANO);

    /* Barra de título */
    gui_retangulo(x + 2, y + 2, w - 4, 26, BRW_COR_TOPO);
    gui_texto(x + 12, y + 7, "FydelisBrowser v2.0", BRW_COR_CIANO);

    /* [X] fechar */
    brw_btn(BRW_BTN_FECHAR(x, w), y + 4, 20, 20, BRW_COR_VERMELHO, BRW_COR_VERMELHO, "X", 6, 2, BRW_COR_TEXTO);
    /* [+] maximizar/restaurar */
    if (brw_win_estado == BRW_WIN_MAXIMIZADA)
        brw_btn(BRW_BTN_MAX(x, w), y + 4, 20, 20, BRW_COR_BTN, BRW_COR_AMARELO, "r", 6, 2, BRW_COR_AMARELO);
    else
        brw_btn(BRW_BTN_MAX(x, w), y + 4, 20, 20, BRW_COR_BTN, BRW_COR_VERDE, "+", 6, 2, BRW_COR_VERDE);
    /* [_] minimizar */
    brw_btn(BRW_BTN_MIN(x, w), y + 4, 20, 20, BRW_COR_BTN, BRW_COR_SUAVE, "_", 6, 6, BRW_COR_SUAVE);

    /* Barra de navegação: [<][>] [Home] [URL] [Ir] */
    int nav_y = y + 34;
    brw_btn(x + 10, nav_y, 26, 24, BRW_COR_BTN, brw_pode_voltar() ? BRW_COR_ROXO : 0xFF333333,
            "<", 8, 4, brw_pode_voltar() ? BRW_COR_TEXTO : 0xFF666666);
    brw_btn(x + 38, nav_y, 26, 24, BRW_COR_BTN, brw_pode_avancar() ? BRW_COR_ROXO : 0xFF333333,
            ">", 8, 4, brw_pode_avancar() ? BRW_COR_TEXTO : 0xFF666666);
    brw_btn(x + 68, nav_y, 46, 24, BRW_COR_BTN, BRW_COR_ROXO, "Home", 8, 4, BRW_COR_TEXTO);

    int url_x = x + 118;
    int url_w = w - 174;
    gui_retangulo(url_x, nav_y, url_w, 24, BRW_COR_INPUT);
    gui_borda(url_x, nav_y, url_w, 24, brw_foco_url ? BRW_COR_CIANO : BRW_COR_ROXO);

    /* mostra a porção final da URL se não couber */
    int vis_chars = (url_w - 16) / 8;
    const char *mostra = brw_url;
    int mostra_len = brw_url_len;
    if (brw_url_len > vis_chars) {
        mostra = brw_url + (brw_url_len - vis_chars);
        mostra_len = vis_chars;
    }
    gui_texto(url_x + 8, nav_y + 4, mostra, BRW_COR_TEXTO);
    if (brw_foco_url) gui_texto(url_x + 8 + (mostra_len * 8), nav_y + 4, "_", BRW_COR_CIANO);

    int go_x = x + w - 50;
    brw_btn(go_x, nav_y, 40, 24, BRW_COR_BTN, BRW_COR_CIANO, "Ir", 12, 4, BRW_COR_CIANO);

    /* Favoritos */
    int fav_y = nav_y + 28;
    gui_texto(x + 12, fav_y + 2, "Favoritos:", BRW_COR_SUAVE);
    gui_texto(x + 100, fav_y + 2, "[Inicio]", BRW_COR_CIANO);
    gui_texto(x + 176, fav_y + 2, "[Status Rede]", BRW_COR_VERDE);
    gui_texto(x + 292, fav_y + 2, "[CVE Guard]", BRW_COR_AMARELO);

    /* Viewport */
    int view_x = x + 10;
    int view_y = fav_y + 22;
    int view_w = w - 20;
    int area_h = h - (view_y - y) - 22;

    gui_retangulo(view_x, view_y, view_w, area_h, BRW_COR_VIEW);
    gui_borda(view_x, view_y, view_w, area_h, 0xFF4C2889);

    int tx = view_x + 14;
    int ty = view_y + 12 - brw_scroll;

    if (brw_pagina_id == 0) {
        gui_texto(tx, ty, "PORTAL INTRANET - FYDELISTECH OS v4.2", BRW_COR_CIANO); ty += 24;
        gui_texto(tx, ty, "Navegador rodando em Ring 0 (64-bit Freestanding).", BRW_COR_TEXTO); ty += 22;
        gui_texto(tx, ty, "Clique nos favoritos ou digite uma URL + ENTER.", BRW_COR_SUAVE); ty += 26;
        gui_texto(tx, ty, "> fydelis://home  - Pagina inicial do sistema", BRW_COR_VERDE); ty += 20;
        gui_texto(tx, ty, "> fydelis://rede  - Diagnostico TCP/IP, E1000 e Wi-Fi", BRW_COR_VERDE); ty += 20;
        gui_texto(tx, ty, "> fydelis://cve   - Assinaturas ativas do CVE Guard", BRW_COR_VERDE);
        brw_scroll_max = 0;
    } else if (brw_pagina_id == 1) {
        gui_texto(tx, ty, "DIAGNOSTICO DE REDE & INTERFACES", BRW_COR_VERDE); ty += 24;
        gui_texto(tx, ty, "Interface 0 (eth0): Controlador Intel E1000 MMIO", BRW_COR_TEXTO); ty += 20;
        gui_texto(tx, ty, "Interface 1 (wlan0): Driver 802.11 + WPA2 + DHCP", BRW_COR_TEXTO); ty += 20;
        gui_texto(tx, ty, "Pilha Protocolos: Ethernet / ARP / IPv4 / ICMP / UDP", BRW_COR_CIANO);
        brw_scroll_max = 0;
    } else if (brw_pagina_id == 2) {
        gui_texto(tx, ty, "FYDELIS CVE GUARD - ESCUDO ATIVO DO KERNEL", BRW_COR_AMARELO); ty += 24;
        gui_texto(tx, ty, "[ATIVO] CVE-2024-3094  - Bloqueio de payload XZ Backdoor", BRW_COR_TEXTO); ty += 20;
        gui_texto(tx, ty, "[ATIVO] CVE-2021-44228 - Filtro JNDI/LDAP Log4Shell", BRW_COR_TEXTO); ty += 20;
        gui_texto(tx, ty, "[ATIVO] FYD-MEM-001    - Deteccao de NOP sled 0x90909090", BRW_COR_TEXTO);
        brw_scroll_max = 0;
    } else {
        int est = http_estado();
        if (est == 0 || est == 1) {
            gui_texto(tx, ty, "CONECTANDO...", BRW_COR_AMARELO); ty += 20;
            gui_texto(tx, ty, brw_url, BRW_COR_CIANO);
        } else if (est == -1) {
            gui_texto(tx, ty, "FALHA DE CONEXAO", BRW_COR_VERMELHO); ty += 20;
            gui_texto(tx, ty, "Verifique o endereco e a rede (porta 80).", BRW_COR_SUAVE);
        } else if (est == 3 || est == 2) {
            const char *corpo = http_corpo();
            int total = http_corpo_len();
            int chars_por_linha = (view_w - 28) / 8;
            int max_linhas = (area_h - 24) / 14;

            int linha_atual = 0, col = 0, buf_i = 0;
            char linha_buf[128];
            int linhas_total = 0;
            for (int i = 0; i < total; i++) {
                if (corpo[i] == '\n' || col >= chars_por_linha) { linhas_total++; col = 0; }
                else col++;
            }
            if (col > 0) linhas_total++;
            brw_scroll_max = linhas_total * 14 > area_h ? linhas_total * 14 - area_h : 0;
            if (brw_scroll > brw_scroll_max) brw_scroll = brw_scroll_max;

            int primeira_visivel = brw_scroll / 14;
            col = 0; linha_atual = 0; buf_i = 0;
            for (int i = 0; i <= total; i++) {
                char ch = (i < total) ? corpo[i] : '\n';
                int quebra = (ch == '\n' || col >= chars_por_linha || i == total);
                if (quebra) {
                    if (linha_atual >= primeira_visivel &&
                        linha_atual < primeira_visivel + max_linhas) {
                        linha_buf[buf_i] = '\0';
                        gui_texto(tx, view_y + 12 + (linha_atual - primeira_visivel) * 14,
                                  linha_buf, BRW_COR_TEXTO);
                    }
                    linha_atual++; col = 0; buf_i = 0;
                    if (linha_atual >= primeira_visivel + max_linhas) break;
                } else {
                    if (ch >= 32 && ch < 127 && buf_i < 127) linha_buf[buf_i++] = ch;
                    col++;
                }
            }

            if (brw_scroll_max > 0) {
                int sb_x = view_x + view_w - 8;
                gui_retangulo(sb_x, view_y + 2, 6, area_h - 4, BRW_COR_TOPO);
                int prop = (area_h - 4) * area_h / (area_h + brw_scroll_max);
                int off  = brw_scroll * (area_h - 4 - prop) / brw_scroll_max;
                gui_retangulo(sb_x, view_y + 2 + off, 6, prop, BRW_COR_ROXO);
            }
        }
    }

    /* Barra de status */
    const char *st = "Pronto";
    int est = http_estado();
    if (brw_pagina_id == 3) {
        if (est == 0 || est == 1) st = "Conectando...";
        else if (est == 2)        st = "Baixando...";
        else if (est == 3)        st = "Carregado";
        else if (est == -1)       st = "Erro de rede";
    }
    gui_retangulo(x + 2, y + h - 20, w - 4, 18, BRW_COR_TOPO);
    gui_texto(x + 10, y + h - 18, st, BRW_COR_VERDE);
}

/* ---------- Cliques ---------- */
static void browser_on_click(int rel_x, int rel_y) {
    if (brw_win_estado == BRW_WIN_MINIMIZADA) return;

    int x, y, w, h;
    brw_geom(&x, &y, &w, &h);

    /* Barra de título */
    if (rel_y >= 2 && rel_y <= 28) {
        if (rel_x >= BRW_BTN_FECHAR(x, w) - x && rel_x <= BRW_BTN_FECHAR(x, w) - x + 20) {
            app_browser.aberta = 0;
            brw_win_estado = BRW_WIN_NORMAL;
            brw_hist_pos = -1;
            brw_hist_count = 0;
            return;
        }
        if (rel_x >= BRW_BTN_MAX(x, w) - x && rel_x <= BRW_BTN_MAX(x, w) - x + 20) {
            if (brw_win_estado == BRW_WIN_MAXIMIZADA) {
                app_browser.x = brw_salvo_x;
                app_browser.y = brw_salvo_y;
                app_browser.w = brw_salvo_w;
                app_browser.h = brw_salvo_h;
                brw_win_estado = BRW_WIN_NORMAL;
            } else {
                brw_salvo_x = app_browser.x;
                brw_salvo_y = app_browser.y;
                brw_salvo_w = app_browser.w;
                brw_salvo_h = app_browser.h;
                app_browser.x = 0;
                app_browser.y = 34;
                app_browser.w = TELA_W;
                app_browser.h = TELA_H - 72;
                brw_win_estado = BRW_WIN_MAXIMIZADA;
            }
            return;
        }
        if (rel_x >= BRW_BTN_MIN(x, w) - x && rel_x <= BRW_BTN_MIN(x, w) - x + 20) {
            browser_alternar_minimizar();
            return;
        }
        return;
    }

    int nav_y = 34;
    int fav_y = nav_y + 28;
    int view_y = fav_y + 22;

    /* [<][>] */
    if (rel_y >= nav_y && rel_y <= nav_y + 24) {
        if (rel_x >= 10 && rel_x <= 36)  { browser_voltar(); return; }
        if (rel_x >= 38 && rel_x <= 64)  { browser_avancar(); return; }
        if (rel_x >= 68 && rel_x <= 114) { browser_ir_para("fydelis://home"); return; }
        if (rel_x >= 68 + 50 && rel_x <= w - 56) { brw_foco_url = 1; return; }
        if (rel_x >= w - 50 && rel_x <= w - 10) { brw_foco_url = 0; browser_navegar(); brw_hist_push(brw_url); return; }
        brw_foco_url = 0;
        return;
    }

    /* Favoritos */
    if (rel_y >= fav_y && rel_y <= fav_y + 18) {
        if (rel_x >= 100 && rel_x <= 165)      browser_ir_para("fydelis://home");
        else if (rel_x >= 176 && rel_x <= 282) browser_ir_para("fydelis://rede");
        else if (rel_x >= 292 && rel_x <= 385) browser_ir_para("fydelis://cve");
        brw_foco_url = 0;
        return;
    }

    /* Área de conteúdo */
    if (rel_y >= view_y && rel_y <= h - 22) {
        if (brw_scroll > 0) brw_scroll -= 40;
        else brw_scroll = 0;
        return;
    }

    brw_foco_url = 0;
}

/* ---------- Teclado ---------- */
static void browser_on_key(char tecla) {
    if (brw_win_estado == BRW_WIN_MINIMIZADA) return;
    if (!brw_foco_url) return;

    if (tecla == '\n') {
        brw_foco_url = 0;
        browser_navegar();
        brw_hist_push(brw_url);
    } else if (tecla == '\b') {
        if (brw_url_len > 0) brw_url[--brw_url_len] = '\0';
    } else if (tecla >= 32 && tecla <= 126 && brw_url_len < BRW_URL_MAX - 1) {
        brw_url[brw_url_len++] = tecla;
        brw_url[brw_url_len] = '\0';
    }
}

FydelisApp app_browser = {
    .aberta   = 0,
    .x        = 170,
    .y        = 85,
    .w        = 800,
    .h        = 600,
    .abrir    = browser_abrir,
    .desenhar = browser_desenhar,
    .on_click = browser_on_click,
    .on_key   = browser_on_key
};
