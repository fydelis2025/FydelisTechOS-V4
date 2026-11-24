#include "../apps.h"
#include "../../include/fyd_formatos.h"
#include "../../include/icones.h"
#include <stdint.h>
#include <stddef.h>

extern void gui_retangulo(int x, int y, int w, int h, uint32_t cor);
extern void gui_borda(int x, int y, int w, int h, uint32_t cor);
extern void gui_texto(int x, int y, const char *str, uint32_t cor);
extern void gpu_desenhar_icone(const uint32_t *pixels, int x, int y, int w, int h);

extern uint32_t fb_largura;
extern uint32_t fb_altura;

/* Pontes reais com fs.asm (FAT32) */
extern int fs_existe(const char *caminho);
extern int fs_listar_dir(const char *caminho, char *buf_saida, int max_bytes);

#define TELA_W ((int)(fb_largura ? fb_largura : 1024))
#define TELA_H ((int)(fb_altura  ? fb_altura  : 768))

#define EXP_COR_PAINEL      0xFF1E0E3D
#define EXP_COR_TOPO        0xFF120826
#define EXP_COR_FUNDO_ARV   0xFF160A2E
#define EXP_COR_FUNDO_DIR   0xFF120726
#define EXP_COR_ITEM_SEL    0xFF3B1D75
#define EXP_COR_BTN         0xFF3B1D75
#define EXP_COR_ROXO        0xFF9D4EDD
#define EXP_COR_CIANO       0xFF00F5D4
#define EXP_COR_VERDE       0xFF00FF9C
#define EXP_COR_AMARELO     0xFFFFD166
#define EXP_COR_VERMELHO    0xFFFF4D6D
#define EXP_COR_TEXTO       0xFFF8FAFC
#define EXP_COR_SUAVE       0xFFCBD5E1

#define EXP_WIN_NORMAL      0
#define EXP_WIN_MAXIMIZADA  1
#define EXP_WIN_MINIMIZADA  2

#define EXP_NOME_MAX    64
#define EXP_CAMINHO_MAX 256
#define EXP_LISTA_MAX   64
#define EXP_DIR_BUF_MAX 4096

/* ---------- Estado ---------- */
static char exp_caminho[EXP_CAMINHO_MAX] = "/fyd";
static char exp_arvore_raiz[EXP_CAMINHO_MAX] = "/fyd";

typedef struct {
    char     nome[EXP_NOME_MAX];
    uint8_t  eh_dir;
    uint64_t tamanho;
} exp_entrada_t;

static exp_entrada_t exp_lista[EXP_LISTA_MAX];
static int exp_lista_count = 0;
static int exp_item_sel = -1;
static char exp_dir_raw[EXP_DIR_BUF_MAX];

static int exp_win_estado = EXP_WIN_NORMAL;
static int exp_salvo_x = 110, exp_salvo_y = 65, exp_salvo_w = 610, exp_salvo_h = 350;

/* Histórico de navegação (voltar) */
static char exp_hist[16][EXP_CAMINHO_MAX];
static int  exp_hist_pos = -1;
static int  exp_hist_count = 0;

/* ---------- Utilidades ---------- */
static void exp_str_cpy(char *dst, const char *src, int max) {
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

static void exp_str_lower(char *s) {
    for (int i = 0; s[i]; i++) {
        if (s[i] >= 'A' && s[i] <= 'Z') s[i] += 32;
    }
}

static int exp_str_eq(const char *a, const char *b) {
    int i = 0;
    while (a[i] && b[i]) { if (a[i] != b[i]) return 0; i++; }
    return a[i] == b[i];
}

static int exp_str_len(const char *s) { int i = 0; while (s[i]) i++; return i; }

static int exp_contem(const char *texto, const char *sub) {
    if (!texto || !sub) return 0;
    for (int i = 0; texto[i]; i++) {
        int j = 0;
        while (sub[j] && texto[i + j] == sub[j]) j++;
        if (!sub[j]) return 1;
    }
    return 0;
}

static void exp_juntar(char *dst, int max, const char *base, const char *nome) {
    int i = 0;
    while (base[i] && i < max - 2) { dst[i] = base[i]; i++; }
    if (i > 0 && dst[i - 1] != '/' && i < max - 2) dst[i++] = '/';
    int j = 0;
    while (nome[j] && i < max - 1) dst[i++] = nome[j++];
    dst[i] = '\0';
}

static void exp_pai(char *caminho) {
    int len = exp_str_len(caminho);
    while (len > 1 && caminho[len - 1] != '/') len--;
    if (len > 1) len--;
    caminho[len] = '\0';
    if (caminho[0] == '\0') { caminho[0] = '/'; caminho[1] = '\0'; }
}

/* ---------- Leitura Real do Diretório via fs.asm ---------- */
static void exp_carregar_diretorio(void) {
    exp_lista_count = 0;
    exp_item_sel = -1;

    int n = fs_listar_dir(exp_caminho, exp_dir_raw, EXP_DIR_BUF_MAX - 1);
    if (n <= 0) return;
    if (n >= EXP_DIR_BUF_MAX) n = EXP_DIR_BUF_MAX - 1;
    exp_dir_raw[n] = '\0';

    int pos = 0;
    while (pos < n && exp_lista_count < EXP_LISTA_MAX) {
        char linha[160];
        int li = 0;
        while (pos < n && exp_dir_raw[pos] != '\n' && exp_dir_raw[pos] != '\r' && exp_dir_raw[pos] != '\0') {
            if (li < 159) linha[li++] = exp_dir_raw[pos];
            pos++;
        }
        linha[li] = '\0';
        while (pos < n && (exp_dir_raw[pos] == '\n' || exp_dir_raw[pos] == '\r' || exp_dir_raw[pos] == '\0')) {
            pos++;
        }

        if (li == 0) continue;
        if (exp_str_eq(linha, ".") || exp_str_eq(linha, "..")) continue;

        exp_entrada_t *ent = &exp_lista[exp_lista_count];
        ent->eh_dir = 0;
        ent->tamanho = 0;

        char nome_real[EXP_NOME_MAX];
        nome_real[0] = '\0';

        if (li > 5 && linha[0] == '<' && linha[1] == 'D' && linha[2] == 'I' && linha[3] == 'R' && linha[4] == '>') {
            int k = 5;
            while (linha[k] == ' ' || linha[k] == '\t') k++;
            if (exp_str_eq(linha + k, ".") || exp_str_eq(linha + k, "..")) continue;
            ent->eh_dir = 1;
            exp_str_cpy(nome_real, linha + k, EXP_NOME_MAX);
        } else {
            int sep = -1;
            for (int k = 0; linha[k]; k++) {
                if (linha[k] == '\t' || (linha[k] == ' ' && linha[k + 1] == ' ')) {
                    sep = k;
                    break;
                }
            }

            if (sep > 0) {
                linha[sep] = '\0';
                exp_str_cpy(nome_real, linha, EXP_NOME_MAX);

                int k = sep + 1;
                while (linha[k] == ' ' || linha[k] == '\t') k++;
                if (linha[k] == '<' || linha[k] == '[') {
                    ent->eh_dir = 1;
                } else {
                    uint64_t tam = 0;
                    while (linha[k] >= '0' && linha[k] <= '9') {
                        tam = tam * 10 + (uint64_t)(linha[k] - '0');
                        k++;
                    }
                    ent->tamanho = tam;
                }
            } else {
                if (linha[li - 1] == '/') {
                    linha[li - 1] = '\0';
                    ent->eh_dir = 1;
                }
                exp_str_cpy(nome_real, linha, EXP_NOME_MAX);
            }
        }

        if (nome_real[0] == '\0') continue;

        /* Confirma via VFS se o item é diretório quando ainda não marcado */
        if (!ent->eh_dir) {
            char full_teste[EXP_CAMINHO_MAX];
            exp_juntar(full_teste, EXP_CAMINHO_MAX, exp_caminho, nome_real);
            char sub_probe[32];
            if (fs_listar_dir(full_teste, sub_probe, sizeof(sub_probe)) >= 0) {
                ent->eh_dir = 1;
            }
        }

        exp_str_cpy(ent->nome, nome_real, EXP_NOME_MAX);
        exp_str_lower(ent->nome);
        exp_lista_count++;
    }
}

static void exp_hist_push(const char *caminho) {
    if (exp_hist_pos + 1 < 16) exp_hist_count = exp_hist_pos + 1;
    else {
        for (int i = 0; i < 15; i++) exp_str_cpy(exp_hist[i], exp_hist[i + 1], EXP_CAMINHO_MAX);
        exp_hist_count = 15;
    }
    exp_hist_pos = exp_hist_count;
    exp_str_cpy(exp_hist[exp_hist_pos], caminho, EXP_CAMINHO_MAX);
    exp_hist_count++;
}

static void explorer_ir_para(const char *caminho) {
    char probe[32];
    int pode_listar = (fs_listar_dir(caminho, probe, sizeof(probe)) >= 0);
    if (!pode_listar && !fs_existe(caminho)) return;

    exp_str_cpy(exp_caminho, caminho, EXP_CAMINHO_MAX);
    exp_carregar_diretorio();
    exp_hist_push(caminho);
}

static void explorer_voltar(void) {
    if (exp_hist_pos <= 0) return;
    exp_hist_pos--;
    exp_str_cpy(exp_caminho, exp_hist[exp_hist_pos], EXP_CAMINHO_MAX);
    exp_carregar_diretorio();
}

/* ---------- Geometria e Estados ---------- */
static void exp_geom(int *x, int *y, int *w, int *h) {
    if (exp_win_estado == EXP_WIN_MAXIMIZADA) {
        *x = 0;
        *y = 34;
        *w = TELA_W;
        *h = TELA_H - 72;
        app_explorer.x = *x;
        app_explorer.y = *y;
        app_explorer.w = *w;
        app_explorer.h = *h;
    } else {
        *x = app_explorer.x;
        *y = app_explorer.y;
        *w = app_explorer.w;
        *h = app_explorer.h;
    }
}

/* Botões da barra de título (direita p/ esquerda): [X][+][_] */
#define EXP_BTN_FECHAR(_x,_w) ((_x) + (_w) - 24)
#define EXP_BTN_MAX(_x,_w)    ((_x) + (_w) - 46)
#define EXP_BTN_MIN(_x,_w)    ((_x) + (_w) - 68)

/* ---------- Abrir/Minimizar/Fechar ---------- */
static void explorer_abrir(void) {
    app_explorer.aberta = 1;
    if (exp_win_estado == EXP_WIN_MINIMIZADA) {
        app_explorer.x = exp_salvo_x;
        app_explorer.y = exp_salvo_y;
        app_explorer.w = exp_salvo_w;
        app_explorer.h = exp_salvo_h;
        exp_win_estado = EXP_WIN_NORMAL;
    }
    exp_carregar_diretorio();
    if (exp_hist_pos < 0) exp_hist_push(exp_caminho);
}

void explorer_alternar_minimizar(void) {
    if (!app_explorer.aberta) {
        explorer_abrir();
        return;
    }
    if (exp_win_estado == EXP_WIN_MINIMIZADA) {
        app_explorer.x = exp_salvo_x;
        app_explorer.y = exp_salvo_y;
        app_explorer.w = exp_salvo_w;
        app_explorer.h = exp_salvo_h;
        exp_win_estado = EXP_WIN_NORMAL;
    } else {
        if (exp_win_estado == EXP_WIN_NORMAL) {
            exp_salvo_x = app_explorer.x;
            exp_salvo_y = app_explorer.y;
            exp_salvo_w = app_explorer.w;
            exp_salvo_h = app_explorer.h;
        }
        exp_win_estado = EXP_WIN_MINIMIZADA;
    }
}

int explorer_esta_minimizado(void) {
    return (app_explorer.aberta && exp_win_estado == EXP_WIN_MINIMIZADA);
}

/* ---------- Desenho ---------- */
static void exp_btn(int x, int y, int w, int h, uint32_t fundo, uint32_t borda,
                    const char *label, int lx, int ly, uint32_t cor_label) {
    gui_retangulo(x, y, w, h, fundo);
    gui_borda(x, y, w, h, borda);
    if (label) gui_texto(x + lx, y + ly, label, cor_label);
}

static int exp_nivel(const char *caminho) {
    int nivel = 0;
    const char *raiz = exp_arvore_raiz;
    int len_r = exp_str_len(raiz);
    if (exp_contem(caminho, raiz) && caminho[0] == raiz[0]) {
        for (int i = len_r; caminho[i]; i++)
            if (caminho[i] == '/') nivel++;
    } else {
        for (int i = 0; caminho[i]; i++)
            if (caminho[i] == '/') nivel++;
        if (nivel > 0) nivel--;
    }
    return nivel;
}

static void exp_desenhar_arvore(int tree_x, int tree_y, int tree_w, int tree_h) {
    gui_texto(tree_x + 8, tree_y + 6, "ARVORE FAT32", EXP_COR_ROXO);

    int cy = tree_y + 26;
    int max_linhas = (tree_h - 28) / 20;
    if (max_linhas <= 0) return;

    char segmentos[16][EXP_NOME_MAX];
    int n_seg = 0;
    {
        char tmp[EXP_CAMINHO_MAX];
        exp_str_cpy(tmp, exp_caminho, EXP_CAMINHO_MAX);
        while (exp_str_len(tmp) > exp_str_len(exp_arvore_raiz) && n_seg < 16) {
            int l = exp_str_len(tmp), k = l;
            while (k > 0 && tmp[k - 1] != '/') k--;
            exp_str_cpy(segmentos[n_seg++], tmp + k, EXP_NOME_MAX);
            exp_pai(tmp);
        }
        for (int i = 0; i < n_seg / 2; i++) {
            char t[EXP_NOME_MAX];
            exp_str_cpy(t, segmentos[i], EXP_NOME_MAX);
            exp_str_cpy(segmentos[i], segmentos[n_seg - 1 - i], EXP_NOME_MAX);
            exp_str_cpy(segmentos[n_seg - 1 - i], t, EXP_NOME_MAX);
        }
    }

    char acumulado[EXP_CAMINHO_MAX];
    exp_str_cpy(acumulado, exp_arvore_raiz, EXP_CAMINHO_MAX);

    int linhas = 0;
    if (linhas < max_linhas) {
        int sel = exp_str_eq(acumulado, exp_caminho);
        if (sel) {
            gui_retangulo(tree_x + 4, cy - 2, tree_w - 8, 18, EXP_COR_ITEM_SEL);
            gui_borda(tree_x + 4, cy - 2, tree_w - 8, 18, EXP_COR_CIANO);
        }
        gpu_desenhar_icone(icone_pasta_aberta, tree_x + 8, cy, 14, 14);
        gui_texto(tree_x + 26, cy + 1, acumulado, sel ? EXP_COR_CIANO : EXP_COR_TEXTO);
        cy += 20; linhas++;
    }

    for (int s = 0; s < n_seg && linhas < max_linhas; s++) {
        int l = exp_str_len(acumulado);
        acumulado[l] = '/'; acumulado[l + 1] = '\0';
        exp_str_cpy(acumulado + l + 1, segmentos[s], EXP_CAMINHO_MAX - l - 1);

        int nivel = s + 1;
        int indent = nivel * 14;
        int sel = exp_str_eq(acumulado, exp_caminho);

        if (sel) {
            gui_retangulo(tree_x + 4, cy - 2, tree_w - 8, 18, EXP_COR_ITEM_SEL);
            gui_borda(tree_x + 4, cy - 2, tree_w - 8, 18, EXP_COR_CIANO);
        }
        gui_texto(tree_x + 6 + indent - 12, cy + 1, "|-", EXP_COR_SUAVE);
        gpu_desenhar_icone(icone_pasta_aberta, tree_x + 8 + indent, cy, 14, 14);
        gui_texto(tree_x + 26 + indent, cy + 1, segmentos[s],
                  sel ? EXP_COR_CIANO : EXP_COR_TEXTO);
        cy += 20; linhas++;
    }

    int restam = max_linhas - linhas;
    int desenhadas = 0;
    for (int i = 0; i < exp_lista_count && desenhadas < restam; i++) {
        if (!exp_lista[i].eh_dir) continue;
        int indent = (exp_nivel(exp_caminho) + 1) * 14;
        gui_texto(tree_x + 6 + indent - 12, cy + 1, "|-", EXP_COR_SUAVE);
        gpu_desenhar_icone(icone_pasta_fechada, tree_x + 8 + indent, cy, 14, 14);
        gui_texto(tree_x + 26 + indent, cy + 1, exp_lista[i].nome, EXP_COR_VERDE);
        cy += 20; desenhadas++;
    }
}

static void explorer_desenhar(void) {
    if (!app_explorer.aberta) return;
    if (exp_win_estado == EXP_WIN_MINIMIZADA) return;

    int x, y, w, h;
    exp_geom(&x, &y, &w, &h);

    /* Moldura */
    gui_retangulo(x, y, w, h, EXP_COR_PAINEL);
    gui_borda(x, y, w, h, EXP_COR_ROXO);

    /* Barra de título */
    gui_retangulo(x + 2, y + 2, w - 4, 26, EXP_COR_TOPO);
    gpu_desenhar_icone(icone_pasta_aberta, x + 8, y + 6, 16, 16);
    gui_texto(x + 30, y + 7, "FydelisExplorer - FAT32 /fyd", EXP_COR_CIANO);

    /* Botões: [_] Minimizar, [+] Maximizar/Restaurar, [X] Fechar */
    exp_btn(EXP_BTN_FECHAR(x, w), y + 4, 20, 20, EXP_COR_VERMELHO, EXP_COR_VERMELHO,
            "X", 6, 2, EXP_COR_TEXTO);
    if (exp_win_estado == EXP_WIN_MAXIMIZADA)
        exp_btn(EXP_BTN_MAX(x, w), y + 4, 20, 20, EXP_COR_BTN, EXP_COR_AMARELO,
                "r", 6, 2, EXP_COR_AMARELO);
    else
        exp_btn(EXP_BTN_MAX(x, w), y + 4, 20, 20, EXP_COR_BTN, EXP_COR_VERDE,
                "+", 6, 2, EXP_COR_VERDE);
    exp_btn(EXP_BTN_MIN(x, w), y + 4, 20, 20, EXP_COR_BTN, EXP_COR_SUAVE,
            "_", 6, 6, EXP_COR_SUAVE);

    /* Barra de ferramentas */
    int tb_y = y + 34;
    exp_btn(x + 10, tb_y, 64, 24, EXP_COR_BTN, EXP_COR_ROXO, "<Voltar", 6, 4, EXP_COR_TEXTO);
    exp_btn(x + 80, tb_y, 56, 24, EXP_COR_BTN, EXP_COR_ROXO, "Acima", 10, 4, EXP_COR_TEXTO);

    gui_retangulo(x + 142, tb_y, w - 152, 24, EXP_COR_FUNDO_ARV);
    gui_borda(x + 142, tb_y, w - 152, 24, 0xFF4C2889);
    gui_texto(x + 150, tb_y + 4, exp_caminho, EXP_COR_VERDE);

    /* Painéis */
    int tree_x = x + 10;
    int tree_y = y + 64;
    int tree_w = 225;
    int tree_h = h - 94;

    gui_retangulo(tree_x, tree_y, tree_w, tree_h, EXP_COR_FUNDO_ARV);
    gui_borda(tree_x, tree_y, tree_w, tree_h, 0xFF4C2889);
    exp_desenhar_arvore(tree_x, tree_y, tree_w, tree_h);

    int pane_x = tree_x + tree_w + 8;
    int pane_y = tree_y;
    int pane_w = w - tree_w - 28;
    int pane_h = tree_h;

    gui_retangulo(pane_x, pane_y, pane_w, pane_h, EXP_COR_FUNDO_DIR);
    gui_borda(pane_x, pane_y, pane_w, pane_h, 0xFF4C2889);

    int px = pane_x + 12;
    int py = pane_y + 8;

    gui_texto(px, py, "CONTEUDO:", EXP_COR_CIANO);
    gui_texto(px + 96, py, exp_caminho, EXP_COR_VERDE);
    py += 22;

    if (exp_lista_count == 0) {
        gui_texto(px, py, "(diretorio vazio)", EXP_COR_SUAVE);
    }

    int max_itens = (pane_h - 34) / 18;
    for (int i = 0; i < exp_lista_count && i < max_itens; i++) {
        exp_entrada_t *e = &exp_lista[i];
        int sel = (i == exp_item_sel);

        if (sel) {
            gui_retangulo(pane_x + 4, py - 2, pane_w - 8, 18, EXP_COR_ITEM_SEL);
            gui_borda(pane_x + 4, py - 2, pane_w - 8, 18, EXP_COR_CIANO);
        }

        gpu_desenhar_icone(e->eh_dir ? icone_pasta_fechada : icone_arquivo,
                           px, py, 14, 14);

        gui_texto(px + 20, py + 1, e->nome,
                  e->eh_dir ? EXP_COR_VERDE :
                  (sel ? EXP_COR_CIANO : EXP_COR_TEXTO));

        if (!e->eh_dir) {
            char tam[24];
            int ti = 0;
            uint64_t v = e->tamanho;
            if (v == 0) {
                tam[ti++] = '0';
            } else {
                char inv[24];
                int ii = 0;
                while (v) { inv[ii++] = '0' + (v % 10); v /= 10; }
                while (ii) tam[ti++] = inv[--ii];
            }
            tam[ti++] = ' ';
            tam[ti++] = 'B';
            tam[ti++] = '\0';
            gui_texto(pane_x + pane_w - 90, py + 1, tam, EXP_COR_SUAVE);
        } else {
            gui_texto(pane_x + pane_w - 90, py + 1, "<DIR>", EXP_COR_AMARELO);
        }
        py += 18;
    }

    /* Barra de status */
    gui_retangulo(x + 2, y + h - 22, w - 4, 20, EXP_COR_TOPO);
    char status[64];
    int si = 0;
    const char *p1 = "FAT32 | Itens: ";
    for (int i = 0; p1[i]; i++) status[si++] = p1[i];
    {
        int v = exp_lista_count;
        char inv[8];
        int ii = 0;
        if (!v) inv[ii++] = '0';
        while (v) { inv[ii++] = '0' + (v % 10); v /= 10; }
        while (ii) status[si++] = inv[--ii];
    }
    status[si] = '\0';
    gui_texto(x + 12, y + h - 19, status, EXP_COR_SUAVE);
}

/* ---------- Cliques ---------- */
static void explorer_on_click(int rel_x, int rel_y) {
    if (exp_win_estado == EXP_WIN_MINIMIZADA) return;

    int x, y, w, h;
    exp_geom(&x, &y, &w, &h);

    /* Barra de título */
    if (rel_y >= 2 && rel_y <= 28) {
        if (rel_x >= EXP_BTN_FECHAR(x, w) - x && rel_x <= EXP_BTN_FECHAR(x, w) - x + 20) {
            app_explorer.aberta = 0;
            exp_win_estado = EXP_WIN_NORMAL;
            return;
        }
        if (rel_x >= EXP_BTN_MAX(x, w) - x && rel_x <= EXP_BTN_MAX(x, w) - x + 20) {
            if (exp_win_estado == EXP_WIN_MAXIMIZADA) {
                app_explorer.x = exp_salvo_x;
                app_explorer.y = exp_salvo_y;
                app_explorer.w = exp_salvo_w;
                app_explorer.h = exp_salvo_h;
                exp_win_estado = EXP_WIN_NORMAL;
            } else {
                exp_salvo_x = app_explorer.x;
                exp_salvo_y = app_explorer.y;
                exp_salvo_w = app_explorer.w;
                exp_salvo_h = app_explorer.h;
                app_explorer.x = 0;
                app_explorer.y = 34;
                app_explorer.w = TELA_W;
                app_explorer.h = TELA_H - 72;
                exp_win_estado = EXP_WIN_MAXIMIZADA;
            }
            return;
        }
        if (rel_x >= EXP_BTN_MIN(x, w) - x && rel_x <= EXP_BTN_MIN(x, w) - x + 20) {
            explorer_alternar_minimizar();
            return;
        }
        return;
    }

    int tb_y = 34;
    int tree_x = 10, tree_y = 64, tree_w = 225, tree_h = h - 94;

    /* Toolbar */
    if (rel_y >= tb_y && rel_y <= tb_y + 24) {
        if (rel_x >= 10 && rel_x <= 74)  { explorer_voltar(); return; }
        if (rel_x >= 80 && rel_x <= 136) { /* Acima */
            if (exp_str_len(exp_caminho) > exp_str_len(exp_arvore_raiz)) {
                char pai[EXP_CAMINHO_MAX];
                exp_str_cpy(pai, exp_caminho, EXP_CAMINHO_MAX);
                exp_pai(pai);
                explorer_ir_para(pai);
            }
            return;
        }
        return;
    }

    /* Árvore: cliques nas subpastas listadas abrem o diretório */
    if (rel_x >= tree_x && rel_x <= tree_x + tree_w &&
        rel_y >= tree_y + 24 && rel_y <= tree_y + tree_h) {
        int n_seg = 0;
        char tmp[EXP_CAMINHO_MAX];
        exp_str_cpy(tmp, exp_caminho, EXP_CAMINHO_MAX);
        while (exp_str_len(tmp) > exp_str_len(exp_arvore_raiz)) {
            exp_pai(tmp); n_seg++;
        }
        int primeira_sub = 26 + (n_seg + 1) * 20;
        int idx = (rel_y - (tree_y + primeira_sub)) / 20;

        int visiveis = (tree_h - primeira_sub - 2) / 20;
        int passados = 0;
        for (int i = 0; i < exp_lista_count; i++) {
            if (!exp_lista[i].eh_dir) continue;
            if (passados >= visiveis) break;
            if (passados == idx) {
                char novo[EXP_CAMINHO_MAX];
                exp_juntar(novo, EXP_CAMINHO_MAX, exp_caminho, exp_lista[i].nome);
                explorer_ir_para(novo);
                return;
            }
            passados++;
        }
        return;
    }

    /* Painel de conteúdo */
    int pane_x = tree_x + tree_w + 8;
    int pane_y = tree_y;
    if (rel_x >= pane_x && rel_y >= pane_y + 30) {
        int idx = (rel_y - (pane_y + 30)) / 18;
        if (idx >= 0 && idx < exp_lista_count) {
            exp_item_sel = idx;
            if (exp_lista[idx].eh_dir) {
                char novo[EXP_CAMINHO_MAX];
                exp_juntar(novo, EXP_CAMINHO_MAX, exp_caminho, exp_lista[idx].nome);
                explorer_ir_para(novo);
            }
        }
    }
}

/* ---------- Teclado ---------- */
static void explorer_on_key(char tecla) {
    if (exp_win_estado == EXP_WIN_MINIMIZADA) return;
    if (exp_lista_count <= 0) return;

    if (tecla == '\t' || tecla == 's' || tecla == 'S') {
        exp_item_sel = (exp_item_sel + 1) % exp_lista_count;
    } else if (tecla == 'w' || tecla == 'W') {
        exp_item_sel = (exp_item_sel - 1 + exp_lista_count) % exp_lista_count;
    } else if (tecla == '\n') {
        if (exp_item_sel >= 0 && exp_lista[exp_item_sel].eh_dir) {
            char novo[EXP_CAMINHO_MAX];
            exp_juntar(novo, EXP_CAMINHO_MAX, exp_caminho, exp_lista[exp_item_sel].nome);
            explorer_ir_para(novo);
        }
    } else if (tecla == '\b') {
        explorer_voltar();
    }
}

FydelisApp app_explorer = {
    .aberta   = 0,
    .x        = 110,
    .y        = 65,
    .w        = 610,
    .h        = 350,
    .abrir    = explorer_abrir,
    .desenhar = explorer_desenhar,
    .on_click = explorer_on_click,
    .on_key   = explorer_on_key
};
