#include "../apps.h"
#include "../../include/icones.h"
#include <stdint.h>
#include <stddef.h>

extern void gui_retangulo(int x, int y, int w, int h, uint32_t cor);
extern void gui_borda(int x, int y, int w, int h, uint32_t cor);
extern void gui_texto(int x, int y, const char *str, uint32_t cor);
extern void gpu_desenhar_icone(const uint32_t *pixels, int x, int y, int w, int h);

extern uint32_t fb_largura;
extern uint32_t fb_altura;

/* Ponte com fs.asm (FAT32 real) */
extern int fs_existe(const char *caminho);
extern int fs_ler_arquivo(const char *caminho, char *buf, int max);
extern int fs_gravar_arquivo(const char *caminho, const char *buf, int len);

#define TELA_W ((int)(fb_largura ? fb_largura : 800))
#define TELA_H ((int)(fb_altura  ? fb_altura  : 600))

/* Visual da janela e moldura em roxo/ciano; área de digitação branca com escrita escura */
#define NTC_PAINEL      0xFF1E0E3D
#define NTC_TOPO        0xFF120826
#define NTC_EDIT        0xFFFFFFFF
#define NTC_NUM_LINHA   0xFF1A0C36
#define NTC_ITEM_SEL    0xFF3B1D75
#define NTC_ROXO        0xFF9D4EDD
#define NTC_CIANO       0xFF00F5D4
#define NTC_VERDE       0xFF00FF9C
#define NTC_AMARELO     0xFFFFD166
#define NTC_VERMELHO    0xFFFF4D6D
#define NTC_TEXTO       0xFF0F172A
#define NTC_SUAVE       0xFFCBD5E1
#define NTC_LINHA_CUR   0xFFF1E8FF

#define NTC_WIN_NORMAL      0
#define NTC_WIN_MAXIMIZADA  1
#define NTC_WIN_MINIMIZADA  2

#define NTC_ABAS_MAX    6
#define NTC_NOME_MAX    48
#define NTC_CAMINHO_MAX 128
#define NTC_BUF_MAX     8192

#define NTC_CW  8
#define NTC_LH  14

typedef struct {
    char nome[NTC_NOME_MAX];
    char caminho[NTC_CAMINHO_MAX];
    char buf[NTC_BUF_MAX];
    int  len;
    int  modificado;
    int  aberta;
} ntc_aba_t;

extern FydelisApp app_notepad;

static ntc_aba_t ntc_abas[NTC_ABAS_MAX];
static int ntc_aba_ativa = 0;
static int ntc_aba_count = 0;

static int ntc_cursor_lin = 0;
static int ntc_cursor_col = 0;
static int ntc_scroll_v = 0;
static int ntc_scroll_h = 0;

static int ntc_win_estado = NTC_WIN_NORMAL;
static int ntc_salvo_x = 120, ntc_salvo_y = 70, ntc_salvo_w = 640, ntc_salvo_h = 420;

static char ntc_mensagem[64] = "";

static int ntc_len(const char *s) {
    int i = 0;
    while (s[i]) i++;
    return i;
}

static void ntc_cpy(char *dst, const char *src, int max) {
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

static void ntc_juntar_caminho(char *dst, int max, const char *dir, const char *nome, const char *ext) {
    int p = 0, i = 0;
    while (dir[i] && p < max - 2) dst[p++] = dir[i++];
    if (p > 0 && dst[p - 1] != '/' && p < max - 2) dst[p++] = '/';
    i = 0;
    int tem_ponto = 0;
    while (nome[i] && p < max - 1) {
        if (nome[i] == '.') tem_ponto = 1;
        dst[p++] = nome[i++];
    }
    if (!tem_ponto && ext) {
        i = 0;
        while (ext[i] && p < max - 1) dst[p++] = ext[i++];
    }
    dst[p] = '\0';
}

static ntc_aba_t *ntc_atual(void) {
    if (ntc_aba_ativa < 0 || ntc_aba_ativa >= ntc_aba_count) return 0;
    return &ntc_abas[ntc_aba_ativa];
}

static int ntc_nova_aba(const char *nome) {
    if (ntc_aba_count >= NTC_ABAS_MAX) return -1;
    ntc_aba_t *a = &ntc_abas[ntc_aba_count];
    ntc_cpy(a->nome, nome, NTC_NOME_MAX);
    a->caminho[0] = '\0';
    a->buf[0] = '\0';
    a->len = 0;
    a->modificado = 0;
    a->aberta = 1;
    return ntc_aba_count++;
}

static int ntc_offset_linha(const char *buf, int len, int linha) {
    int off = 0, l = 0;
    while (off < len) {
        if (l == linha) return off;
        if (buf[off] == '\n') l++;
        off++;
    }
    return (l == linha) ? off : -1;
}

static int ntc_total_linhas(const char *buf, int len) {
    int l = 1;
    for (int i = 0; i < len; i++) if (buf[i] == '\n') l++;
    return l;
}

static int ntc_comp_linha(const char *buf, int len, int off) {
    int i = off;
    while (i < len && buf[i] != '\n') i++;
    return i - off;
}

static int ntc_cursor_offset(void) {
    ntc_aba_t *a = ntc_atual();
    if (!a) return 0;
    int off = ntc_offset_linha(a->buf, a->len, ntc_cursor_lin);
    if (off < 0) off = a->len;
    return off + ntc_cursor_col;
}

static void ntc_inserir(char c) {
    ntc_aba_t *a = ntc_atual();
    if (!a || a->len >= NTC_BUF_MAX - 1) return;

    int off = ntc_cursor_offset();
    if (off > a->len) off = a->len;

    for (int i = a->len; i > off; i--) a->buf[i] = a->buf[i - 1];
    a->buf[off] = c;
    a->len++;
    a->buf[a->len] = '\0';
    a->modificado = 1;

    if (c == '\n') {
        ntc_cursor_lin++;
        ntc_cursor_col = 0;
    } else {
        ntc_cursor_col++;
    }
}

static void ntc_backspace(void) {
    ntc_aba_t *a = ntc_atual();
    if (!a || a->len == 0) return;

    int off = ntc_cursor_offset();
    if (off == 0) return;

    if (ntc_cursor_col == 0 && ntc_cursor_lin > 0) {
        ntc_cursor_lin--;
        ntc_cursor_col = ntc_comp_linha(a->buf, a->len,
                                        ntc_offset_linha(a->buf, a->len, ntc_cursor_lin));
    } else {
        ntc_cursor_col--;
    }
    off--;

    for (int i = off; i < a->len - 1; i++) a->buf[i] = a->buf[i + 1];
    a->len--;
    a->buf[a->len] = '\0';
    a->modificado = 1;
}

static void ntc_mover_esq(void) {
    ntc_aba_t *a = ntc_atual();
    if (!a) return;
    if (ntc_cursor_col > 0) ntc_cursor_col--;
    else if (ntc_cursor_lin > 0) {
        ntc_cursor_lin--;
        ntc_cursor_col = ntc_comp_linha(a->buf, a->len,
                                        ntc_offset_linha(a->buf, a->len, ntc_cursor_lin));
    }
}

static void ntc_mover_dir(void) {
    ntc_aba_t *a = ntc_atual();
    if (!a) return;
    int off_lin = ntc_offset_linha(a->buf, a->len, ntc_cursor_lin);
    int comp = ntc_comp_linha(a->buf, a->len, off_lin);
    if (ntc_cursor_col < comp) ntc_cursor_col++;
    else if (ntc_cursor_lin < ntc_total_linhas(a->buf, a->len) - 1) {
        ntc_cursor_lin++;
        ntc_cursor_col = 0;
    }
}

static void ntc_mover_cima(void) {
    ntc_aba_t *a = ntc_atual();
    if (!a || ntc_cursor_lin <= 0) return;
    ntc_cursor_lin--;
    int off_lin = ntc_offset_linha(a->buf, a->len, ntc_cursor_lin);
    int comp = ntc_comp_linha(a->buf, a->len, off_lin);
    if (ntc_cursor_col > comp) ntc_cursor_col = comp;
}

static void ntc_mover_baixo(void) {
    ntc_aba_t *a = ntc_atual();
    if (!a) return;
    if (ntc_cursor_lin < ntc_total_linhas(a->buf, a->len) - 1) {
        ntc_cursor_lin++;
        int off_lin = ntc_offset_linha(a->buf, a->len, ntc_cursor_lin);
        int comp = ntc_comp_linha(a->buf, a->len, off_lin);
        if (ntc_cursor_col > comp) ntc_cursor_col = comp;
    }
}

static void ntc_mover_home(void) { ntc_cursor_col = 0; }

static void ntc_mover_end(void) {
    ntc_aba_t *a = ntc_atual();
    if (!a) return;
    int off_lin = ntc_offset_linha(a->buf, a->len, ntc_cursor_lin);
    ntc_cursor_col = ntc_comp_linha(a->buf, a->len, off_lin);
}

static void ntc_scroll_atualizar(int linhas_visiveis, int cols_visiveis) {
    if (linhas_visiveis < 1) linhas_visiveis = 1;
    if (cols_visiveis < 1) cols_visiveis = 1;
    if (ntc_cursor_lin < ntc_scroll_v) ntc_scroll_v = ntc_cursor_lin;
    if (ntc_cursor_lin >= ntc_scroll_v + linhas_visiveis)
        ntc_scroll_v = ntc_cursor_lin - linhas_visiveis + 1;
    if (ntc_cursor_col < ntc_scroll_h) ntc_scroll_h = ntc_cursor_col;
    if (ntc_cursor_col >= ntc_scroll_h + cols_visiveis)
        ntc_scroll_h = ntc_cursor_col - cols_visiveis + 1;
    if (ntc_scroll_v < 0) ntc_scroll_v = 0;
    if (ntc_scroll_h < 0) ntc_scroll_h = 0;
}

static void ntc_salvar(void) {
    ntc_aba_t *a = ntc_atual();
    if (!a) return;

    /* Se for aba nova sem caminho, define destino padrao em /fyd/usuario/documentos */
    if (a->caminho[0] == '\0') {
        const char *base_nome = (a->nome[0] != '\0') ? a->nome : "nota";
        ntc_juntar_caminho(a->caminho, NTC_CAMINHO_MAX, "/fyd/usuario/documentos", base_nome, ".txt");
        int k = ntc_len(a->caminho);
        while (k > 0 && a->caminho[k - 1] != '/') k--;
        ntc_cpy(a->nome, a->caminho + k, NTC_NOME_MAX);
    }

    if (fs_gravar_arquivo(a->caminho, a->buf, a->len) < 0) {
        ntc_cpy(ntc_mensagem, "ERRO ao gravar no disco", 64);
        return;
    }
    a->modificado = 0;
    ntc_cpy(ntc_mensagem, "Salvo em /fyd/usuario/documentos", 64);
}

static void ntc_abrir_caminho(const char *caminho) {
    /* Reutiliza aba se ja estiver aberta com mesmo caminho */
    for (int i = 0; i < ntc_aba_count; i++) {
        int j = 0;
        while (ntc_abas[i].caminho[j] && caminho[j] && ntc_abas[i].caminho[j] == caminho[j]) j++;
        if (ntc_abas[i].caminho[j] == '\0' && caminho[j] == '\0') {
            ntc_aba_ativa = i;
            ntc_cursor_lin = 0;
            ntc_cursor_col = 0;
            ntc_scroll_v = 0;
            ntc_scroll_h = 0;
            return;
        }
    }

    int idx = ntc_nova_aba("...");
    if (idx < 0) {
        ntc_cpy(ntc_mensagem, "Limite de abas", 64);
        return;
    }
    ntc_aba_t *a = &ntc_abas[idx];

    ntc_cpy(a->caminho, caminho, NTC_CAMINHO_MAX);
    int i = ntc_len(caminho), k = i;
    while (k > 0 && caminho[k - 1] != '/') k--;
    ntc_cpy(a->nome, caminho + k, NTC_NOME_MAX);

    if (fs_existe(caminho)) {
        int n = fs_ler_arquivo(caminho, a->buf, NTC_BUF_MAX - 1);
        a->len = (n > 0) ? n : 0;
        a->buf[a->len] = '\0';
        ntc_cpy(ntc_mensagem, "Arquivo carregado do FS", 64);
    } else {
        a->buf[0] = '\0';
        a->len = 0;
        ntc_cpy(ntc_mensagem, "Novo arquivo no caminho", 64);
    }
    ntc_aba_ativa = idx;
    ntc_cursor_lin = 0;
    ntc_cursor_col = 0;
    ntc_scroll_v = 0;
    ntc_scroll_h = 0;
}

static void ntc_geom(int *x, int *y, int *w, int *h) {
    if (ntc_win_estado == NTC_WIN_MAXIMIZADA) {
        *x = 0;
        *y = 34;
        *w = TELA_W;
        *h = TELA_H - 72;
        app_notepad.x = *x;
        app_notepad.y = *y;
        app_notepad.w = *w;
        app_notepad.h = *h;
    } else {
        *x = app_notepad.x;
        *y = app_notepad.y;
        *w = app_notepad.w;
        *h = app_notepad.h;
    }
}

#define NTC_BTN_FECHAR(_x,_w) ((_x) + (_w) - 24)
#define NTC_BTN_MAX(_x,_w)    ((_x) + (_w) - 46)
#define NTC_BTN_MIN(_x,_w)    ((_x) + (_w) - 68)

static void ntc_btn(int x, int y, int w, int h, uint32_t f, uint32_t b,
                    const char *l, int lx, int ly, uint32_t cl) {
    gui_retangulo(x, y, w, h, f);
    gui_borda(x, y, w, h, b);
    if (l) gui_texto(x + lx, y + ly, l, cl);
}

static void notes_abrir(void) {
    app_notepad.aberta = 1;
    if (ntc_win_estado == NTC_WIN_MINIMIZADA) {
        app_notepad.x = ntc_salvo_x;
        app_notepad.y = ntc_salvo_y;
        app_notepad.w = ntc_salvo_w;
        app_notepad.h = ntc_salvo_h;
        ntc_win_estado = NTC_WIN_NORMAL;
    }
    if (ntc_aba_count == 0) {
        int idx = ntc_nova_aba("nota1");
        ntc_aba_ativa = idx;
    }
}

void notepad_alternar_minimizar(void) {
    if (!app_notepad.aberta) {
        notes_abrir();
        return;
    }
    if (ntc_win_estado == NTC_WIN_MINIMIZADA) {
        app_notepad.x = ntc_salvo_x;
        app_notepad.y = ntc_salvo_y;
        app_notepad.w = ntc_salvo_w;
        app_notepad.h = ntc_salvo_h;
        ntc_win_estado = NTC_WIN_NORMAL;
    } else {
        if (ntc_win_estado == NTC_WIN_NORMAL) {
            ntc_salvo_x = app_notepad.x;
            ntc_salvo_y = app_notepad.y;
            ntc_salvo_w = app_notepad.w;
            ntc_salvo_h = app_notepad.h;
        }
        ntc_win_estado = NTC_WIN_MINIMIZADA;
    }
}

int notepad_esta_minimizado(void) {
    return (app_notepad.aberta && ntc_win_estado == NTC_WIN_MINIMIZADA);
}

/* Renderiza a janela completa do FydelNotes: barra, toolbar, abas, editor e status */
static void notes_desenhar(void) {
    /* Nao desenha se o aplicativo estiver fechado ou minimizado */
    if (!app_notepad.aberta) return;
    if (ntc_win_estado == NTC_WIN_MINIMIZADA) return;

    /* Obtem geometria atual da janela */
    int x, y, w, h;
    ntc_geom(&x, &y, &w, &h);

    /* Moldura externa e barra superior com controles da janela */
    gui_retangulo(x, y, w, h, NTC_PAINEL);
    gui_borda(x, y, w, h, NTC_ROXO);

    gui_retangulo(x + 2, y + 2, w - 4, 26, NTC_TOPO);
    gpu_desenhar_icone(icone_arquivo, x + 8, y + 6, 16, 16);
    gui_texto(x + 30, y + 7, "FydelNotes - Editor Nativo VFS", NTC_CIANO);

    ntc_btn(NTC_BTN_FECHAR(x, w), y + 4, 20, 20, NTC_VERMELHO, NTC_VERMELHO, "X", 6, 2, 0xFFFFFFFF);
    if (ntc_win_estado == NTC_WIN_MAXIMIZADA)
        ntc_btn(NTC_BTN_MAX(x, w), y + 4, 20, 20, NTC_ITEM_SEL, NTC_AMARELO, "r", 6, 2, NTC_AMARELO);
    else
        ntc_btn(NTC_BTN_MAX(x, w), y + 4, 20, 20, NTC_ITEM_SEL, NTC_VERDE, "+", 6, 2, NTC_VERDE);
    ntc_btn(NTC_BTN_MIN(x, w), y + 4, 20, 20, NTC_ITEM_SEL, NTC_SUAVE, "_", 6, 6, NTC_SUAVE);

    /* Barra de ferramentas (Novo, Abrir, Salvar) e mensagem de status temporaria */
    int tb_y = y + 34;
    ntc_btn(x + 10,  tb_y, 50, 24, NTC_ITEM_SEL, NTC_ROXO, "Novo",   8, 4, 0xFFFFFFFF);
    ntc_btn(x + 66,  tb_y, 54, 24, NTC_ITEM_SEL, NTC_ROXO, "Abrir",  8, 4, 0xFFFFFFFF);
    ntc_btn(x + 126, tb_y, 58, 24, NTC_ITEM_SEL, NTC_ROXO, "Salvar", 8, 4, 0xFFFFFFFF);
    gui_texto(x + 194, tb_y + 4, ntc_mensagem, NTC_VERDE);

    /* Faixa de abas abertas indicando documento ativo e modificacoes nao salvas */
    int aba_y = tb_y + 28;
    int aba_w = 104;
    for (int i = 0; i < ntc_aba_count; i++) {
        ntc_aba_t *a = &ntc_abas[i];
        int ax = x + 10 + i * (aba_w + 4);
        if (ax + aba_w > x + w - 10) break;

        uint32_t fundo = (i == ntc_aba_ativa) ? NTC_EDIT : NTC_TOPO;
        uint32_t borda = (i == ntc_aba_ativa) ? NTC_CIANO : 0xFF4C2889;

        ntc_btn(ax, aba_y, aba_w, 22, fundo, borda, 0, 0, 0, 0);
        char nome_vis[13];
        ntc_cpy(nome_vis, a->nome, 13);
        gui_texto(ax + 6, aba_y + 4, nome_vis, i == ntc_aba_ativa ? NTC_TEXTO : NTC_SUAVE);
        if (a->modificado) gui_texto(ax + aba_w - 12, aba_y + 4, "*", NTC_AMARELO);
    }

    /* Area principal de edicao com margem esquerda (gutter) de numeros de linha */
    int edit_x = x + 10;
    int edit_y = aba_y + 26;
    int edit_w = w - 20;
    int edit_h = h - (edit_y - y) - 24;

    gui_retangulo(edit_x, edit_y, edit_w, edit_h, NTC_EDIT);
    gui_borda(edit_x, edit_y, edit_w, edit_h, NTC_ROXO);

    ntc_aba_t *a = ntc_atual();
    if (!a) return;

    int gutter_w = 44;
    gui_retangulo(edit_x + 1, edit_y + 1, gutter_w, edit_h - 2, NTC_NUM_LINHA);

    /* Sincroniza rolagem horizontal/vertical com a area visivel do editor */
    int linhas_visiveis = (edit_h - 10) / NTC_LH;
    int cols_visiveis   = (edit_w - gutter_w - 20) / NTC_CW;

    ntc_scroll_atualizar(linhas_visiveis, cols_visiveis);

    int texto_x = edit_x + gutter_w + 8;
    int ty = edit_y + 6;

    /* Renderiza linhas visiveis, destaque da linha atual, texto e cursor */
    for (int vis = 0; vis < linhas_visiveis; vis++) {
        int linha = ntc_scroll_v + vis;
        int total = ntc_total_linhas(a->buf, a->len);
        if (linha >= total) break;

        int off_lin = ntc_offset_linha(a->buf, a->len, linha);
        int comp = ntc_comp_linha(a->buf, a->len, off_lin);

        if (linha == ntc_cursor_lin)
            gui_retangulo(edit_x + gutter_w + 2, ty - 2, edit_w - gutter_w - 4, NTC_LH, NTC_LINHA_CUR);

        /* Formata numero da linha alinhado a direita no gutter */
        char num[8];
        int ni = 0, v = linha + 1;
        char inv[8];
        int ii = 0;
        while (v) { inv[ii++] = '0' + (v % 10); v /= 10; }
        while (ii) num[ni++] = inv[--ii];
        num[ni] = '\0';
        gui_texto(edit_x + gutter_w - 6 - (ni * NTC_CW), ty, num,
                  linha == ntc_cursor_lin ? NTC_AMARELO : NTC_CIANO);

        /* Copia fatia visivel da linha substituindo tabulacoes por espaco */
        char linha_buf[160];
        int limite = comp - ntc_scroll_h;
        if (limite > 159) limite = 159;
        for (int c = 0; c < limite; c++) {
            char ch = a->buf[off_lin + ntc_scroll_h + c];
            linha_buf[c] = (ch == '\t') ? ' ' : ch;
        }
        linha_buf[limite > 0 ? limite : 0] = '\0';
        if (limite > 0) gui_texto(texto_x, ty, linha_buf, NTC_TEXTO);

        /* Desenha marcador do cursor na coluna ativa */
        if (linha == ntc_cursor_lin) {
            int cx = texto_x + (ntc_cursor_col - ntc_scroll_h) * NTC_CW;
            if (cx >= texto_x && cx < edit_x + edit_w - 4)
                gui_texto(cx, ty, "_", 0xFF7B2CBF);
        }

        ty += NTC_LH;
    }

    /* Barra de rolagem vertical proporcional quando houver mais linhas que a tela */
    int total_lin = ntc_total_linhas(a->buf, a->len);
    if (total_lin > linhas_visiveis) {
        int sb_x = edit_x + edit_w - 8;
        int sb_h = edit_h - 4;
        gui_retangulo(sb_x, edit_y + 2, 6, sb_h, NTC_TOPO);
        int prop = sb_h * linhas_visiveis / total_lin;
        if (prop < 8) prop = 8;
        int off = (sb_h - prop) * ntc_scroll_v / (total_lin - linhas_visiveis);
        gui_retangulo(sb_x, edit_y + 2 + off, 6, prop, NTC_ROXO);
    }

    /* Barra de status inferior com linha, coluna, tamanho em bytes e caminho do arquivo */
    gui_retangulo(x + 2, y + h - 20, w - 4, 18, NTC_TOPO);
    char st[112];
    int si = 0;
    const char *p1 = "Ln ";
    for (int i = 0; p1[i]; i++) st[si++] = p1[i];
    {
        int v = ntc_cursor_lin + 1;
        char inv[8];
        int ii = 0;
        while (v) { inv[ii++] = '0' + (v % 10); v /= 10; }
        while (ii) st[si++] = inv[--ii];
    }
    const char *p2 = " Col ";
    for (int i = 0; p2[i]; i++) st[si++] = p2[i];
    {
        int v = ntc_cursor_col + 1;
        char inv[8];
        int ii = 0;
        while (v) { inv[ii++] = '0' + (v % 10); v /= 10; }
        while (ii) st[si++] = inv[--ii];
    }
    const char *p3 = " | ";
    for (int i = 0; p3[i]; i++) st[si++] = p3[i];
    {
        int v = a->len;
        char inv[8];
        int ii = 0;
        if (!v) inv[ii++] = '0';
        while (v) { inv[ii++] = '0' + (v % 10); v /= 10; }
        while (ii) st[si++] = inv[--ii];
    }
    const char *p4 = " B";
    for (int i = 0; p4[i]; i++) st[si++] = p4[i];
    if (a->modificado) { st[si++] = ' '; st[si++] = '*'; }
    if (a->caminho[0]) {
        st[si++] = ' '; st[si++] = '|'; st[si++] = ' ';
        for (int i = 0; a->caminho[i] && si < 110; i++) st[si++] = a->caminho[i];
    }
    st[si] = '\0';
    gui_texto(x + 12, y + h - 18, st, NTC_VERDE);
}

/* Trata cliques relativos dentro da janela do FydelNotes (barra, toolbar, abas e texto) */
static void notes_on_click(int rel_x, int rel_y) {
    /* Ignora cliques enquanto a janela estiver minimizada */
    if (ntc_win_estado == NTC_WIN_MINIMIZADA) return;

    /* Obtem geometria atual da janela para calcular coordenadas relativas */
    int x, y, w, h;
    ntc_geom(&x, &y, &w, &h);

    /* Botoes da barra de titulo: fechar, maximizar/restaurar e minimizar */
    if (rel_y >= 2 && rel_y <= 28) {
        if (rel_x >= NTC_BTN_FECHAR(x, w) - x && rel_x <= NTC_BTN_FECHAR(x, w) - x + 20) {
            app_notepad.aberta = 0;
            ntc_win_estado = NTC_WIN_NORMAL;
            return;
        }
        if (rel_x >= NTC_BTN_MAX(x, w) - x && rel_x <= NTC_BTN_MAX(x, w) - x + 20) {
            if (ntc_win_estado == NTC_WIN_MAXIMIZADA) {
                /* Restaura geometria salva antes da maximizacao */
                app_notepad.x = ntc_salvo_x;
                app_notepad.y = ntc_salvo_y;
                app_notepad.w = ntc_salvo_w;
                app_notepad.h = ntc_salvo_h;
                ntc_win_estado = NTC_WIN_NORMAL;
            } else {
                /* Salva geometria atual e expande a janela na area util da tela */
                ntc_salvo_x = app_notepad.x;
                ntc_salvo_y = app_notepad.y;
                ntc_salvo_w = app_notepad.w;
                ntc_salvo_h = app_notepad.h;
                app_notepad.x = 0;
                app_notepad.y = 34;
                app_notepad.w = TELA_W;
                app_notepad.h = TELA_H - 72;
                ntc_win_estado = NTC_WIN_MAXIMIZADA;
            }
            return;
        }
        if (rel_x >= NTC_BTN_MIN(x, w) - x && rel_x <= NTC_BTN_MIN(x, w) - x + 20) {
            notepad_alternar_minimizar();
            return;
        }
        return;
    }

    int tb_y = 34;
    int aba_y = tb_y + 28;
    int aba_w = 104;

    /* Botoes da barra de ferramentas: nova aba, abrir configuracao padrao e salvar */
    if (rel_y >= tb_y && rel_y <= tb_y + 24) {
        if (rel_x >= 10 && rel_x <= 60) {
            char nome[16] = "nota";
            nome[4] = '0' + ((ntc_aba_count + 1) % 10);
            nome[5] = '\0';
            int idx = ntc_nova_aba(nome);
            if (idx >= 0) {
                ntc_aba_ativa = idx;
                ntc_cursor_lin = 0;
                ntc_cursor_col = 0;
                ntc_scroll_v = 0;
                ntc_scroll_h = 0;
                ntc_cpy(ntc_mensagem, "Novo documento", 64);
            } else {
                ntc_cpy(ntc_mensagem, "Limite de abas", 64);
            }
            return;
        }
        if (rel_x >= 66 && rel_x <= 120) {
            ntc_abrir_caminho("/fyd/config/sistema.fcfg");
            return;
        }
        if (rel_x >= 126 && rel_x <= 184) {
            ntc_salvar();
            return;
        }
        return;
    }

    /* Seleciona aba ativa e reseta cursor e rolagem para o inicio do documento */
    if (rel_y >= aba_y && rel_y <= aba_y + 22) {
        int idx = (rel_x - 10) / (aba_w + 4);
        if (idx >= 0 && idx < ntc_aba_count) {
            ntc_aba_ativa = idx;
            ntc_cursor_lin = 0;
            ntc_cursor_col = 0;
            ntc_scroll_v = 0;
            ntc_scroll_h = 0;
        }
        return;
    }

    /* Posiciona o cursor de texto ao clicar dentro da area de edicao e ajusta rolagem */
    int edit_y = aba_y + 26;
    int edit_w = w - 20;
    int edit_h = h - edit_y - 24;
    if (rel_x >= 54 && rel_y >= edit_y && rel_y < edit_y + edit_h) {
        ntc_aba_t *a = ntc_atual();
        if (!a) return;

        int linhas_visiveis = (edit_h - 10) / NTC_LH;
        int cols_visiveis   = (edit_w - 52 - 20) / NTC_CW;

        /* Calcula linha alvo limitada ao intervalo valido do buffer */
        int nova_lin = ntc_scroll_v + (rel_y - edit_y - 6) / NTC_LH;
        int total = ntc_total_linhas(a->buf, a->len);
        if (nova_lin >= total) nova_lin = total - 1;
        if (nova_lin < 0) nova_lin = 0;
        ntc_cursor_lin = nova_lin;

        /* Calcula coluna alvo limitada ao comprimento da linha selecionada */
        int off_lin = ntc_offset_linha(a->buf, a->len, ntc_cursor_lin);
        int comp = ntc_comp_linha(a->buf, a->len, off_lin);
        int nova_col = ntc_scroll_h + (rel_x - 54) / NTC_CW;
        if (nova_col > comp) nova_col = comp;
        if (nova_col < 0) nova_col = 0;
        ntc_cursor_col = nova_col;

        ntc_scroll_atualizar(linhas_visiveis, cols_visiveis);
    }
}

static void notes_on_key(char tecla) {
    if (ntc_win_estado == NTC_WIN_MINIMIZADA) return;

    ntc_aba_t *a = ntc_atual();
    if (!a) return;

    if (tecla == 0) return;

    if (tecla == 17) { ntc_mover_cima();  return; }
    if (tecla == 18) { ntc_mover_baixo(); return; }
    if (tecla == 19) { ntc_mover_esq();   return; }
    if (tecla == 20) { ntc_mover_dir();   return; }
    if (tecla == 1)  { ntc_mover_home();  return; }
    if (tecla == 2)  { ntc_mover_end();   return; }

    if (tecla == '\n' || tecla == '\r') { ntc_inserir('\n'); return; }
    if (tecla == '\b') { ntc_backspace(); return; }
    if (tecla == '\t') {
        ntc_inserir(' ');
        ntc_inserir(' ');
        ntc_inserir(' ');
        ntc_inserir(' ');
        return;
    }

    if (tecla == 3) { ntc_salvar(); return; }

    if (tecla >= 32 && tecla <= 126) { ntc_inserir(tecla); return; }
}

FydelisApp app_notepad = {
    .aberta   = 0,
    .x        = 120,
    .y        = 70,
    .w        = 640,
    .h        = 420,
    .abrir    = notes_abrir,
    .desenhar = notes_desenhar,
    .on_click = notes_on_click,
    .on_key   = notes_on_key
};
