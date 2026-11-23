#include "../apps.h"

// Paleta visual FydelisTech OS
#define CALC_BG         0xFF140B29
#define CALC_VISOR_BG   0xFF090611
#define CALC_BTN_NUM    0xFF2A1454
#define CALC_BTN_OP     0xFF5A189A
#define CALC_BTN_EQ     0xFF00B4D8
#define CALC_BTN_CLR    0xFF9D0208
#define CALC_BORDA      0xFF9D4EDD
#define CALC_TEXTO      0xFFF0E6FF
#define CALC_TEXTO_CIANO 0xFF00FFFF

static int64_t calc_acumulador = 0;
static int64_t calc_atual      = 0;
static char    calc_operador   = 0;
static int     calc_novo_num   = 1;
static int     calc_erro_div0  = 0;

static const char *calc_labels[4][4] = {
    { "7", "8", "9", "/" },
    { "4", "5", "6", "*" },
    { "1", "2", "3", "-" },
    { "C", "0", "=", "+" }
};

static void calc_int_to_str(int64_t val, char *buf) {
    if (calc_erro_div0) {
        const char *err = "Erro: Div/0";
        int i = 0;
        while (err[i]) { buf[i] = err[i]; i++; }
        buf[i] = '\0';
        return;
    }

    char tmp[24];
    int i = 0, j = 0;
    int negativo = 0;

    if (val == 0) {
        buf[0] = '0';
        buf[1] = '\0';
        return;
    }

    if (val < 0) {
        negativo = 1;
        val = -val;
    }

    while (val > 0 && i < 22) {
        tmp[i++] = (char)('0' + (val % 10));
        val /= 10;
    }

    if (negativo) buf[j++] = '-';
    while (i > 0) buf[j++] = tmp[--i];
    buf[j] = '\0';
}

static void calc_executar_operacao(void) {
    if (calc_operador == '+') {
        calc_acumulador += calc_atual;
    } else if (calc_operador == '-') {
        calc_acumulador -= calc_atual;
    } else if (calc_operador == '*') {
        calc_acumulador *= calc_atual;
    } else if (calc_operador == '/') {
        if (calc_atual == 0) {
            calc_erro_div0 = 1;
            calc_acumulador = 0;
        } else {
            calc_acumulador /= calc_atual;
        }
    } else {
        calc_acumulador = calc_atual;
    }
    calc_atual = calc_acumulador;
}

static void calc_processar_tecla(char c) {
    if (c == 'c' || c == 'C' || c == 27) { // ESC ou C limpa tudo
        calc_acumulador = 0;
        calc_atual      = 0;
        calc_operador   = 0;
        calc_novo_num   = 1;
        calc_erro_div0  = 0;
        return;
    }

    if (calc_erro_div0) return;

    if (c >= '0' && c <= '9') {
        int digito = c - '0';
        if (calc_novo_num) {
            calc_atual = digito;
            calc_novo_num = 0;
        } else {
            if (calc_atual < 999999999999LL && calc_atual > -999999999999LL) {
                calc_atual = calc_atual * 10 + digito;
            }
        }
        return;
    }

    if (c == '\b') { // Backspace apaga último dígito
        if (!calc_novo_num) {
            calc_atual /= 10;
        }
        return;
    }

    if (c == '+' || c == '-' || c == '*' || c == '/') {
        if (!calc_novo_num && calc_operador != 0) {
            calc_executar_operacao();
        } else {
            calc_acumulador = calc_atual;
        }
        calc_operador = c;
        calc_novo_num = 1;
        return;
    }

    if (c == '=' || c == '\n' || c == '\r') {
        if (calc_operador != 0) {
            calc_executar_operacao();
            calc_operador = 0;
            calc_novo_num = 1;
        }
    }
}

static void calc_abrir(void) {
    app_calculadora.aberta = 1;
}

static void calc_desenhar(void) {
    if (!app_calculadora.aberta) return;

    int wx = app_calculadora.x;
    int wy = app_calculadora.y;
    int ww = app_calculadora.w;
    int wh = app_calculadora.h;

    // Fundo da janela e moldura neon
    gui_retangulo(wx, wy, ww, wh, CALC_BG);
    gui_borda(wx, wy, ww, wh, CALC_BORDA);

    // Barra de título (26px)
    gui_retangulo(wx + 1, wy + 1, ww - 2, 26, 0xFF2A1050);
    gui_texto(wx + 10, wy + 7, "Calculadora - Acessorios", CALC_TEXTO);

    // Botão fechar [X]
    gui_retangulo(wx + ww - 24, wy + 3, 20, 20, CALC_BTN_CLR);
    gui_texto(wx + ww - 18, wy + 7, "X", CALC_TEXTO);

    // Visor numérico
    int vx = wx + 12;
    int vy = wy + 36;
    int vw = ww - 24;
    int vh = 42;
    gui_retangulo(vx, vy, vw, vh, CALC_VISOR_BG);
    gui_borda(vx, vy, vw, vh, CALC_BORDA);

    // Indicador da operação pendente no canto esquerdo do visor
    if (calc_operador != 0) {
        char op_str[2] = { calc_operador, '\0' };
        gui_texto(vx + 8, vy + 14, op_str, CALC_TEXTO_CIANO);
    }

    // Número atual
    char num_str[28];
    calc_int_to_str(calc_atual, num_str);
    gui_texto(vx + 28, vy + 14, num_str, CALC_TEXTO);

    // Grade 4x4 de botões
    int grid_x = wx + 12;
    int grid_y = wy + 88;
    int btn_w  = 52;
    int btn_h  = 38;
    int gap    = 6;

    for (int row = 0; row < 4; row++) {
        for (int col = 0; col < 4; col++) {
            int bx = grid_x + col * (btn_w + gap);
            int by = grid_y + row * (btn_h + gap);
            char lbl = calc_labels[row][col][0];

            uint32_t cor_btn = CALC_BTN_NUM;
            if (lbl == 'C') cor_btn = CALC_BTN_CLR;
            else if (lbl == '=') cor_btn = CALC_BTN_EQ;
            else if (col == 3) cor_btn = CALC_BTN_OP;

            gui_retangulo(bx, by, btn_w, btn_h, cor_btn);
            gui_borda(bx, by, btn_w, btn_h, CALC_BORDA);
            gui_texto(bx + 21, by + 13, calc_labels[row][col], CALC_TEXTO);
        }
    }
}

static void calc_on_click(int rel_x, int rel_y) {
    if (!app_calculadora.aberta) return;

    // Clique no botão fechar [X]
    if (rel_x >= app_calculadora.w - 24 && rel_x <= app_calculadora.w - 4 &&
        rel_y >= 3 && rel_y <= 23) {
        app_calculadora.aberta = 0;
        return;
    }

    // Verifica clique na grade 4x4
    int grid_x = 12;
    int grid_y = 88;
    int btn_w  = 52;
    int btn_h  = 38;
    int gap    = 6;

    for (int row = 0; row < 4; row++) {
        for (int col = 0; col < 4; col++) {
            int bx = grid_x + col * (btn_w + gap);
            int by = grid_y + row * (btn_h + gap);

            if (rel_x >= bx && rel_x <= bx + btn_w &&
                rel_y >= by && rel_y <= by + btn_h) {
                calc_processar_tecla(calc_labels[row][col][0]);
                return;
            }
        }
    }
}

static void calc_on_key(char tecla) {
    if (!app_calculadora.aberta) return;
    calc_processar_tecla(tecla);
}

FydelisApp app_calculadora = {
    .nome      = "Calculadora",
    .categoria = CAT_ACESSORIOS,
    .aberta    = 0,
    .x         = 340,
    .y         = 140,
    .w         = 250,
    .h         = 270,
    .abrir     = calc_abrir,
    .desenhar  = calc_desenhar,
    .on_click  = calc_on_click,
    .on_key    = calc_on_key
};
