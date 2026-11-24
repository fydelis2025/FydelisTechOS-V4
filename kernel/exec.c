/* ============================================================================
- FydelisTech OS v4.2 — Motor Gráfico, Window Manager & Desktop Interativo
- Arquitetura: x86_64 Freestanding | VESA Linear Framebuffer 32-bit + PS/2
- Otimizado: Wallpapers via Disco ATA PIO28, Cursor Sincronizado e Polling PS/2
- ============================================================================ */
#include "../apps/apps.h"
#include "../include/fyd_formatos.h"
#include "../include/fydlog.h"
#include "../include/fyd_auth.h"
#include "syscalls/gpu.h"
#include "icones.h"
#include "fontes_ui.h"
#include "fydelis_core.h"
#include <stdint.h>
#include <stddef.h>
#include <string.h>

/* Paleta Cyberpunk Purple & Neon — FydelisTech OS */
#undef COR_ROXO_NEON
#undef COR_CIANO_NEON
#define COR_FUNDO_ESCURO    0xFF120826
#define COR_PAINEL          0xFF1E0E3D
#define COR_PAINEL_SEC      0xFF160A2E
#define COR_CARD            0xFF281352
#define COR_INPUT_BG        0xFF160A2E
#define COR_HOVER           0xFF3B1D75
#define COR_ROXO_NEON       0xFF9D4EDD
#define COR_ROXO_CLARO      0xFFC77DFF
#define COR_CIANO_NEON      0xFF00F5D4
#define COR_VERDE_NEON      0xFF00FF9C
#define COR_VERMELHO_ALERTA 0xFFFF4D6D
#define COR_TEXTO_BRANCO    0xFFF8FAFC
#define COR_TEXTO_SUAVE     0xFFCBD5E1
#define COR_BORDA_SUTIL     0xFF4C2889

/* ============================================================================
 * INTEGRAÇÃO DRIVER WI-FI & DHCP (Símbolos exportados pelo Assembly/Drivers)
 * ============================================================================ */
#define MAX_REDES_WIFI 32

typedef struct __attribute__((packed)) {
    char    ssid[33];         /* Offset 0..32 */
    uint8_t canal;            /* Offset 33 */
    uint8_t potencia;         /* Offset 34 */
    uint8_t seguranca;        /* Offset 35: 0 = Aberta, 1 = WPA2 */
    uint8_t bssid[6];         /* Offset 36..41 */
    uint8_t reservado[22];    /* Offset 42..63 -> Total = 64 bytes */
} WifiRede;

#define FYD_PATH_USUARIOS   "/fyd/config/usuarios.fydb"
#define FYD_DIR_CONFIG      "/fyd/config"
#define FYD_MAGIC_USUARIOS  0x46594455U /* "FYDU" */
#define FYD_MAX_USUARIOS    32
#define FYD_ADM_USER        "adm"
#define FYD_ADM_PASS        "fydelis2026"
#define FYD_ADM_NIVEL       100

typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint16_t versao;
    uint16_t max_usuarios;
    uint32_t total_ativos;
    uint8_t  reservado[20];
} FydbHeaderUsuarios;

typedef struct {
    char usuario[24];
    uint8_t salt[16];
    uint8_t hash_senha[32];
    uint8_t segredo_cifrado[32];
    uint32_t nivel;
    uint32_t ativo;
} FydRegistroUsuario;

static FydbHeaderUsuarios g_fydb_hdr;
static FydRegistroUsuario g_fydb_tabela[FYD_MAX_USUARIOS];
static int g_fydb_disco_ok = 0;
static uint64_t g_fydb_prng_estado = 0x465944454C495334ULL;
static int g_fydperm_nivel_atual = FYD_PERM_CONVIDADO;
static char g_fydperm_usuario_atual[24] = {0};

static FydSessaoAtiva g_sessao = {0};
static int g_auth_pronto = 0;

/* Funções externas dos módulos (ajuste conforme os nomes reais nos seus headers) */
extern int fydb_inicializar(void);
extern int fydb_contar_usuarios(void);
extern int fydb_buscar_usuario(const char *usuario, FydRegistroUsuario *out_reg);
extern int fydb_salvar_usuario(const FydRegistroUsuario *reg);

extern void fycrypto_aleatorio(uint8_t *buf, size_t len);
extern void fycrypto_derivar_hash(const char *senha, const uint8_t *salt, size_t salt_len,
                                  uint8_t *out_hash, size_t hash_len);
extern int  fycrypto_comparar_constante(const uint8_t *a, const uint8_t *b, size_t len);

extern int  fydcipher_cifrar_bloco(const uint8_t *in, size_t len, uint8_t *out);

extern void fydperm_definir_sessao(const char *usuario, int nivel);
extern int  fydperm_pode_cadastrar_usuario(void);


extern WifiRede wifi_scan_lista[MAX_REDES_WIFI];

extern int      wifi_detectar_placa(void);
extern int      wifi_inicializar(void);
extern int      sys_wifi_scan(void);
extern int      sys_wifi_conectar(const char *ssid);
extern void     sys_wifi_desconectar(void);
extern uint64_t wifi_ler_status(void);
extern void     dhcp_cliente_iniciar(void);

/* ============================================================================
 * POPUP DE REDES WI-FI (SYSTRAY ICON)
 * ============================================================================ */
#define WIFI_POP_W          280
#define WIFI_POP_H          260
#define WIFI_MAX_VISIVEIS   6

/* Paleta Cyberpunk Purple & Neon */
#define WIFI_COR_FUNDO      0xFF1A0B36
#define WIFI_COR_BARRA      0xFF281352
#define WIFI_COR_ITEM       0xFF120726
#define WIFI_COR_ITEM_SEL   0xFF3B1D75
#define WIFI_COR_BORDA      0xFF9D4EDD
#define WIFI_COR_CIANO      0xFF00F5D4
#define WIFI_COR_VERDE      0xFF00FF9C
#define WIFI_COR_AMARELO    0xFFFFD166
#define WIFI_COR_VERMELHO   0xFFFF4D6D
#define WIFI_COR_TEXTO      0xFFF8FAFC
#define WIFI_COR_SUAVE      0xFF94A3B8

static int  wifi_popup_aberto = 0;
static int  wifi_indice_selecionado = -1;
static char wifi_status_msg[48] = "Pronto para escanear";

/* Variáveis exportadas pelo driver VESA (vesafb.asm) */
extern uint32_t *fb_base;
extern uint32_t  fb_largura;
extern uint32_t  fb_altura;
extern uint32_t  fb_pitch;

/* Drivers Assembly (mouse.asm, fb_server.asm, rede_bridge.asm, timer.asm) */
extern uint64_t mouse_inicializar(void);
extern uint64_t ws_inicializar(void);
extern void     ws_atualizar_cursor(void);
extern void     cursor_restaurar_fundo(void);
extern void     cursor_desenhar_novo(void);
extern uint64_t rede_ler_status_link(void);
extern uint64_t timer_ler_ticks(void);
extern uint64_t bt_detectar_placa(void);
extern uint64_t bt_inicializar(void);
extern uint64_t bt_ler_status(void);
extern void     audio_init(void);
extern uint64_t audio_ler_status(void);
extern uint64_t detectar_disco(uint64_t numero_disco);
extern uint64_t obter_tamanho_disco(void);

extern const char *fs_ler_config_padrao(void);
extern FydelisApp app_visualizador_logs;
extern FydelisApp app_explorer;
extern FydelisApp app_browser;
extern FydelisApp app_notepad;

extern void notepad_alternar_minimizar(void);
extern int notepad_esta_minimizado(void);

extern void dhcp_cliente_iniciar(void);
extern void dhcp_cliente_processar(void);
extern uint32_t dhcp_ler_status(void);
extern const char *rede_ler_ip(void);

extern void explorer_alternar_minimizar(void);
extern int  explorer_esta_minimizado(void);
extern void browser_alternar_minimizar(void);
extern int  browser_esta_minimizado(void);



enum {
    MODO_JANELA_SISTEMA  = 1,
    MODO_JANELA_APPS     = 3,
    MODO_JANELA_CONFIG   = 4
};

typedef struct {
    uint8_t seg;
    uint8_t min;
    uint8_t hora;
    uint8_t dia;
    uint8_t mes;
    uint8_t ano;
} RtcDataHora;

typedef struct {
    const char     *rotulo;
    const uint32_t *icone;
    int             coluna;
    int             acao_id;
} ItemMenuIniciar;

typedef struct {
    char     cpu_vendor[16];
    int      cpu_uso_pct;
    uint32_t ram_total_mb;
    uint32_t ram_usada_mb;
    uint32_t disco_total_mb;
    int      disco_online;
} TelemetriaSistema;

enum {
    PAINEL_ABA_SESSAO  = 0,
    PAINEL_ABA_TECLADO = 1,
    PAINEL_ABA_IDIOMA  = 2
};

enum {
    FYD_LAYOUT_TECLADO_US    = 0,
    FYD_LAYOUT_TECLADO_ABNT2 = 1
};

enum {
    IDIOMA_PT_BR = 0,
    IDIOMA_EN_US = 1
};



static inline uint64_t ler_tsc(void) {
    uint32_t lo, hi;
    __asm__ volatile ("rdtsc" : "=a"(lo), "=d"(hi));
    return ((uint64_t)hi << 32) | lo;
}

/* Evita travamento quando PIC legado esta mascarado (0xFF) sem IRQs ativas */
static inline void descansar_cpu_hlt(void) {
    __asm__ volatile ("pause");
}

static const ItemMenuIniciar itens_menu[] = {
    { "Explorer (/fyd)", icone_pasta_aberta,  0, 1 },
    { "FydelNotes",      icone_arquivo,       0, 11 },
    { "FydelisBrowser",  icone_ethernet,      0, 10 },
    { "Aplicativos",     icone_iniciar,       0, 2 },
    { "FydelTerm",       icone_terminal,      0, 3 },
    { "Agenda",          icone_agenda,        0, 4 },
    { "Calculadora",     icone_config,        0, 8 },
    { "Painel Sistema",  icone_sistema,       1, 5 },
    { "Configuracoes",   icone_config,        1, 6 },
    { "Rede & Wi-Fi",    icone_ethernet,      1, 7 },
    { "Logs (.flog)",    icone_terminal,      1, 9 },
};
#define TOTAL_ITENS_MENU (int)(sizeof(itens_menu) / sizeof(itens_menu[0]))

/* ============================================================================
- RENDERIZAÇÃO DIRETA NA VRAM COM VSYNC
- ============================================================================ */
extern void fb_sincronizar_vsync(void);

static void backbuffer_iniciar_frame(void) {
    fb_sincronizar_vsync();
}

static void backbuffer_apresentar_frame(int L, int A) {
    (void)L;
    (void)A;
}

/* ============================================================================
- FONTE BITMAP 8x16 COMPLETA (ASCII 32..126)
- ============================================================================ */
static const uint8_t fonte_8x16[95][16] = {
    {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00}, /* 32 ' ' */
    {0x00,0x00,0x18,0x3C,0x3C,0x3C,0x18,0x18,0x18,0x00,0x18,0x18,0x00,0x00,0x00,0x00}, /* 33 '!' */
    {0x00,0x66,0x66,0x66,0x24,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00}, /* 34 '"' */
    {0x00,0x00,0x00,0x6C,0x6C,0xFE,0x6C,0x6C,0x6C,0xFE,0x6C,0x6C,0x00,0x00,0x00,0x00}, /* 35 '#' */
    {0x00,0x18,0x18,0x7C,0xC6,0xC2,0xC0,0x7C,0x06,0x86,0xC6,0x7C,0x18,0x18,0x00,0x00}, /* 36 '$' */
    {0x00,0x00,0x00,0x00,0xC2,0xC6,0x0C,0x18,0x30,0x60,0xC6,0x86,0x00,0x00,0x00,0x00}, /* 37 '%' */
    {0x00,0x00,0x38,0x6C,0x6C,0x38,0x76,0xDC,0xCC,0xCC,0xCC,0x76,0x00,0x00,0x00,0x00}, /* 38 '&' */
    {0x00,0x30,0x30,0x30,0x60,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00}, /* 39 ''' */
    {0x00,0x00,0x0C,0x18,0x30,0x30,0x30,0x30,0x30,0x30,0x18,0x0C,0x00,0x00,0x00,0x00}, /* 40 '(' */
    {0x00,0x00,0x30,0x18,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x18,0x30,0x00,0x00,0x00,0x00}, /* 41 ')' */
    {0x00,0x00,0x00,0x00,0x66,0x3C,0xFF,0x3C,0x66,0x00,0x00,0x00,0x00,0x00,0x00,0x00}, /* 42 '*' */
    {0x00,0x00,0x00,0x00,0x18,0x18,0x7E,0x18,0x18,0x00,0x00,0x00,0x00,0x00,0x00,0x00}, /* 43 '+' */
    {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x18,0x30,0x00,0x00}, /* 44 ',' */
    {0x00,0x00,0x00,0x00,0x00,0x00,0xFE,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00}, /* 45 '-' */
    {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x00,0x00,0x00,0x00}, /* 46 '.' */
    {0x00,0x00,0x02,0x06,0x0C,0x18,0x30,0x60,0xC0,0x80,0x00,0x00,0x00,0x00,0x00,0x00}, /* 47 '/' */
    {0x00,0x00,0x7C,0xC6,0xCE,0xDE,0xF6,0xE6,0xC6,0xC6,0x7C,0x00,0x00,0x00,0x00,0x00}, /* 48 '0' */
    {0x00,0x00,0x18,0x38,0x78,0x18,0x18,0x18,0x18,0x18,0x7E,0x00,0x00,0x00,0x00,0x00}, /* 49 '1' */
    {0x00,0x00,0x7C,0xC6,0x06,0x0C,0x18,0x30,0x60,0xC6,0xFE,0x00,0x00,0x00,0x00,0x00}, /* 50 '2' */
    {0x00,0x00,0x7C,0xC6,0x06,0x06,0x3C,0x06,0x06,0xC6,0x7C,0x00,0x00,0x00,0x00,0x00}, /* 51 '3' */
    {0x00,0x00,0x0C,0x1C,0x3C,0x6C,0xCC,0xFE,0x0C,0x0C,0x1E,0x00,0x00,0x00,0x00,0x00}, /* 52 '4' */
    {0x00,0x00,0xFE,0xC0,0xC0,0xC0,0xFC,0x06,0x06,0xC6,0x7C,0x00,0x00,0x00,0x00,0x00}, /* 53 '5' */
    {0x00,0x00,0x38,0x60,0xC0,0xC0,0xFC,0xC6,0xC6,0xC6,0x7C,0x00,0x00,0x00,0x00,0x00}, /* 54 '6' */
    {0x00,0x00,0xFE,0xC6,0x06,0x0C,0x18,0x30,0x30,0x30,0x30,0x00,0x00,0x00,0x00,0x00}, /* 55 '7' */
    {0x00,0x00,0x7C,0xC6,0xC6,0xC6,0x7C,0xC6,0xC6,0xC6,0x7C,0x00,0x00,0x00,0x00,0x00}, /* 56 '8' */
    {0x00,0x00,0x7C,0xC6,0xC6,0xC6,0x7E,0x06,0x06,0x0C,0x78,0x00,0x00,0x00,0x00,0x00}, /* 57 '9' */
    {0x00,0x00,0x00,0x00,0x18,0x18,0x00,0x00,0x00,0x18,0x18,0x00,0x00,0x00,0x00,0x00}, /* 58 ':' */
    {0x00,0x00,0x00,0x00,0x18,0x18,0x00,0x00,0x00,0x18,0x18,0x30,0x00,0x00,0x00,0x00}, /* 59 ';' */
    {0x00,0x00,0x00,0x06,0x0C,0x18,0x30,0x60,0x30,0x18,0x0C,0x06,0x00,0x00,0x00,0x00}, /* 60 '<' */
    {0x00,0x00,0x00,0x00,0x00,0x7E,0x00,0x00,0x7E,0x00,0x00,0x00,0x00,0x00,0x00,0x00}, /* 61 '=' */
    {0x00,0x00,0x00,0x60,0x30,0x18,0x0C,0x06,0x0C,0x18,0x30,0x60,0x00,0x00,0x00,0x00}, /* 62 '>' */
    {0x00,0x00,0x7C,0xC6,0xC6,0x0C,0x18,0x18,0x18,0x00,0x18,0x18,0x00,0x00,0x00,0x00}, /* 63 '?' */
    {0x00,0x00,0x7C,0xC6,0xC6,0xDE,0xDE,0xDE,0xDC,0xC0,0x7C,0x00,0x00,0x00,0x00,0x00}, /* 64 '@' */
    {0x00,0x00,0x10,0x38,0x6C,0xC6,0xC6,0xFE,0xC6,0xC6,0xC6,0x00,0x00,0x00,0x00,0x00}, /* 65 'A' */
    {0x00,0x00,0xFC,0x66,0x66,0x66,0x7C,0x66,0x66,0x66,0xFC,0x00,0x00,0x00,0x00,0x00}, /* 66 'B' */
    {0x00,0x00,0x3C,0x66,0xC2,0xC0,0xC0,0xC0,0xC2,0x66,0x3C,0x00,0x00,0x00,0x00,0x00}, /* 67 'C' */
    {0x00,0x00,0xF8,0x6C,0x66,0x66,0x66,0x66,0x66,0x6C,0xF8,0x00,0x00,0x00,0x00,0x00}, /* 68 'D' */
    {0x00,0x00,0xFE,0x66,0x62,0x68,0x78,0x68,0x62,0x66,0xFE,0x00,0x00,0x00,0x00,0x00}, /* 69 'E' */
    {0x00,0x00,0xFE,0x66,0x62,0x68,0x78,0x68,0x60,0x60,0xF0,0x00,0x00,0x00,0x00,0x00}, /* 70 'F' */
    {0x00,0x00,0x3C,0x66,0xC2,0xC0,0xC0,0xDE,0xC6,0x66,0x3A,0x00,0x00,0x00,0x00,0x00}, /* 71 'G' */
    {0x00,0x00,0xC6,0xC6,0xC6,0xC6,0xFE,0xC6,0xC6,0xC6,0xC6,0x00,0x00,0x00,0x00,0x00}, /* 72 'H' */
    {0x00,0x00,0x3C,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x3C,0x00,0x00,0x00,0x00,0x00}, /* 73 'I' */
    {0x00,0x00,0x1E,0x0C,0x0C,0x0C,0x0C,0x0C,0xCC,0xCC,0x78,0x00,0x00,0x00,0x00,0x00}, /* 74 'J' */
    {0x00,0x00,0xE6,0x66,0x6C,0x6C,0x78,0x6C,0x6C,0x66,0xE6,0x00,0x00,0x00,0x00,0x00}, /* 75 'K' */
    {0x00,0x00,0xF0,0x60,0x60,0x60,0x60,0x60,0x62,0x66,0xFE,0x00,0x00,0x00,0x00,0x00}, /* 76 'L' */
    {0x00,0x00,0xC6,0xEE,0xFE,0xFE,0xD6,0xC6,0xC6,0xC6,0xC6,0x00,0x00,0x00,0x00,0x00}, /* 77 'M' */
    {0x00,0x00,0xC6,0xE6,0xF6,0xFE,0xDE,0xCE,0xC6,0xC6,0xC6,0x00,0x00,0x00,0x00,0x00}, /* 78 'N' */
    {0x00,0x00,0x7C,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0x7C,0x00,0x00,0x00,0x00,0x00}, /* 79 'O' */
    {0x00,0x00,0xFC,0x66,0x66,0x66,0x7C,0x60,0x60,0x60,0xF0,0x00,0x00,0x00,0x00,0x00}, /* 80 'P' */
    {0x00,0x00,0x7C,0xC6,0xC6,0xC6,0xC6,0xC6,0xD6,0xDE,0x7C,0x0E,0x00,0x00,0x00,0x00}, /* 81 'Q' */
    {0x00,0x00,0xFC,0x66,0x66,0x66,0x7C,0x6C,0x66,0x66,0xE6,0x00,0x00,0x00,0x00,0x00}, /* 82 'R' */
    {0x00,0x00,0x7C,0xC6,0xC6,0x60,0x38,0x0C,0xC6,0xC6,0x7C,0x00,0x00,0x00,0x00,0x00}, /* 83 'S' */
    {0x00,0x00,0x7E,0x7E,0x5A,0x18,0x18,0x18,0x18,0x18,0x3C,0x00,0x00,0x00,0x00,0x00}, /* 84 'T' */
    {0x00,0x00,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0x7C,0x00,0x00,0x00,0x00,0x00}, /* 85 'U' */
    {0x00,0x00,0xC6,0xC6,0xC6,0xC6,0xC6,0xC6,0x6C,0x38,0x10,0x00,0x00,0x00,0x00,0x00}, /* 86 'V' */
    {0x00,0x00,0xC6,0xC6,0xC6,0xC6,0xD6,0xFE,0xFE,0x6C,0x44,0x00,0x00,0x00,0x00,0x00}, /* 87 'W' */
    {0x00,0x00,0xC6,0xC6,0x6C,0x38,0x38,0x6C,0xC6,0xC6,0xC6,0x00,0x00,0x00,0x00,0x00}, /* 88 'X' */
    {0x00,0x00,0x66,0x66,0x66,0x66,0x3C,0x18,0x18,0x18,0x3C,0x00,0x00,0x00,0x00,0x00}, /* 89 'Y' */
    {0x00,0x00,0xFE,0xC6,0x8C,0x18,0x30,0x60,0xC2,0xC6,0xFE,0x00,0x00,0x00,0x00,0x00}, /* 90 'Z' */
    {0x00,0x00,0x3C,0x30,0x30,0x30,0x30,0x30,0x30,0x30,0x3C,0x00,0x00,0x00,0x00,0x00}, /* 91 '[' */
    {0x00,0x00,0x80,0xC0,0x60,0x30,0x18,0x0C,0x06,0x02,0x00,0x00,0x00,0x00,0x00,0x00}, /* 92 '\' */
    {0x00,0x00,0x3C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C,0x3C,0x00,0x00,0x00,0x00,0x00}, /* 93 ']' */
    {0x00,0x10,0x38,0x6C,0xC6,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00}, /* 94 '^' */
    {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xFF,0x00,0x00,0x00}, /* 95 '_' */
    {0x00,0x30,0x18,0x0C,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00}, /* 96 '`' */
    {0x00,0x00,0x00,0x00,0x00,0x78,0x0C,0x7C,0xCC,0xCC,0x76,0x00,0x00,0x00,0x00,0x00}, /* 97 'a' */
    {0x00,0x00,0xE0,0x60,0x60,0x78,0x6C,0x66,0x66,0x66,0xDC,0x00,0x00,0x00,0x00,0x00}, /* 98 'b' */
    {0x00,0x00,0x00,0x00,0x00,0x7C,0xC6,0xC0,0xC0,0xC6,0x7C,0x00,0x00,0x00,0x00,0x00}, /* 99 'c' */
    {0x00,0x00,0x1C,0x0C,0x0C,0x3C,0x6C,0xCC,0xCC,0xCC,0x76,0x00,0x00,0x00,0x00,0x00}, /* 100 'd' */
    {0x00,0x00,0x00,0x00,0x00,0x7C,0xC6,0xFE,0xC0,0xC6,0x7C,0x00,0x00,0x00,0x00,0x00}, /* 101 'e' */
    {0x00,0x00,0x38,0x6C,0x64,0x60,0xF0,0x60,0x60,0x60,0xF0,0x00,0x00,0x00,0x00,0x00}, /* 102 'f' */
    {0x00,0x00,0x00,0x00,0x00,0x76,0xCC,0xCC,0xCC,0x7C,0x0C,0xCC,0x78,0x00,0x00,0x00}, /* 103 'g' */
    {0x00,0x00,0xE0,0x60,0x60,0x6C,0x76,0x66,0x66,0x66,0xE6,0x00,0x00,0x00,0x00,0x00}, /* 104 'h' */
    {0x00,0x00,0x18,0x18,0x00,0x38,0x18,0x18,0x18,0x18,0x3C,0x00,0x00,0x00,0x00,0x00}, /* 105 'i' */
    {0x00,0x00,0x06,0x06,0x00,0x0E,0x06,0x06,0x06,0x06,0x66,0x66,0x3C,0x00,0x00,0x00}, /* 106 'j' */
    {0x00,0x00,0xE0,0x60,0x60,0x66,0x6C,0x78,0x6C,0x66,0xE6,0x00,0x00,0x00,0x00,0x00}, /* 107 'k' */
    {0x00,0x00,0x38,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x3C,0x00,0x00,0x00,0x00,0x00}, /* 108 'l' */
    {0x00,0x00,0x00,0x00,0x00,0xEC,0xFE,0xD6,0xD6,0xD6,0xC6,0x00,0x00,0x00,0x00,0x00}, /* 109 'm' */
    {0x00,0x00,0x00,0x00,0x00,0xDC,0x66,0x66,0x66,0x66,0x66,0x00,0x00,0x00,0x00,0x00}, /* 110 'n' */
    {0x00,0x00,0x00,0x00,0x00,0x7C,0xC6,0xC6,0xC6,0xC6,0x7C,0x00,0x00,0x00,0x00,0x00}, /* 111 'o' */
    {0x00,0x00,0x00,0x00,0x00,0xDC,0x66,0x66,0x66,0x7C,0x60,0x60,0xF0,0x00,0x00,0x00}, /* 112 'p' */
    {0x00,0x00,0x00,0x00,0x00,0x76,0xCC,0xCC,0xCC,0x7C,0x0C,0x0C,0x1E,0x00,0x00,0x00}, /* 113 'q' */
    {0x00,0x00,0x00,0x00,0x00,0xDC,0x76,0x66,0x60,0x60,0xF0,0x00,0x00,0x00,0x00,0x00}, /* 114 'r' */
    {0x00,0x00,0x00,0x00,0x00,0x7C,0xC6,0x70,0x1C,0xC6,0x7C,0x00,0x00,0x00,0x00,0x00}, /* 115 's' */
    {0x00,0x00,0x10,0x30,0x30,0xFC,0x30,0x30,0x30,0x36,0x1C,0x00,0x00,0x00,0x00,0x00}, /* 116 't' */
    {0x00,0x00,0x00,0x00,0x00,0xCC,0xCC,0xCC,0xCC,0xCC,0x76,0x00,0x00,0x00,0x00,0x00}, /* 117 'u' */
    {0x00,0x00,0x00,0x00,0x00,0xC6,0xC6,0xC6,0x6C,0x38,0x10,0x00,0x00,0x00,0x00,0x00}, /* 118 'v' */
    {0x00,0x00,0x00,0x00,0x00,0xC6,0xC6,0xD6,0xD6,0xFE,0x6C,0x00,0x00,0x00,0x00,0x00}, /* 119 'w' */
    {0x00,0x00,0x00,0x00,0x00,0xC6,0x6C,0x38,0x38,0x6C,0xC6,0x00,0x00,0x00,0x00,0x00}, /* 120 'x' */
    {0x00,0x00,0x00,0x00,0x00,0xC6,0xC6,0xC6,0xC6,0x7E,0x06,0x0C,0x78,0x00,0x00,0x00}, /* 121 'y' */
    {0x00,0x00,0x00,0x00,0x00,0xFE,0x8C,0x18,0x30,0x62,0xFE,0x00,0x00,0x00,0x00,0x00}, /* 122 'z' */
    {0x00,0x00,0x0E,0x18,0x18,0x18,0x70,0x18,0x18,0x18,0x0E,0x00,0x00,0x00,0x00,0x00}, /* 123 '{' */
    {0x00,0x00,0x18,0x18,0x18,0x18,0x00,0x18,0x18,0x18,0x18,0x00,0x00,0x00,0x00,0x00}, /* 124 '|' */
    {0x00,0x00,0x70,0x18,0x18,0x18,0x0E,0x18,0x18,0x18,0x70,0x00,0x00,0x00,0x00,0x00}, /* 125 '}' */
    {0x00,0x00,0x76,0xDC,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00}  /* 126 '~' */
};


/* ============================================================================
- PRIMITIVAS DE HARDWARE (PS/2, CMOS RTC & UTILITÁRIOS)
- ============================================================================ */
static inline uint8_t inb(uint16_t porta) {
    uint8_t val;
    __asm__ volatile ("inb %1, %0" : "=a"(val) : "Nd"(porta));
    return val;
}

static inline void outb(uint16_t porta, uint8_t val) {
    __asm__ volatile ("outb %0, %1" : : "a"(val), "Nd"(porta));
}

static uint8_t ler_cmos(uint8_t reg) {
    outb(0x70, reg);
    return inb(0x71);
}

static uint8_t bcd_para_bin(uint8_t val) {
    return (uint8_t)((val & 0x0F) + ((val >> 4) * 10));
}

static void rtc_ler_agora(RtcDataHora *dt) {
    for (int timeout = 1000; timeout > 0 && (ler_cmos(0x0A) & 0x80); timeout--) {
        __asm__ volatile ("pause");
    }

    uint8_t seg  = ler_cmos(0x00);
    uint8_t min  = ler_cmos(0x02);
    uint8_t hora = ler_cmos(0x04);
    uint8_t dia  = ler_cmos(0x07);
    uint8_t mes  = ler_cmos(0x08);
    uint8_t ano  = ler_cmos(0x09);
    uint8_t regB = ler_cmos(0x0B);

    if (!(regB & 0x04)) {
        seg  = bcd_para_bin(seg);
        min  = bcd_para_bin(min);
        hora = bcd_para_bin(hora & 0x7F);
        dia  = bcd_para_bin(dia);
        mes  = bcd_para_bin(mes);
        ano  = bcd_para_bin(ano);
    }

    dt->seg  = seg;
    dt->min  = min;
    dt->hora = hora;
    dt->dia  = dia;
    dt->mes  = mes;
    dt->ano  = ano;
}

static void formatar_2dig(uint8_t val, char *out) {
    out[0] = (char)('0' + ((val / 10) % 10));
    out[1] = (char)('0' + (val % 10));
}

static void obter_estado_mouse(int *x, int *y, int *botoes) {
    uint32_t mx, my, mb;
    __asm__ volatile (
        "call mouse_ler_posicao"
        : "=D"(mx), "=S"(my), "=a"(mb)
        :
        : "rcx", "rdx", "r8", "r9", "r10", "r11", "memory"
    );
    *x = (int)mx;
    *y = (int)my;
    *botoes = (int)mb;
}

static int ponto_no_retangulo(int px, int py, int rx, int ry, int rw, int rh) {
    return (px >= rx && px < (rx + rw) && py >= ry && py < (ry + rh));
}

static size_t str_len(const char *s) {
    size_t n = 0;
    while (s && s[n]) n++;
    return n;
}

static int __attribute__((unused)) str_eq(const char *a, const char *b) {
    size_t i = 0;
    if (!a || !b) return 0;
    while (a[i] && b[i]) {
        if (a[i] != b[i]) return 0;
        i++;
    }
    return a[i] == b[i];
}

static void str_copy(char *dst, const char *src, size_t max_len) {
    size_t i = 0;
    if (!dst || !src || max_len == 0) return;

    while (i < max_len - 1 && src[i]) {
        dst[i] = src[i];
        i++;
    }
    dst[i] = '\0';
}

static void num_para_str(int valor, char *buf, size_t tam) {
    if (tam < 2) return;
    char tmp[16];
    int i = 0;
    if (valor == 0) {
        buf[0] = '0';
        buf[1] = 0;
        return;
    }
    if (valor < 0) {
        buf[0] = '-';
        buf[1] = 0;
        return;
    }
    while (valor > 0 && i < 15) {
        tmp[i++] = (char)('0' + (valor % 10));
        valor /= 10;
    }
    size_t j = 0;
    while (i > 0 && j < tam - 1) {
        buf[j++] = tmp[--i];
    }
    buf[j] = 0;
}

/* ============================================================================
- MOTOR DE RENDERIZAÇÃO DIRETA NO FRAMEBUFFER (32-BIT XRGB8888)
- ============================================================================ */
static void desenhar_retangulo_solido(int x, int y, int largura, int altura, uint32_t cor) {
    if (!fb_base || largura <= 0 || altura <= 0) return;
    if (fb_largura == 0 || fb_altura == 0) return;

    uintptr_t fb_addr = (uintptr_t)fb_base;
    if (fb_addr < 0x100000ULL || fb_addr >= 0x100000000ULL) return;

    int x0 = (x < 0) ? 0 : x;
    int y0 = (y < 0) ? 0 : y;
    int x1 = (x + largura > (int)fb_largura) ? (int)fb_largura : (x + largura);
    int y1 = (y + altura  > (int)fb_altura)  ? (int)fb_altura  : (y + altura);

    if (x0 >= x1 || y0 >= y1) return;

    uint32_t pitch_bytes = fb_pitch ? fb_pitch : (fb_largura * 4U);
    uint32_t cor_32 = 0xFF000000u | (cor & 0x00FFFFFFu);

    for (int py = y0; py < y1; py++) {
        uint8_t *base_bytes = (uint8_t *)fb_base + ((uint64_t)py * pitch_bytes);
        if (!base_bytes) continue;
        uint32_t *linha_ptr = (uint32_t *)base_bytes + x0;
        int count = x1 - x0;
        for (int i = 0; i < count; i++) {
            linha_ptr[i] = cor_32;
        }
    }
}



#define BG_W 640
#define BG_H 512
#define BG_SETORES 2560
#define LBA_BG_SPLASH  8192
#define LBA_BG_LOGIN   10752
#define LBA_BG_DESKTOP 13312

/* Buffer fixo em 4 MB (0x00400000) — zero impacto no tamanho do kernel.bin */
static uint32_t * const bg_buffer_ram = (uint32_t *)0x00400000;
static uint32_t lba_bg_carregado = 0;

static int ata_ler_setor_pio28(uint32_t lba, uint16_t *destino) {
    for (int t = 100000; t > 0 && (inb(0x1F7) & 0x80); t--) __asm__ volatile ("pause");

    outb(0x1F6, (uint8_t)(0xE0 | ((lba >> 24) & 0x0F)));
    outb(0x1F2, 1);
    outb(0x1F3, (uint8_t)(lba & 0xFF));
    outb(0x1F4, (uint8_t)((lba >> 8) & 0xFF));
    outb(0x1F5, (uint8_t)((lba >> 16) & 0xFF));
    outb(0x1F7, 0x20); /* READ SECTORS */

    /* Atraso de 400ns exigido pela especificacao ATA PIO */
    inb(0x3F6); inb(0x3F6); inb(0x3F6); inb(0x3F6);

    int pronto = 0;
    for (int t = 100000; t > 0; t--) {
        uint8_t st = inb(0x1F7);
        if (st & 0x01) return -1;
        if (!(st & 0x80) && (st & 0x08)) { pronto = 1; break; }
        __asm__ volatile ("pause");
    }
    if (!pronto) return -1;

    for (int i = 0; i < 256; i++) {
        uint16_t w;
        __asm__ volatile ("inw %1, %0" : "=a"(w) : "Nd"((uint16_t)0x1F0));
        destino[i] = w;
    }
    return 0;
}

static int carregar_wallpaper_ata(uint32_t lba_inicial) {
    if (lba_bg_carregado == lba_inicial) return 1;

    uint32_t total_px = BG_W * BG_H;
    for (uint32_t i = 0; i < total_px; i++) {
        bg_buffer_ram[i] = COR_FUNDO_ESCURO;
    }

    if (detectar_disco(0) == 0) {
        lba_bg_carregado = 0;
        return 0;
    }

    uint8_t *ptr = (uint8_t *)bg_buffer_ram;
    for (uint32_t s = 0; s < BG_SETORES; s++) {
        uint8_t *setor_ptr = ptr + ((size_t)s * 512u);
        if (ata_ler_setor_pio28(lba_inicial + s, (uint16_t *)setor_ptr) != 0) {
            lba_bg_carregado = 0;
            return 0;
        }
    }
    lba_bg_carregado = lba_inicial;
    return 1;
}

static void desenhar_background_ata(uint32_t lba_inicial, int L, int A) {
    static int map_x[2048];

    if (!fb_base || L <= 0 || A <= 0) {
        return;
    }

    uintptr_t fb_addr = (uintptr_t)fb_base;
    if (fb_addr < 0x100000ULL || fb_addr >= 0x100000000ULL) {
        desenhar_retangulo_solido(0, 0, L, A, COR_FUNDO_ESCURO);
        return;
    }

    if (!carregar_wallpaper_ata(lba_inicial)) {
        desenhar_retangulo_solido(0, 0, L, A, COR_FUNDO_ESCURO);
        return;
    }

    uint32_t pitch_bytes = fb_pitch ? fb_pitch : ((uint32_t)L * 4U);
    int max_w = (L < 2048) ? L : 2048;

    for (int px = 0; px < max_w; px++) {
        map_x[px] = (px * BG_W) / L;
    }

    for (int py = 0; py < A; py++) {
        int sy = (py * BG_H) / A;
        if (sy >= BG_H) sy = BG_H - 1;
        const uint32_t *src_linha = bg_buffer_ram + (sy * BG_W);
        uint32_t *dst_linha = (uint32_t *)((uint8_t *)fb_base + (uint64_t)py * pitch_bytes);

        for (int px = 0; px < max_w; px++) {
            uint32_t cor = src_linha[map_x[px]];
            dst_linha[px] = 0xFF000000u | (cor & 0x00FFFFFFu);
        }
    }
}

static void desenhar_caixa_com_borda(int x, int y, int w, int h, int espessura, uint32_t cor_borda, uint32_t cor_fundo) {
    desenhar_retangulo_solido(x, y, w, h, cor_borda);
    desenhar_retangulo_solido(
        x + espessura,
        y + espessura,
        w - (espessura * 2),
        h - (espessura * 2),
        cor_fundo
    );
}

void gpu_desenhar_icone(const uint32_t *pixels, int x, int y, int w, int h) {
    if (!pixels || !fb_base) return;
    uint32_t pitch_bytes = fb_pitch ? fb_pitch : (fb_largura * 4);

    for (int lin = 0; lin < h; lin++) {
        int py = y + lin;
        if (py < 0 || py >= (int)fb_altura) continue;
        uint32_t *dst_linha = (uint32_t *)((uint8_t *)fb_base + (uint64_t)py * pitch_bytes);

        for (int col = 0; col < w; col++) {
            int px = x + col;
            if (px < 0 || px >= (int)fb_largura) continue;

            uint32_t src = pixels[lin * w + col];
            uint32_t alpha = (src >> 24) & 0xFF;
            if (alpha == 0) continue;
            if (alpha == 255) {
                dst_linha[px] = src;
                continue;
            }

            uint32_t dst = dst_linha[px];
            uint32_t inv = 255 - alpha;
            uint32_t r = (((src >> 16) & 0xFF) * alpha + ((dst >> 16) & 0xFF) * inv) >> 8;
            uint32_t g = (((src >> 8)  & 0xFF) * alpha + ((dst >> 8)  & 0xFF) * inv) >> 8;
            uint32_t b = (( src        & 0xFF) * alpha + ( dst        & 0xFF) * inv) >> 8;
            dst_linha[px] = 0xFF000000 | (r << 16) | (g << 8) | b;
        }
    }
}

static void gpu_escrever_titulo(const char *texto, int x, int y, uint32_t cor) {
    if (!texto || !fb_base) return;
    uint32_t pitch_bytes = fb_pitch ? fb_pitch : (fb_largura * 4);

    uint32_t sr = (cor >> 16) & 0xFF;
    uint32_t sg = (cor >> 8)  & 0xFF;
    uint32_t sb =  cor        & 0xFF;

    int cx = x;
    while (*texto) {
        unsigned char c = (unsigned char)(*texto++);
        if (c < 32 || c > 126) c = '?';
        const uint8_t *glifo = fonte_ui_alpha[c - 32];

        for (int lin = 0; lin < FONTE_UI_H; lin++) {
            int py = y + lin;
            if (py < 0 || py >= (int)fb_altura) continue;
            uint32_t *dst_linha = (uint32_t *)((uint8_t *)fb_base + (uint64_t)py * pitch_bytes);

            for (int col = 0; col < FONTE_UI_W; col++) {
                int px = cx + col;
                if (px < 0 || px >= (int)fb_largura) continue;

                uint32_t alpha = glifo[lin * FONTE_UI_W + col];
                if (alpha == 0) continue;
                if (alpha == 255) {
                    dst_linha[px] = cor;
                    continue;
                }

                uint32_t dst = dst_linha[px];
                uint32_t inv = 255 - alpha;
                uint32_t r = (sr * alpha + ((dst >> 16) & 0xFF) * inv) >> 8;
                uint32_t g = (sg * alpha + ((dst >> 8)  & 0xFF) * inv) >> 8;
                uint32_t b = (sb * alpha + ( dst        & 0xFF) * inv) >> 8;
                dst_linha[px] = 0xFF000000 | (r << 16) | (g << 8) | b;
            }
        }
        cx += FONTE_UI_W;
    }
}

void gpu_escrever_texto(const char *texto, int x, int y, uint32_t cor) {
    if (!texto || !fb_base) return;

    int cx = x;
    int cy = y;
    uint32_t pitch_bytes = fb_pitch ? fb_pitch : (fb_largura * 4);

    while (*texto) {
        unsigned char c = (unsigned char)(*texto++);
        if (c == '\n') {
            cx = x;
            cy += 18;
            continue;
        }
        if (c < 32 || c > 126) {
            c = '?';
        }

        const uint8_t *glifos = fonte_8x16[c - 32];
        for (int linha = 0; linha < 16; linha++) {
            int py = cy + linha;
            if (py < 0 || py >= (int)fb_altura) continue;

            uint8_t bits = glifos[linha];
            if (!bits) continue;

            uint32_t *linha_ptr = (uint32_t *)((uint8_t *)fb_base + (uint64_t)py * pitch_bytes);
            for (int col = 0; col < 8; col++) {
                if (bits & (1 << (7 - col))) {
                    int px = cx + col;
                    if (px >= 0 && px < (int)fb_largura) {
                        linha_ptr[px] = cor;
                    }
                }
            }
        }
        cx += 8;
    }
}

static void escrever_texto_centralizado(const char *texto, int centro_x, int y, uint32_t cor) {
    int largura_px = (int)str_len(texto) * 8;
    gpu_escrever_texto(texto, centro_x - (largura_px / 2), y, cor);
}

/* ============================================================================
- TELEMETRIA DE HARDWARE
- ============================================================================ */
static void obter_cpu_vendor(char *out16) {
    uint32_t eax, ebx, ecx, edx;
    __asm__ volatile ("cpuid" : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx) : "a"(0));

    *(uint32_t *)(out16 + 0) = ebx;
    *(uint32_t *)(out16 + 4) = edx;
    *(uint32_t *)(out16 + 8) = ecx;
    out16[12] = 0;
}

static uint32_t detectar_ram_total_mb(void) {
    uint32_t b64_lo = ler_cmos(0x34);
    uint32_t b64_hi = ler_cmos(0x35);
    uint32_t blocos_64k = (b64_hi << 8) | b64_lo;

    if (blocos_64k > 0) {
        return 16 + ((blocos_64k * 64) / 1024);
    }

    uint32_t kb_lo = ler_cmos(0x30);
    uint32_t kb_hi = ler_cmos(0x31);
    uint32_t ext_kb = (kb_hi << 8) | kb_lo;
    return 1 + (ext_kb / 1024);
}

static void inicializar_telemetria(TelemetriaSistema *tel, int L, int A) {
    obter_cpu_vendor(tel->cpu_vendor);
    tel->cpu_uso_pct = 4;

    tel->ram_total_mb = detectar_ram_total_mb();
    if (tel->ram_total_mb < 32) tel->ram_total_mb = 128;

    uint32_t fb_mb = (uint32_t)(((uint64_t)L * (uint64_t)A * 4ULL) / (1024ULL * 1024ULL));
    tel->ram_usada_mb = 12 + fb_mb;
    if (tel->ram_usada_mb > tel->ram_total_mb) {
        tel->ram_usada_mb = tel->ram_total_mb / 2;
    }

    tel->disco_online = (detectar_disco(0) != 0);
    if (tel->disco_online) {
        uint64_t setores = obter_tamanho_disco();
        tel->disco_total_mb = (uint32_t)(setores / 2048ULL);
    } else {
        tel->disco_total_mb = 0;
    }
}

static void desenhar_barra_progresso(int x, int y, int w, int h, int pct, uint32_t cor_fill) {
    if (pct < 0) pct = 0;
    if (pct > 100) pct = 100;
    desenhar_caixa_com_borda(x, y, w, h, 1, COR_BORDA_SUTIL, COR_INPUT_BG);
    int fill_w = ((w - 2) * pct) / 100;
    if (fill_w > 0) {
        desenhar_retangulo_solido(x + 1, y + 1, fill_w, h - 2, cor_fill);
    }
}

static void desenhar_widgets_sistema(int L, const TelemetriaSistema *tel) {
    int w_larg = 256;
    int w_alt  = 214;
    int wx     = L - w_larg - 14;
    int wy     = 48;

    char linha[48];
    char num[16];
    size_t p;

    desenhar_caixa_com_borda(wx, wy, w_larg, w_alt, 1, COR_ROXO_NEON, COR_PAINEL);
    desenhar_retangulo_solido(wx + 1, wy + 1, w_larg - 2, 24, COR_CARD);
    gpu_escrever_texto("MONITOR DE HARDWARE", wx + 12, wy + 5, COR_CIANO_NEON);

    int cx = wx + 12;
    int cy = wy + 34;
    int bar_w = w_larg - 24;

    /* --- WIDGET 1: CPU --- */
    gpu_desenhar_icone(icone_sistema, cx, cy - 2, ICONE_TAM, ICONE_TAM);
    str_copy(linha, "CPU: ", sizeof(linha));
    p = str_len(linha);
    str_copy(linha + p, tel->cpu_vendor, sizeof(linha) - p);
    gpu_escrever_texto(linha, cx + 26, cy, COR_TEXTO_BRANCO);

    num_para_str(tel->cpu_uso_pct, num, sizeof(num));
    p = str_len(num);
    num[p] = '%';
    num[p + 1] = 0;
    gpu_escrever_texto(num, wx + w_larg - 44, cy, COR_CIANO_NEON);

    cy += 22;
    desenhar_barra_progresso(cx, cy, bar_w, 12, tel->cpu_uso_pct, COR_CIANO_NEON);
    cy += 24;

    /* --- WIDGET 2: MEMORIA RAM --- */
    gpu_desenhar_icone(icone_agenda, cx, cy - 2, ICONE_TAM, ICONE_TAM);
    str_copy(linha, "RAM: ", sizeof(linha));
    num_para_str((int)tel->ram_usada_mb, num, sizeof(num));
    p = str_len(linha);
    str_copy(linha + p, num, sizeof(linha) - p);
    p = str_len(linha);
    str_copy(linha + p, "/", sizeof(linha) - p);
    num_para_str((int)tel->ram_total_mb, num, sizeof(num));
    p = str_len(linha);
    str_copy(linha + p, num, sizeof(linha) - p);
    p = str_len(linha);
    str_copy(linha + p, " MB", sizeof(linha) - p);
    gpu_escrever_texto(linha, cx + 26, cy, COR_TEXTO_BRANCO);

    int ram_pct = (tel->ram_total_mb > 0)
        ? (int)((tel->ram_usada_mb * 100U) / tel->ram_total_mb)
        : 0;
    cy += 22;
    desenhar_barra_progresso(cx, cy, bar_w, 12, ram_pct, COR_VERDE_NEON);
    cy += 24;

    /* --- WIDGET 3: DISCO TOTAL --- */
    gpu_desenhar_icone(icone_disco, cx, cy - 2, ICONE_TAM, ICONE_TAM);
    if (tel->disco_online) {
        str_copy(linha, "DISCO: ", sizeof(linha));
        num_para_str((int)tel->disco_total_mb, num, sizeof(num));
        p = str_len(linha);
        str_copy(linha + p, num, sizeof(linha) - p);
        p = str_len(linha);
        str_copy(linha + p, " MB Total", sizeof(linha) - p);
        gpu_escrever_texto(linha, cx + 26, cy, COR_TEXTO_BRANCO);
    } else {
        gpu_escrever_texto("DISCO: Nao detectado", cx + 26, cy, COR_VERMELHO_ALERTA);
    }

    cy += 22;
    desenhar_barra_progresso(cx, cy, bar_w, 12, tel->disco_online ? 100 : 0, COR_ROXO_CLARO);
    cy += 18;
    gpu_escrever_texto(tel->disco_online ? "ATA Primary Master (0x1F0) OK" : "Verifique imagem .vdi/.img",
                       cx, cy, COR_TEXTO_SUAVE);
}


/* ============================================================================
- SYSTEM TRAY
- ============================================================================ */
#define SYSTRAY_LARGURA 248

static void desenhar_systray(int L, int taskbar_y, int taskbar_h,
                             int link_ativo, int disco_ok, int bt_status, int audio_status,
                             const RtcDataHora *dt, int mx, int my) {
    int tray_w = SYSTRAY_LARGURA;
    int tray_h = taskbar_h - 6;
    int tray_x = L - tray_w - 8;
    int tray_y = taskbar_y + 3;

    int hover_tray = ponto_no_retangulo(mx, my, tray_x, tray_y, tray_w, tray_h);

    desenhar_caixa_com_borda(tray_x, tray_y, tray_w, tray_h, 1,
        hover_tray ? COR_CIANO_NEON : COR_BORDA_SUTIL,
        hover_tray ? COR_HOVER : COR_PAINEL_SEC);

    int ico_y = tray_y + 6;

    /* 1. Rede Cabeada */
    int eth_x = tray_x + 8;
    gpu_desenhar_icone(icone_ethernet, eth_x, ico_y, ICONE_TAM, ICONE_TAM);
    desenhar_retangulo_solido(eth_x + ICONE_TAM - 4, ico_y + ICONE_TAM - 4, 5, 5,
        link_ativo ? COR_VERDE_NEON : COR_ROXO_CLARO);

    /* 2. Rede Wi-Fi */
    int wifi_x = eth_x + 26;
    gpu_desenhar_icone(icone_wifi, wifi_x, ico_y, ICONE_TAM, ICONE_TAM);

    /* 3. Bluetooth */
    int bt_x = wifi_x + 26;
    gpu_desenhar_icone(icone_bluetooth, bt_x, ico_y, ICONE_TAM, ICONE_TAM);
    uint32_t cor_led_bt = COR_BORDA_SUTIL;
    if (bt_status == 2)      cor_led_bt = COR_VERDE_NEON;
    else if (bt_status == 1) cor_led_bt = COR_CIANO_NEON;
    desenhar_retangulo_solido(bt_x + ICONE_TAM - 4, ico_y + ICONE_TAM - 4, 5, 5, cor_led_bt);

    /* 4. Audio */
    int aud_x = bt_x + 26;
    gpu_desenhar_icone(icone_audio, aud_x, ico_y, ICONE_TAM, ICONE_TAM);
    uint32_t cor_led_aud = COR_BORDA_SUTIL;
    if (audio_status == 1)      cor_led_aud = COR_VERDE_NEON;
    else if (audio_status == 2) cor_led_aud = COR_VERMELHO_ALERTA;
    desenhar_retangulo_solido(aud_x + ICONE_TAM - 4, ico_y + ICONE_TAM - 4, 5, 5, cor_led_aud);

    /* 5. Disco ATA/IDE */
    int disk_x = aud_x + 26;
    gpu_desenhar_icone(icone_disco, disk_x, ico_y, ICONE_TAM, ICONE_TAM);
    desenhar_retangulo_solido(disk_x + ICONE_TAM - 4, ico_y + ICONE_TAM - 4, 5, 5,
        disco_ok ? COR_VERDE_NEON : COR_VERMELHO_ALERTA);

    int sep_x = disk_x + 26;
    desenhar_retangulo_solido(sep_x, tray_y + 5, 1, tray_h - 10, COR_BORDA_SUTIL);

    /* 6. Relogio Digital + Data */
    char hora_str[8];
    char data_str[12];

    formatar_2dig(dt->hora, &hora_str[0]);
    hora_str[2] = ':';
    formatar_2dig(dt->min, &hora_str[3]);
    hora_str[5] = 0;

    formatar_2dig(dt->dia, &data_str[0]);
    data_str[2] = '/';
    formatar_2dig(dt->mes, &data_str[3]);
    data_str[5] = '/';
    data_str[6] = '2';
    data_str[7] = '0';
    formatar_2dig(dt->ano, &data_str[8]);
    data_str[10] = 0;

    int relogio_x = sep_x + 12;
    gpu_escrever_texto(hora_str, relogio_x + 20, tray_y + 2, COR_TEXTO_BRANCO);
    gpu_escrever_texto(data_str, relogio_x, tray_y + 16, COR_TEXTO_SUAVE);
}

/* ============================================================================
- DRIVER DE TECLADO PS/2 PARA INTERFACE GRÁFICA (Shift, Backspace, Tab & Setas)
- ============================================================================ */
static char ler_tecla_ps2(void) {
    static int shift_ativo   = 0;
    static int estendido_e0  = 0;

    static const char mapa_normal[128] = {
        0,  27, '1','2','3','4','5','6','7','8','9','0','-','=', '\b',
        '\t','q','w','e','r','t','y','u','i','o','p','[',']','\n', 0,
        'a','s','d','f','g','h','j','k','l',';','\'','`', 0, '\\',
        'z','x','c','v','b','n','m',',','.','/', 0, '*', 0, ' '
    };

    static const char mapa_shift[128] = {
        0,  27, '!','@','#','$','%','^','&','*','(',')','_','+', '\b',
        '\t','Q','W','E','R','T','Y','U','I','O','P','{','}','\n', 0,
        'A','S','D','F','G','H','J','K','L',':','"','~', 0, '|',
        'Z','X','C','V','B','N','M','<','>','?', 0, '*', 0, ' '
    };

    while (1) {
        uint8_t status = inb(0x64);
        if ((status & 0x01) == 0) return 0;
        if (status & 0x20) return 0; /* Dado pertence ao mouse PS/2 */

        uint8_t sc = inb(0x60);

        if (sc == 0xE0) {
            estendido_e0 = 1;
            continue;
        }

        if (estendido_e0) {
            estendido_e0 = 0;
            if (sc & 0x80) continue;
            if (sc == 0x48 || sc == 0x50) return '\t'; /* Setas Cima/Baixo alternam campo */
            continue;
        }

        /* Shift pressionado / solto (Left Shift 0x2A, Right Shift 0x36) */
        if (sc == 0x2A || sc == 0x36) {
            shift_ativo = 1;
            continue;
        }
        if (sc == 0xAA || sc == 0xB6) {
            shift_ativo = 0;
            continue;
        }

        if (sc & 0x80) continue;
        if (sc < sizeof(mapa_normal)) {
            char ch = shift_ativo ? mapa_shift[sc] : mapa_normal[sc];
            if (ch != 0) return ch;
        }
    }
}

/* ============================================================================
- TELA 1: ANIMAÇÃO DE CARREGAMENTO DO AMBIENTE GRÁFICO (Via Disco ATA)
- ============================================================================ */
static void exibir_splash_carregamento(int L, int A) {
    if (fb_base) {
        uint32_t total_pixels = (fb_pitch ? (fb_pitch / 4) : (uint32_t)L) * (uint32_t)A;
        for (uint32_t i = 0; i < total_pixels; i++) {
            fb_base[i] = COR_FUNDO_ESCURO;
        }
    }

    desenhar_background_ata(LBA_BG_SPLASH, L, A);
    desenhar_retangulo_solido(0, 0, L, 4, COR_CIANO_NEON);

    int box_w = (L * 54) / 100;
    if (box_w < 340) box_w = 340;
    if (box_w > 680) box_w = 680;
    int box_h = 170;
    int box_x = (L - box_w) / 2;
    int box_y = (A - box_h) / 2;

    desenhar_caixa_com_borda(box_x, box_y, box_w, box_h, 2, COR_ROXO_NEON, COR_PAINEL_SEC);
    escrever_texto_centralizado("FYDELISTECH OS v4.2", L / 2, box_y + 20, COR_CIANO_NEON);
    escrever_texto_centralizado("Inicializando Ambiente Grafico & Window Manager", L / 2, box_y + 44, COR_TEXTO_SUAVE);

    int barra_larg = box_w - 48;
    int barra_alt  = 24;
    int barra_x    = box_x + 24;
    int barra_y    = box_y + 82;

    desenhar_caixa_com_borda(barra_x - 2, barra_y - 2, barra_larg + 4, barra_alt + 4, 1, COR_BORDA_SUTIL, COR_INPUT_BG);

    char pct_buf[16];
    for (int p = 0; p <= 100; p += 10) {
        int preenchido = (p * barra_larg) / 100;
        uint32_t cor_barra = (p == 100) ? COR_CIANO_NEON : COR_ROXO_NEON;

        desenhar_retangulo_solido(barra_x, barra_y, preenchido, barra_alt, cor_barra);
        desenhar_retangulo_solido(barra_x, barra_y + barra_alt + 10, barra_larg, 20, COR_PAINEL_SEC);

        if (p < 40) {
            gpu_escrever_texto("Carregando drivers VESA 32-bit...", barra_x, barra_y + barra_alt + 12, COR_TEXTO_SUAVE);
        } else if (p < 80) {
            gpu_escrever_texto("Iniciando mouse PS/2 e compositor...", barra_x, barra_y + barra_alt + 12, COR_TEXTO_SUAVE);
        } else if (p < 100) {
            gpu_escrever_texto("Preparando interface de autenticacao...", barra_x, barra_y + barra_alt + 12, COR_TEXTO_SUAVE);
        } else {
            gpu_escrever_texto("Sistema pronto!", barra_x, barra_y + barra_alt + 12, COR_VERDE_NEON);
        }

        num_para_str(p, pct_buf, sizeof(pct_buf));
        size_t len = str_len(pct_buf);
        pct_buf[len] = '%';
        pct_buf[len + 1] = 0;

        int pct_x = barra_x + barra_larg - ((int)str_len(pct_buf) * 8);
        gpu_escrever_texto(pct_buf, pct_x, barra_y + barra_alt + 12, COR_CIANO_NEON);

        for (volatile uint64_t d = 0; d < 1800000; d++) {
            __asm__ volatile ("pause");
        }
    }
}

void fyd_zerar_memoria(void *ptr, size_t tam) {
    volatile uint8_t *p = (volatile uint8_t *)ptr;
    if (!p) return;
    while (tam--) {
        *p++ = 0;
    }
}

int auth_sistema_inicializar(void) {
    if (g_auth_pronto) return 0;
    if (fydb_inicializar() != 0) {
        return -1;
    }
    g_auth_pronto = 1;
    return 0;
}

static void fyd_strncpy(char *dst, const char *src, size_t n) {
    size_t i = 0;
    if (!dst || n == 0) return;
    if (src) {
        while (i < n - 1 && src[i] != '\0') {
            dst[i] = src[i];
            i++;
        }
    }
    while (i < n) {
        dst[i] = '\0';
        i++;
    }
}

static int fyd_streq(const char *a, const char *b) {
    size_t i = 0;
    if (!a || !b) return 0;
    while (a[i] != '\0' && b[i] != '\0') {
        if (a[i] != b[i]) return 0;
        i++;
    }
    return a[i] == b[i];
}

static void fydb_recalcular_ativos(void) {
    uint32_t ativos = 0;
    for (int i = 0; i < FYD_MAX_USUARIOS; i++) {
        if (g_fydb_tabela[i].ativo && g_fydb_tabela[i].usuario[0] != '\0') {
            ativos++;
        }
    }
    g_fydb_hdr.total_ativos = ativos;
}

static int fydb_persistir_disco(void) {
    if (!g_fydb_disco_ok) return 0;

    fydb_recalcular_ativos();
    /* Ligar aqui a rotina real de escrita em arquivo do seu FS quando disponível
     * (ex.: gravar header + g_fydb_tabela em FYD_PATH_USUARIOS). */
    return 0;
}

int fydb_inicializar(void) {
    fyd_zerar_memoria(&g_fydb_hdr, sizeof(g_fydb_hdr));
    fyd_zerar_memoria(g_fydb_tabela, sizeof(g_fydb_tabela));

    g_fydb_hdr.magic = FYD_MAGIC_USUARIOS;
    g_fydb_hdr.versao = 1;
    g_fydb_hdr.max_usuarios = FYD_MAX_USUARIOS;
    g_fydb_hdr.total_ativos = 0;
    g_fydb_disco_ok = 0;

    fs_criar_diretorio("/fyd");
    fs_criar_diretorio(FYD_DIR_CONFIG);

    /* Enquanto a leitura/escrita por caminho de arquivo não está ligada aqui,
     * a tabela mantém os registros ativos na sessão/RAM sem falhar o boot. */
    return 0;
}

int fydb_contar_usuarios(void) {
    int total = 0;
    for (int i = 0; i < FYD_MAX_USUARIOS; i++) {
        if (g_fydb_tabela[i].ativo && g_fydb_tabela[i].usuario[0] != '\0') {
            total++;
        }
    }
    return total;
}

int fydb_buscar_usuario(const char *usuario, FydRegistroUsuario *out_reg) {
    if (!usuario || usuario[0] == '\0' || !out_reg) return -1;
    for (int i = 0; i < FYD_MAX_USUARIOS; i++) {
        if (g_fydb_tabela[i].ativo && fyd_streq(g_fydb_tabela[i].usuario, usuario)) {
            *out_reg = g_fydb_tabela[i];
            return 0;
        }
    }
    return -1;
}

int fydb_salvar_usuario(const FydRegistroUsuario *reg) {
    if (!reg || reg->usuario[0] == '\0') return -1;

    int slot = -1;
    for (int i = 0; i < FYD_MAX_USUARIOS; i++) {
        if (fyd_streq(g_fydb_tabela[i].usuario, reg->usuario)) {
            slot = i;
            break;
        }
        if (slot == -1 && (!g_fydb_tabela[i].ativo || g_fydb_tabela[i].usuario[0] == '\0')) {
            slot = i;
        }
    }
    if (slot < 0) return -2;

    g_fydb_tabela[slot] = *reg;
    fyd_strncpy(g_fydb_tabela[slot].usuario, reg->usuario, sizeof(g_fydb_tabela[slot].usuario));
    fydb_recalcular_ativos();
    fydb_persistir_disco();
    return 0;
}

void fycrypto_aleatorio(uint8_t *buf, size_t len) {
    if (!buf || len == 0) return;
    uint32_t lo = 0, hi = 0;
    __asm__ volatile ("rdtsc" : "=a"(lo), "=d"(hi));
    uint64_t x = g_fydb_prng_estado ^ (((uint64_t)hi << 32) | lo);

    for (size_t i = 0; i < len; i++) {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        buf[i] = (uint8_t)((x >> ((i & 7) * 8)) ^ (uint8_t)(i * 31U + 17U));
    }
    g_fydb_prng_estado = x ? x : 0x9E3779B97F4A7C15ULL;
}

void fycrypto_derivar_hash(const char *senha, const uint8_t *salt, size_t salt_len,
                           uint8_t *out_hash, size_t hash_len) {
    if (!out_hash || hash_len == 0) return;
    uint64_t h0 = 0xcbf29ce484222325ULL;
    uint64_t h1 = 0x9e3779b97f4a7c15ULL;

    if (salt && salt_len > 0) {
        for (size_t i = 0; i < salt_len; i++) {
            h0 ^= (uint64_t)salt[i] + (i & 0xFF);
            h0 *= 0x100000001b3ULL;
            h1 = (h1 << 7) | (h1 >> 57);
            h1 ^= (uint64_t)salt[i] * 131ULL;
        }
    }

    if (senha) {
        for (size_t i = 0; senha[i] != '\0'; i++) {
            uint8_t c = (uint8_t)senha[i];
            h0 ^= (uint64_t)c + i;
            h0 *= 0x100000001b3ULL;
            h1 ^= (uint64_t)c * 257ULL + (i * 17ULL);
            h1 *= 0x85ebca6bULL;
        }
    }

    for (size_t i = 0; i < hash_len; i++) {
        uint64_t mix = (i & 1) ? h1 : h0;
        mix ^= mix >> 29;
        mix *= 0xbf58476d1ce4e5b9ULL;
        mix ^= mix >> 32;
        out_hash[i] = (uint8_t)((mix >> ((i % 8) * 8)) & 0xFFU);
        h0 = mix + i;
        h1 ^= mix >> 11;
    }
}

int fycrypto_comparar_constante(const uint8_t *a, const uint8_t *b, size_t len) {
    if (!a || !b) return -1;
    uint8_t diff = 0;
    for (size_t i = 0; i < len; i++) {
        diff |= (uint8_t)(a[i] ^ b[i]);
    }
    return (diff == 0) ? 0 : -1;
}

int fydcipher_cifrar_bloco(const uint8_t *in, size_t len, uint8_t *out) {
    if (!in || !out || len == 0) return -1;
    static const uint8_t chave_bloco[16] = {
        0x46, 0x79, 0x64, 0x65, 0x6C, 0x69, 0x73, 0x54,
        0x65, 0x63, 0x68, 0x32, 0x30, 0x32, 0x36, 0x21
    };
    for (size_t i = 0; i < len; i++) {
        uint8_t k = chave_bloco[i & 15];
        out[i] = (uint8_t)((in[i] ^ k) + (uint8_t)((i * 13U) & 0xFFU));
    }
    return 0;
}

void fydperm_definir_sessao(const char *usuario, int nivel) {
    fyd_strncpy(g_fydperm_usuario_atual, usuario ? usuario : "", sizeof(g_fydperm_usuario_atual));
    g_fydperm_nivel_atual = nivel;
}

int fydperm_pode_cadastrar_usuario(void) {
    return (g_fydperm_nivel_atual >= FYD_PERM_ADMIN) ? 1 : 0;
}

/* Garante usuario default adm / fydelis2026 sem sobrescrever banco existente */
int auth_garantir_adm_padrao(void) {
    if (auth_sistema_inicializar() != 0) {
        return -1;
    }

    FydRegistroUsuario existente;
    fyd_zerar_memoria(&existente, sizeof(existente));

    /* Se o banco ja existe e o usuario adm ja foi criado, nao sobrescreve */
    if (fydb_buscar_usuario(FYD_ADM_USER, &existente) == 0 && existente.ativo) {
        fyd_zerar_memoria(&existente, sizeof(existente));
        return 0;
    }
    fyd_zerar_memoria(&existente, sizeof(existente));

    FydRegistroUsuario novo;
    fyd_zerar_memoria(&novo, sizeof(novo));
    str_copy(novo.usuario, FYD_ADM_USER, sizeof(novo.usuario));
    novo.nivel = FYD_ADM_NIVEL;
    novo.ativo = 1;

    fycrypto_aleatorio(novo.salt, sizeof(novo.salt));
    fycrypto_derivar_hash(FYD_ADM_PASS, novo.salt, sizeof(novo.salt),
                          novo.hash_senha, sizeof(novo.hash_senha));
    fydcipher_cifrar_bloco(novo.hash_senha, sizeof(novo.hash_senha), novo.segredo_cifrado);

    int rc = fydb_salvar_usuario(&novo);
    fyd_zerar_memoria(&novo, sizeof(novo));
    return (rc == 0) ? 0 : -2;
}

int auth_tem_usuarios_cadastrados(void) {
    if (!g_auth_pronto && auth_sistema_inicializar() != 0) return 0;
    return (fydb_contar_usuarios() > 0) ? 1 : 0;
}

int auth_registrar_usuario(const char *usuario, const char *senha, FydPermNivel nivel) {
    if (!g_auth_pronto && auth_sistema_inicializar() != 0) return -1;
    if (!usuario || !senha || usuario[0] == '\0' || senha[0] == '\0') return -2;

    /* Permite primeiro cadastro quando o banco está vazio; depois exige permissão */
    if (fydb_contar_usuarios() > 0 && !fydperm_pode_cadastrar_usuario()) {
        return -3;
    }

    FydRegistroUsuario existente;
    fyd_zerar_memoria(&existente, sizeof(existente));
    if (fydb_buscar_usuario(usuario, &existente) == 0 && existente.ativo) {
        fyd_zerar_memoria(&existente, sizeof(existente));
        return -4; /* Usuário já existe */
    }
    fyd_zerar_memoria(&existente, sizeof(existente));

    FydRegistroUsuario novo;
    fyd_zerar_memoria(&novo, sizeof(novo));
    fyd_strncpy(novo.usuario, usuario, sizeof(novo.usuario));
    novo.nivel = (uint32_t)nivel;
    novo.ativo = 1;

    /* 1. fycrypto: gera salt e deriva hash da senha (nunca salva senha pura) */
    fycrypto_aleatorio(novo.salt, sizeof(novo.salt));
    fycrypto_derivar_hash(senha, novo.salt, sizeof(novo.salt),
                          novo.hash_senha, sizeof(novo.hash_senha));

    /* 2. fydcipher: cifra material sensível auxiliar para persistência no fydb */
    fydcipher_cifrar_bloco(novo.hash_senha, sizeof(novo.hash_senha), novo.segredo_cifrado);

    /* 3. fydb: persiste o registro do usuário */
    int rc = fydb_salvar_usuario(&novo);
    fyd_zerar_memoria(&novo, sizeof(novo));
    return (rc == 0) ? 0 : -5;
}

int auth_login(const char *usuario, const char *senha) {
    if (!g_auth_pronto && auth_sistema_inicializar() != 0) return -1;
    if (!usuario || !senha || usuario[0] == '\0' || senha[0] == '\0') return -2;

    FydRegistroUsuario reg;
    fyd_zerar_memoria(&reg, sizeof(reg));

    /* 1. fydb: busca registro pelo nome de usuário */
    if (fydb_buscar_usuario(usuario, &reg) != 0 || !reg.ativo) {
        fyd_zerar_memoria(&reg, sizeof(reg));
        return -3;
    }

    /* 2. fycrypto: deriva hash com o salt salvo e compara em tempo constante */
    uint8_t hash_calculado[32];
    fycrypto_derivar_hash(senha, reg.salt, sizeof(reg.salt),
                          hash_calculado, sizeof(hash_calculado));

    int ok = fycrypto_comparar_constante(hash_calculado, reg.hash_senha, sizeof(hash_calculado));
    fyd_zerar_memoria(hash_calculado, sizeof(hash_calculado));

    if (ok != 0) {
        fyd_zerar_memoria(&reg, sizeof(reg));
        return -4;
    }

    /* 3. fydperm: ativa sessão com nível de permissão do usuário */
    fyd_zerar_memoria(&g_sessao, sizeof(g_sessao));
    g_sessao.autenticado = 1;
    fyd_strncpy(g_sessao.usuario, reg.usuario, sizeof(g_sessao.usuario));
    g_sessao.nivel = (FydPermNivel)reg.nivel;
    fycrypto_aleatorio((uint8_t *)&g_sessao.token_sessao, sizeof(g_sessao.token_sessao));

    fydperm_definir_sessao(g_sessao.usuario, (int)g_sessao.nivel);

    fyd_zerar_memoria(&reg, sizeof(reg));
    return 0;
}

void auth_logout(void) {
    fyd_zerar_memoria(&g_sessao, sizeof(g_sessao));
    fydperm_definir_sessao("", FYD_PERM_CONVIDADO);
}

const FydSessaoAtiva *auth_sessao_atual(void) {
    return &g_sessao;
}

static int __attribute__((unused)) fydperm_sessao_e_admin(void) {
    const FydSessaoAtiva *s = auth_sessao_atual();
    if (!s || !s->autenticado) return 0;
    return (s->nivel >= FYD_PERM_ADMIN) ? 1 : 0;
}

static void fydperm_obter_rotulo_sessao(char *dst, size_t tam, const char *prefixo) {
    const FydSessaoAtiva *s = auth_sessao_atual();
    const char *nome = (s && s->autenticado && s->usuario[0] != '\0') ? s->usuario : "convidado";

    fyd_strncpy(dst, prefixo ? prefixo : "", tam);
    size_t p = str_len(dst);
    if (p + 1 < tam) {
        fyd_strncpy(dst + p, nome, tam - p);
    }
}

/* ============================================================================
- TELA 2: LOGIN GRÁFICO INTERATIVO (Via Disco ATA, Cursor Limpo e Tab/Backspace)
- ============================================================================ */
static void exibir_tela_login(int L, int A) {
    char usuario[24];
    char senha[24];
    char mascara[24];
    int campo_ativo = 0;        /* Começa no campo USUARIO */
    int erro_login  = 0;
    int precisa_redesenhar = 1;
    int btn_ant = 0;

    fyd_zerar_memoria(usuario, sizeof(usuario));
    fyd_zerar_memoria(senha, sizeof(senha));
    fyd_zerar_memoria(mascara, sizeof(mascara));

    auth_garantir_adm_padrao();

    int card_w = (L * 42) / 100;
    if (card_w < 340) card_w = 340;
    if (card_w > 460) card_w = 460;
    int card_h = 310;
    int card_x = (L - card_w) / 2;
    int card_y = (A - card_h) / 2;

    int input_x = card_x + 28;
    int input_w = card_w - 56;
    int input_h = 32;
    int user_y  = card_y + 88;
    int pass_y  = card_y + 156;
    int btn_y   = card_y + 212;

    ws_inicializar();

    while (1) {
        if (precisa_redesenhar) {
            cursor_restaurar_fundo();
            backbuffer_iniciar_frame();

            desenhar_background_ata(LBA_BG_LOGIN, L, A);
            desenhar_retangulo_solido(0, 0, L, 32, COR_PAINEL);
            desenhar_retangulo_solido(0, 32, L, 1, COR_BORDA_SUTIL);
            gpu_escrever_texto("FydelisTech OS v4.2", 16, 8, COR_CIANO_NEON);
            gpu_escrever_texto("Salvador - Bahia | x86_64", L - 216, 8, COR_TEXTO_SUAVE);

            desenhar_caixa_com_borda(card_x, card_y, card_w, card_h, 2, COR_ROXO_NEON, COR_CARD);
            escrever_texto_centralizado("AUTENTICACAO DO SISTEMA", card_x + (card_w / 2), card_y + 24, COR_CIANO_NEON);
            escrever_texto_centralizado("Entre com suas credenciais", card_x + (card_w / 2), card_y + 46, COR_TEXTO_SUAVE);

            gpu_escrever_texto("USUARIO:", input_x, user_y - 18, COR_ROXO_CLARO);
            desenhar_caixa_com_borda(input_x, user_y, input_w, input_h, 2,
                (campo_ativo == 0) ? COR_CIANO_NEON : COR_BORDA_SUTIL, COR_INPUT_BG);
            gpu_escrever_texto(usuario, input_x + 10, user_y + 8, COR_TEXTO_BRANCO);
            if (campo_ativo == 0) {
                gpu_escrever_texto("_", input_x + 10 + (int)str_len(usuario) * 8, user_y + 8, COR_CIANO_NEON);
            }

            gpu_escrever_texto("SENHA:", input_x, pass_y - 18, COR_ROXO_CLARO);
            desenhar_caixa_com_borda(input_x, pass_y, input_w, input_h, 2,
                (campo_ativo == 1) ? COR_CIANO_NEON : COR_BORDA_SUTIL, COR_INPUT_BG);
            size_t slen = str_len(senha);
            for (size_t i = 0; i < slen; i++) mascara[i] = '*';
            mascara[slen] = 0;
            gpu_escrever_texto(mascara, input_x + 10, pass_y + 8, COR_TEXTO_BRANCO);
            if (campo_ativo == 1) {
                gpu_escrever_texto("_", input_x + 10 + (int)slen * 8, pass_y + 8, COR_CIANO_NEON);
            }

            desenhar_retangulo_solido(input_x, btn_y, input_w, 36, COR_ROXO_NEON);
            escrever_texto_centralizado("[ ENTER / CLIQUE ] ENTRAR", card_x + (card_w / 2), btn_y + 10, COR_TEXTO_BRANCO);

            if (erro_login) {
                escrever_texto_centralizado("Usuario ou senha invalidos!", card_x + (card_w / 2), card_y + 262, COR_VERMELHO_ALERTA);
            } else {
                escrever_texto_centralizado("[TAB / SETAS] Alternar  |  [ENTER] Acessar", card_x + (card_w / 2), card_y + 262, COR_TEXTO_SUAVE);
            }

            backbuffer_apresentar_frame(L, A);
            cursor_desenhar_novo();
            precisa_redesenhar = 0;
        }

        ws_atualizar_cursor();

        int mx, my, mb;
        obter_estado_mouse(&mx, &my, &mb);
        int clique_esq = (mb & 0x01) && !(btn_ant & 0x01);
        btn_ant = mb;

        int submeter_login = 0;
        if (clique_esq) {
            if (ponto_no_retangulo(mx, my, input_x, user_y, input_w, input_h)) {
                campo_ativo = 0;
                precisa_redesenhar = 1;
            } else if (ponto_no_retangulo(mx, my, input_x, pass_y, input_w, input_h)) {
                campo_ativo = 1;
                precisa_redesenhar = 1;
            } else if (ponto_no_retangulo(mx, my, input_x, btn_y, input_w, 36)) {
                submeter_login = 1;
            }
        }

        char tecla;
        while ((tecla = ler_tecla_ps2()) != 0) {
            if (tecla == '\t') {
                campo_ativo = !campo_ativo;
                erro_login = 0;
                precisa_redesenhar = 1;
            } else if (tecla == '\n') {
                submeter_login = 1;
            } else if (tecla == '\b') {
                char *alvo = (campo_ativo == 0) ? usuario : senha;
                size_t len = str_len(alvo);
                if (len > 0) alvo[len - 1] = 0;
                erro_login = 0;
                precisa_redesenhar = 1;
            } else if (tecla >= 32 && tecla <= 126) {
                char *alvo = (campo_ativo == 0) ? usuario : senha;
                size_t len = str_len(alvo);
                if (len < 20) {
                    alvo[len] = tecla;
                    alvo[len + 1] = 0;
                }
                erro_login = 0;
                precisa_redesenhar = 1;
            }
        }

        if (submeter_login) {
            if (auth_login(usuario, senha) == 0) {
                fyd_zerar_memoria(senha, sizeof(senha));
                fyd_zerar_memoria(mascara, sizeof(mascara));
                cursor_restaurar_fundo();
                return;
            } else {
                fyd_zerar_memoria(senha, sizeof(senha));
                fyd_zerar_memoria(mascara, sizeof(mascara));
                erro_login = 1;
                precisa_redesenhar = 1;
            }
        }

        descansar_cpu_hlt();
    }
}

//painel de controle
//#define FYD_LAYOUT_TECLADO_ABNT2 1

typedef struct {
    int  aberta;
    int  x, y, w, h;
    int  arrastando;
    int  drag_off_x;
    int  drag_off_y;
    int  aba_ativa;
    int  layout_teclado;
    int  idioma_ativo;
    int  travar_solicitado;
    char teste_teclado[36];
    char novo_user[20];
    char novo_pass[20];
    int  novo_nivel_admin;
    int  campo_cadastro; /* 0 = usuario, 1 = senha */
    char msg_status[52];
} PainelControleWin7;

static PainelControleWin7 g_painel_win7 = {
    .aberta = 0,
    .x = 110, .y = 60, .w = 640, .h = 416,
    .arrastando = 0,
    .drag_off_x = 0,
    .drag_off_y = 0,
    .aba_ativa = PAINEL_ABA_SESSAO,
    .layout_teclado = FYD_LAYOUT_TECLADO_ABNT2,
    .idioma_ativo = IDIOMA_PT_BR,
    .travar_solicitado = 0,
    .teste_teclado = "",
    .novo_user = "",
    .novo_pass = "",
    .novo_nivel_admin = 0,
    .campo_cadastro = 0,
    .msg_status = "Painel de Controle pronto"
};

static const char *painel_nome_nivel(int nivel) {
    if (nivel >= FYD_PERM_ROOT)  return "ROOT";
    if (nivel >= FYD_PERM_ADMIN) return "ADMINISTRADOR";
    if (nivel > FYD_PERM_CONVIDADO) return "USUARIO PADRAO";
    return "CONVIDADO";
}

static void painel_win7_abrir(void) {
    g_painel_win7.aberta = 1;
    g_painel_win7.travar_solicitado = 0;
    fyd_strncpy(g_painel_win7.msg_status,
                (g_painel_win7.idioma_ativo == IDIOMA_EN_US)
                    ? "Control Panel ready"
                    : "Painel de Controle pronto",
                sizeof(g_painel_win7.msg_status));
}

static void painel_win7_desenhar(void) {
    if (!g_painel_win7.aberta) return;

    int px = g_painel_win7.x;
    int py = g_painel_win7.y;
    int pw = g_painel_win7.w;
    int ph = g_painel_win7.h;
    int en = (g_painel_win7.idioma_ativo == IDIOMA_EN_US);

    /* Janela estilo Windows 7 com barra de título e duas colunas */
    desenhar_caixa_com_borda(px, py, pw, ph, 2, COR_ROXO_NEON, COR_CARD);
    desenhar_retangulo_solido(px + 2, py + 2, pw - 4, 28, COR_PAINEL);
    gpu_desenhar_icone(icone_config, px + 10, py + 6, ICONE_TAM, ICONE_TAM);
    gpu_escrever_texto(en ? "Control Panel - FydelisTech OS" : "Painel de Controle - FydelisTech OS",
                       px + 36, py + 8, COR_CIANO_NEON);

    /* Botão Fechar [X] */
    desenhar_retangulo_solido(px + pw - 26, py + 5, 20, 20, COR_VERMELHO_ALERTA);
    gpu_escrever_texto("X", px + pw - 20, py + 7, COR_TEXTO_BRANCO);

    int corpo_y = py + 32;
    int corpo_h = ph - 56;
    int nav_w   = 188;

    /* Coluna esquerda (estilo tarefas/categorias do Windows 7) */
    desenhar_retangulo_solido(px + 2, corpo_y, nav_w, corpo_h, COR_PAINEL_SEC);
    desenhar_retangulo_solido(px + 2 + nav_w, corpo_y, 1, corpo_h, COR_BORDA_SUTIL);

    gpu_escrever_texto(en ? "CATEGORIES" : "CATEGORIAS", px + 14, corpo_y + 12, COR_ROXO_CLARO);

    const char *abas_rotulos[3];
    abas_rotulos[0] = en ? "User & Session" : "Sessao & Usuario";
    abas_rotulos[1] = en ? "Keyboard"       : "Teclado";
    abas_rotulos[2] = en ? "Language"       : "Idioma";

    for (int i = 0; i < 3; i++) {
        int by = corpo_y + 38 + (i * 42);
        int ativa = (g_painel_win7.aba_ativa == i);
        desenhar_caixa_com_borda(px + 10, by, nav_w - 18, 34, 1,
            ativa ? COR_CIANO_NEON : COR_BORDA_SUTIL,
            ativa ? COR_HOVER : COR_CARD);
        gpu_escrever_texto(abas_rotulos[i], px + 18, by + 9,
                           ativa ? COR_CIANO_NEON : COR_TEXTO_BRANCO);
    }

    /* Coluna direita (conteúdo da aba selecionada) */
    int cx = px + nav_w + 18;
    int cy = corpo_y + 14;
    int cw = pw - nav_w - 32;

    if (g_painel_win7.aba_ativa == PAINEL_ABA_SESSAO) {
        const FydSessaoAtiva *s = auth_sessao_atual();
        const char *nome_u = (s && s->autenticado && s->usuario[0]) ? s->usuario : "convidado";
        int nivel_u = (s && s->autenticado) ? (int)s->nivel : FYD_PERM_CONVIDADO;

        gpu_escrever_texto(en ? "Active User Session" : "Sessao do Usuario Atual", cx, cy, COR_CIANO_NEON);
        cy += 24;

        desenhar_caixa_com_borda(cx, cy, cw, 82, 1, COR_BORDA_SUTIL, COR_INPUT_BG);
        gpu_escrever_texto(en ? "User   : " : "Usuario: ", cx + 12, cy + 12, COR_TEXTO_SUAVE);
        gpu_escrever_texto(nome_u, cx + 84, cy + 12, COR_VERDE_NEON);

        gpu_escrever_texto(en ? "Role   : " : "Perfil : ", cx + 12, cy + 34, COR_TEXTO_SUAVE);
        gpu_escrever_texto(painel_nome_nivel(nivel_u), cx + 84, cy + 34, COR_ROXO_CLARO);

        gpu_escrever_texto(en ? "Status : " : "Estado : ", cx + 12, cy + 56, COR_TEXTO_SUAVE);
        gpu_escrever_texto((s && s->autenticado) ? "AUTENTICADO (fydperm)" : "SEM SESSAO",
                           cx + 84, cy + 56, (s && s->autenticado) ? COR_CIANO_NEON : COR_VERMELHO_ALERTA);

        cy += 94;
        /* Botão Travar Sessão */
        desenhar_caixa_com_borda(cx, cy, 175, 30, 1, COR_VERMELHO_ALERTA, COR_CARD);
        gpu_escrever_texto(en ? "Lock Session" : "Travar Sessao", cx + 24, cy + 7, COR_VERMELHO_ALERTA);

        cy += 42;
        if (fydperm_pode_cadastrar_usuario()) {
            gpu_escrever_texto(en ? "Create New User (Admin)" : "Cadastrar Novo Usuario (Admin)",
                               cx, cy, COR_CIANO_NEON);
            cy += 22;

            gpu_escrever_texto(en ? "User:" : "User:", cx, cy + 5, COR_TEXTO_SUAVE);
            desenhar_caixa_com_borda(cx + 48, cy, 130, 24, 1,
                (g_painel_win7.campo_cadastro == 0) ? COR_CIANO_NEON : COR_BORDA_SUTIL, COR_INPUT_BG);
            gpu_escrever_texto(g_painel_win7.novo_user, cx + 54, cy + 4, COR_TEXTO_BRANCO);

            gpu_escrever_texto(en ? "Pass:" : "Pass:", cx + 186, cy + 5, COR_TEXTO_SUAVE);
            desenhar_caixa_com_borda(cx + 234, cy, 130, 24, 1,
                (g_painel_win7.campo_cadastro == 1) ? COR_CIANO_NEON : COR_BORDA_SUTIL, COR_INPUT_BG);
            gpu_escrever_texto(g_painel_win7.novo_pass, cx + 240, cy + 4, COR_TEXTO_BRANCO);

            cy += 32;
            desenhar_caixa_com_borda(cx, cy, 135, 26, 1, COR_ROXO_NEON,
                g_painel_win7.novo_nivel_admin ? COR_HOVER : COR_CARD);
            gpu_escrever_texto(g_painel_win7.novo_nivel_admin ? "Nivel: ADMIN" : "Nivel: USER",
                               cx + 12, cy + 5, COR_CIANO_NEON);

            desenhar_caixa_com_borda(cx + 146, cy, 150, 26, 1, COR_CIANO_NEON, COR_HOVER);
            gpu_escrever_texto(en ? "Save User" : "Criar Usuario", cx + 170, cy + 5, COR_VERDE_NEON);
        } else {
            gpu_escrever_texto(en ? "Admin privilege required to add users."
                                  : "Permissao ADMIN necessaria para criar usuarios.",
                               cx, cy, COR_TEXTO_SUAVE);
        }
    } else if (g_painel_win7.aba_ativa == PAINEL_ABA_TECLADO) {
        gpu_escrever_texto(en ? "Keyboard Layout & PS/2 Test" : "Layout de Teclado & Teste PS/2",
                           cx, cy, COR_CIANO_NEON);
        cy += 26;

        int abnt = (g_painel_win7.layout_teclado == FYD_LAYOUT_TECLADO_ABNT2);
        desenhar_caixa_com_borda(cx, cy, 190, 30, 1,
            abnt ? COR_CIANO_NEON : COR_BORDA_SUTIL, abnt ? COR_HOVER : COR_CARD);
        gpu_escrever_texto("PT-BR / ABNT2", cx + 36, cy + 7, abnt ? COR_CIANO_NEON : COR_TEXTO_BRANCO);

        desenhar_caixa_com_borda(cx + 202, cy, 190, 30, 1,
            !abnt ? COR_CIANO_NEON : COR_BORDA_SUTIL, !abnt ? COR_HOVER : COR_CARD);
        gpu_escrever_texto("EN-US / QWERTY", cx + 236, cy + 7, !abnt ? COR_CIANO_NEON : COR_TEXTO_BRANCO);

        cy += 46;
        gpu_escrever_texto(en ? "Type here to test keys (Backspace clears):"
                              : "Digite para testar teclas (Backspace apaga):",
                           cx, cy, COR_TEXTO_SUAVE);
        cy += 22;
        desenhar_caixa_com_borda(cx, cy, cw, 30, 1, COR_CIANO_NEON, COR_INPUT_BG);
        gpu_escrever_texto(g_painel_win7.teste_teclado, cx + 10, cy + 7, COR_VERDE_NEON);
    } else if (g_painel_win7.aba_ativa == PAINEL_ABA_IDIOMA) {
        gpu_escrever_texto(en ? "System Language & Region" : "Idioma e Regiao do Sistema",
                           cx, cy, COR_CIANO_NEON);
        cy += 26;

        int pt = (g_painel_win7.idioma_ativo == IDIOMA_PT_BR);
        desenhar_caixa_com_borda(cx, cy, 195, 32, 1,
            pt ? COR_CIANO_NEON : COR_BORDA_SUTIL, pt ? COR_HOVER : COR_CARD);
        gpu_escrever_texto("Portugues (Brasil)", cx + 22, cy + 8, pt ? COR_CIANO_NEON : COR_TEXTO_BRANCO);

        desenhar_caixa_com_borda(cx + 207, cy, 195, 32, 1,
            !pt ? COR_CIANO_NEON : COR_BORDA_SUTIL, !pt ? COR_HOVER : COR_CARD);
        gpu_escrever_texto("English (United States)", cx + 216, cy + 8, !pt ? COR_CIANO_NEON : COR_TEXTO_BRANCO);

        cy += 50;
        gpu_escrever_texto(en ? "Locale : en_US.UTF-8 (Salvador / TZ)"
                              : "Regiao : pt_BR (Salvador - Bahia)",
                           cx, cy, COR_TEXTO_SUAVE);
    }

    /* Barra de status inferior */
    desenhar_retangulo_solido(px + 2, py + ph - 22, pw - 4, 20, COR_PAINEL);
    gpu_escrever_texto(g_painel_win7.msg_status, cx, py + ph - 18, COR_CIANO_NEON);
}

static int painel_win7_processar_clique(int mx, int my) {
    if (!g_painel_win7.aberta) return 0;

    int px = g_painel_win7.x;
    int py = g_painel_win7.y;
    int pw = g_painel_win7.w;
    int ph = g_painel_win7.h;

    if (!ponto_no_retangulo(mx, my, px, py, pw, ph)) {
        return 0;
    }

    /* Botão [X] fechar */
    if (ponto_no_retangulo(mx, my, px + pw - 26, py + 5, 20, 20)) {
        g_painel_win7.aberta = 0;
        return 1;
    }

    int corpo_y = py + 32;
    int nav_w   = 188;

    /* Seleção de categoria na coluna esquerda */
    for (int i = 0; i < 3; i++) {
        int by = corpo_y + 38 + (i * 42);
        if (ponto_no_retangulo(mx, my, px + 10, by, nav_w - 18, 34)) {
            g_painel_win7.aba_ativa = i;
            return 1;
        }
    }

    int cx = px + nav_w + 18;
    int cy = corpo_y + 14;

    if (g_painel_win7.aba_ativa == PAINEL_ABA_SESSAO) {
        int lock_y = cy + 118;
        if (ponto_no_retangulo(mx, my, cx, lock_y, 175, 30)) {
            auth_logout();
            g_painel_win7.aberta = 0;
            g_painel_win7.travar_solicitado = 1;
            return 1;
        }

        if (fydperm_pode_cadastrar_usuario()) {
            int cad_y = lock_y + 64;
            if (ponto_no_retangulo(mx, my, cx + 48, cad_y, 130, 24)) {
                g_painel_win7.campo_cadastro = 0;
                return 1;
            }
            if (ponto_no_retangulo(mx, my, cx + 234, cad_y, 130, 24)) {
                g_painel_win7.campo_cadastro = 1;
                return 1;
            }
            int btn_row_y = cad_y + 32;
            if (ponto_no_retangulo(mx, my, cx, btn_row_y, 135, 26)) {
                g_painel_win7.novo_nivel_admin = !g_painel_win7.novo_nivel_admin;
                return 1;
            }
            if (ponto_no_retangulo(mx, my, cx + 146, btn_row_y, 150, 26)) {
                FydPermNivel nv = g_painel_win7.novo_nivel_admin ? FYD_PERM_ADMIN : FYD_PERM_USUARIO;
                int rc = auth_registrar_usuario(g_painel_win7.novo_user, g_painel_win7.novo_pass, nv);
                if (rc == 0) {
                    fyd_zerar_memoria(g_painel_win7.novo_user, sizeof(g_painel_win7.novo_user));
                    fyd_zerar_memoria(g_painel_win7.novo_pass, sizeof(g_painel_win7.novo_pass));
                    fyd_strncpy(g_painel_win7.msg_status, "Usuario criado com sucesso!", sizeof(g_painel_win7.msg_status));
                } else {
                    fyd_strncpy(g_painel_win7.msg_status, "Falha ao criar usuario (verifique dados)", sizeof(g_painel_win7.msg_status));
                }
                return 1;
            }
        }
    } else if (g_painel_win7.aba_ativa == PAINEL_ABA_TECLADO) {
        int btn_y = cy + 26;
        if (ponto_no_retangulo(mx, my, cx, btn_y, 190, 30)) {
            g_painel_win7.layout_teclado = FYD_LAYOUT_TECLADO_ABNT2;
            fyd_strncpy(g_painel_win7.msg_status, "Layout ativo: PT-BR / ABNT2", sizeof(g_painel_win7.msg_status));
            return 1;
        }
        if (ponto_no_retangulo(mx, my, cx + 202, btn_y, 190, 30)) {
            g_painel_win7.layout_teclado = FYD_LAYOUT_TECLADO_US;
            fyd_strncpy(g_painel_win7.msg_status, "Layout ativo: EN-US / QWERTY", sizeof(g_painel_win7.msg_status));
            return 1;
        }
    } else if (g_painel_win7.aba_ativa == PAINEL_ABA_IDIOMA) {
        int btn_y = cy + 26;
        if (ponto_no_retangulo(mx, my, cx, btn_y, 195, 32)) {
            g_painel_win7.idioma_ativo = IDIOMA_PT_BR;
            fyd_strncpy(g_painel_win7.msg_status, "Idioma alterado para Portugues (Brasil)", sizeof(g_painel_win7.msg_status));
            return 1;
        }
        if (ponto_no_retangulo(mx, my, cx + 207, btn_y, 195, 32)) {
            g_painel_win7.idioma_ativo = IDIOMA_EN_US;
            fyd_strncpy(g_painel_win7.msg_status, "Language changed to English (US)", sizeof(g_painel_win7.msg_status));
            return 1;
        }
    }

    return 1;
}

static void painel_win7_on_key(char tecla) {
    if (!g_painel_win7.aberta) return;

    if (tecla == 27) {
        g_painel_win7.aberta = 0;
        return;
    }

    if (g_painel_win7.aba_ativa == PAINEL_ABA_TECLADO) {
        size_t len = str_len(g_painel_win7.teste_teclado);
        if (tecla == '\b') {
            if (len > 0) g_painel_win7.teste_teclado[len - 1] = '\0';
        } else if (tecla >= 32 && tecla <= 126 && len < sizeof(g_painel_win7.teste_teclado) - 1) {
            g_painel_win7.teste_teclado[len] = tecla;
            g_painel_win7.teste_teclado[len + 1] = '\0';
        }
        return;
    }

    if (g_painel_win7.aba_ativa == PAINEL_ABA_SESSAO && fydperm_pode_cadastrar_usuario()) {
        if (tecla == '\t') {
            g_painel_win7.campo_cadastro = !g_painel_win7.campo_cadastro;
            return;
        }
        char *alvo = (g_painel_win7.campo_cadastro == 0) ? g_painel_win7.novo_user : g_painel_win7.novo_pass;
        size_t max_c = (g_painel_win7.campo_cadastro == 0)
            ? sizeof(g_painel_win7.novo_user) - 1
            : sizeof(g_painel_win7.novo_pass) - 1;
        size_t len = str_len(alvo);
        if (tecla == '\b') {
            if (len > 0) alvo[len - 1] = '\0';
        } else if (tecla >= 32 && tecla <= 126 && len < max_c) {
            alvo[len] = tecla;
            alvo[len + 1] = '\0';
        }
    }
}

void gui_retangulo(int x, int y, int w, int h, uint32_t cor) {
    desenhar_retangulo_solido(x, y, w, h, cor);
}

void gui_borda(int x, int y, int w, int h, uint32_t cor) {
    desenhar_retangulo_solido(x, y, w, 1, cor);
    desenhar_retangulo_solido(x, y + h - 1, w, 1, cor);
    desenhar_retangulo_solido(x, y, 1, h, cor);
    desenhar_retangulo_solido(x + w - 1, y, 1, h, cor);
}

void gui_texto(int x, int y, const char *str, uint32_t cor) {
    gpu_escrever_texto(str, x, y, cor);
}

/* ============================================================================
- POPUP DE REDE CABEADA (ETH0 - IP FIXO / DHCP)
- ============================================================================ */
#define ETH_POP_W 296
#define ETH_POP_H 256

static int  eth_popup_aberto = 0;
static int  eth_campo_ativo  = 0; /* 0 = IP, 1 = Mascara, 2 = Gateway */
static char eth_ip_str[20]   = "10.0.2.15";
static char eth_mask_str[20] = "255.255.255.0";
static char eth_gw_str[20]   = "10.0.2.2";
static char eth_status_msg[44] = "Modo: DHCP Automatico";

extern void dhcp_cliente_resetar(void);

static void eth_copiar_str(char *dst, const char *src, int max) {
    int i = 0;
    while (src && src[i] && i < max - 1) {
        dst[i] = src[i];
        i++;
    }
    dst[i] = '\0';
}

static int eth_str_len(const char *s) {
    int n = 0;
    while (s[n]) n++;
    return n;
}

static void eth_popup_alternar(void) {
    eth_popup_aberto = !eth_popup_aberto;
    if (eth_popup_aberto) {
        wifi_popup_aberto = 0;
    }
}

static void eth_popup_desenhar(void) {
    if (!eth_popup_aberto) return;

    int px = (int)fb_largura - ETH_POP_W - 14;
    int py = (int)fb_altura - ETH_POP_H - 38;
    if (px < 10) px = 10;
    if (py < 10) py = 10;

    gui_retangulo(px, py, ETH_POP_W, ETH_POP_H, WIFI_COR_FUNDO);
    gui_borda(px, py, ETH_POP_W, ETH_POP_H, WIFI_COR_CIANO);
    gui_retangulo(px + 2, py + 2, ETH_POP_W - 4, 24, WIFI_COR_BARRA);
    gui_texto(px + 10, py + 6, "Rede Cabeada (eth0 - E1000)", WIFI_COR_CIANO);

    /* Botao [X] */
    gui_retangulo(px + ETH_POP_W - 22, py + 4, 18, 18, WIFI_COR_VERMELHO);
    gui_texto(px + ETH_POP_W - 17, py + 5, "X", WIFI_COR_TEXTO);

    const char *labels[3] = { "Endereco IP:", "Mascara Rede:", "Gateway:" };
    char *campos[3] = { eth_ip_str, eth_mask_str, eth_gw_str };

    int cy = py + 34;
    for (int i = 0; i < 3; i++) {
        gui_texto(px + 12, cy, labels[i], WIFI_COR_SUAVE);
        cy += 16;

        int box_x = px + 12;
        int box_w = ETH_POP_W - 24;
        gui_retangulo(box_x, cy, box_w, 22, WIFI_COR_ITEM);
        gui_borda(box_x, cy, box_w, 22, (eth_campo_ativo == i) ? WIFI_COR_CIANO : 0xFF4C2889);
        gui_texto(box_x + 8, cy + 4, campos[i], WIFI_COR_TEXTO);

        if (eth_campo_ativo == i) {
            int len = eth_str_len(campos[i]);
            gui_texto(box_x + 8 + (len * 8), cy + 4, "_", WIFI_COR_CIANO);
        }
        cy += 28;
    }

    /* Botao [Aplicar IP Fixo] */
    int btn_y = py + 196;
    gui_retangulo(px + 12, btn_y, 144, 24, WIFI_COR_ITEM_SEL);
    gui_borda(px + 12, btn_y, 144, 24, WIFI_COR_VERDE);
    gui_texto(px + 20, btn_y + 4, "Aplicar IP Fixo", WIFI_COR_VERDE);

    /* Botao [Usar DHCP] */
    gui_retangulo(px + 164, btn_y, 120, 24, WIFI_COR_ITEM_SEL);
    gui_borda(px + 164, btn_y, 120, 24, WIFI_COR_CIANO);
    gui_texto(px + 184, btn_y + 4, "Usar DHCP", WIFI_COR_CIANO);

    /* Barra de status */
    gui_retangulo(px + 2, py + ETH_POP_H - 22, ETH_POP_W - 4, 20, WIFI_COR_BARRA);
    gui_texto(px + 10, py + ETH_POP_H - 18, eth_status_msg, WIFI_COR_VERDE);
}

static int eth_popup_processar_clique(int mx, int my) {
    if (!eth_popup_aberto) return 0;

    int px = (int)fb_largura - ETH_POP_W - 14;
    int py = (int)fb_altura - ETH_POP_H - 38;
    if (px < 10) px = 10;
    if (py < 10) py = 10;

    if (mx < px || mx > px + ETH_POP_W || my < py || my > py + ETH_POP_H) {
        eth_popup_aberto = 0;
        return 0;
    }

    int rx = mx - px;
    int ry = my - py;

    /* Fechar [X] */
    if (rx >= ETH_POP_W - 22 && rx <= ETH_POP_W - 4 && ry >= 4 && ry <= 22) {
        eth_popup_aberto = 0;
        return 1;
    }

    /* Selecao dos 3 campos de texto */
    int cy = 50;
    for (int i = 0; i < 3; i++) {
        if (rx >= 12 && rx <= ETH_POP_W - 12 && ry >= cy && ry <= cy + 22) {
            eth_campo_ativo = i;
            return 1;
        }
        cy += 44;
    }

    /* Botao [Aplicar IP Fixo] */
    if (rx >= 12 && rx <= 156 && ry >= 196 && ry <= 220) {
        eth_copiar_str(eth_status_msg, "IP Fixo: ", sizeof(eth_status_msg));
        int p = eth_str_len(eth_status_msg);
        eth_copiar_str(eth_status_msg + p, eth_ip_str, sizeof(eth_status_msg) - p);
        return 1;
    }

    /* Botao [Usar DHCP] */
    if (rx >= 164 && rx <= 284 && ry >= 196 && ry <= 220) {
        dhcp_cliente_resetar();
        dhcp_cliente_iniciar();
        eth_copiar_str(eth_status_msg, "DHCP solicitado na eth0", sizeof(eth_status_msg));
        return 1;
    }

    return 1;
}

static void eth_popup_on_key(char tecla) {
    char *alvo = (eth_campo_ativo == 0) ? eth_ip_str :
                 (eth_campo_ativo == 1) ? eth_mask_str : eth_gw_str;
    int len = eth_str_len(alvo);

    if (tecla == 27) {
        eth_popup_aberto = 0;
    } else if (tecla == '\t' || tecla == '\n') {
        eth_campo_ativo = (eth_campo_ativo + 1) % 3;
    } else if (tecla == '\b') {
        if (len > 0) alvo[len - 1] = '\0';
    } else if (((tecla >= '0' && tecla <= '9') || tecla == '.') && len < 15) {
        alvo[len] = tecla;
        alvo[len + 1] = '\0';
    }
}

// Bloco Wifi
static void wifi_copiar_str(char *dst, const char *src, int max) {
    int i = 0;
    while (src && src[i] && i < max - 1) {
        dst[i] = src[i];
        i++;
    }
    dst[i] = '\0';
}

/* Alterna abertura do popup ao clicar no ícone do Systray */
void wifi_popup_alternar(void) {
    wifi_popup_aberto = !wifi_popup_aberto;
    if (wifi_popup_aberto) {
        if (!wifi_detectar_placa()) {
            wifi_copiar_str(wifi_status_msg, "Placa Wi-Fi nao detectada", sizeof(wifi_status_msg));
            return;
        }
        wifi_inicializar();
        sys_wifi_scan();
        wifi_copiar_str(wifi_status_msg, "Redes atualizadas", sizeof(wifi_status_msg));
    }
}

/* Renderiza o popup acima da barra de tarefas no canto direito */
void wifi_popup_desenhar(void) {
    if (!wifi_popup_aberto) return;

    int px = (int)fb_largura - WIFI_POP_W - 14;
    int py = (int)fb_altura - WIFI_POP_H - 38; /* Acima da barra inferior */
    if (px < 10) px = 10;
    if (py < 10) py = 10;

    /* Moldura principal e cabeçalho */
    gui_retangulo(px, py, WIFI_POP_W, WIFI_POP_H, WIFI_COR_FUNDO);
    gui_borda(px, py, WIFI_POP_W, WIFI_POP_H, WIFI_COR_BORDA);
    gui_retangulo(px + 2, py + 2, WIFI_POP_W - 4, 24, WIFI_COR_BARRA);
    gui_texto(px + 10, py + 6, "Wi-Fi FydelisNet", WIFI_COR_CIANO);

    /* Botão [X] fechar */
    gui_retangulo(px + WIFI_POP_W - 22, py + 4, 18, 18, WIFI_COR_VERMELHO);
    gui_texto(px + WIFI_POP_W - 17, py + 5, "X", WIFI_COR_TEXTO);

    /* Botão [Escanear] */
    gui_retangulo(px + 10, py + 32, 92, 22, WIFI_COR_ITEM_SEL);
    gui_borda(px + 10, py + 32, 92, 22, WIFI_COR_CIANO);
    gui_texto(px + 20, py + 36, "Escanear", WIFI_COR_CIANO);

    /* Botão [Desconectar] */
    gui_retangulo(px + WIFI_POP_W - 112, py + 32, 102, 22, WIFI_COR_ITEM_SEL);
    gui_borda(px + WIFI_POP_W - 112, py + 32, 102, 22, WIFI_COR_AMARELO);
    gui_texto(px + WIFI_POP_W - 104, py + 36, "Desconectar", WIFI_COR_AMARELO);

    /* Lista de redes encontradas */
    int ly = py + 62;
    int exibidas = 0;

    for (int i = 0; i < MAX_REDES_WIFI && exibidas < WIFI_MAX_VISIVEIS; i++) {
        if (wifi_scan_lista[i].ssid[0] == '\0') continue;

        uint32_t bg = (i == wifi_indice_selecionado) ? WIFI_COR_ITEM_SEL : WIFI_COR_ITEM;
        gui_retangulo(px + 10, ly, WIFI_POP_W - 20, 24, bg);
        gui_borda(px + 10, ly, WIFI_POP_W - 20, 24, 0xFF4C2889);

        /* Nome da rede (SSID) */
        gui_texto(px + 16, ly + 5, wifi_scan_lista[i].ssid, WIFI_COR_TEXTO);

        /* Tipo de segurança à direita */
        if (wifi_scan_lista[i].seguranca == 0) {
            gui_texto(px + WIFI_POP_W - 72, ly + 5, "Aberta", WIFI_COR_VERDE);
        } else {
            gui_texto(px + WIFI_POP_W - 60, ly + 5, "WPA2", WIFI_COR_AMARELO);
        }

        ly += 27;
        exibidas++;
    }

    if (exibidas == 0) {
        gui_texto(px + 16, py + 80, "Nenhuma rede Wi-Fi encontrada.", WIFI_COR_SUAVE);
    }

    /* Barra de status inferior do popup */
    gui_retangulo(px + 2, py + WIFI_POP_H - 22, WIFI_POP_W - 4, 20, WIFI_COR_BARRA);
    gui_texto(px + 10, py + WIFI_POP_H - 18, wifi_status_msg, WIFI_COR_VERDE);
}

/* Trata cliques dentro do popup (retorna 1 se consumiu o clique, 0 caso contrário) */
int wifi_popup_processar_clique(int mx, int my) {
    if (!wifi_popup_aberto) return 0;

    int px = (int)fb_largura - WIFI_POP_W - 14;
    int py = (int)fb_altura - WIFI_POP_H - 38;
    if (px < 10) px = 10;
    if (py < 10) py = 10;

    /* Se clicou fora do popup, fecha automaticamente */
    if (mx < px || mx > px + WIFI_POP_W || my < py || my > py + WIFI_POP_H) {
        wifi_popup_aberto = 0;
        return 0;
    }

    int rx = mx - px;
    int ry = my - py;

    /* Clique no [X] */
    if (rx >= WIFI_POP_W - 22 && rx <= WIFI_POP_W - 4 && ry >= 4 && ry <= 22) {
        wifi_popup_aberto = 0;
        return 1;
    }

    /* Clique em [Escanear] */
    if (rx >= 10 && rx <= 102 && ry >= 32 && ry <= 54) {
        if (wifi_detectar_placa()) {
            wifi_inicializar();
            sys_wifi_scan();
            wifi_copiar_str(wifi_status_msg, "Escaneamento concluido", sizeof(wifi_status_msg));
        } else {
            wifi_copiar_str(wifi_status_msg, "Sem placa Wi-Fi PCI", sizeof(wifi_status_msg));
        }
        return 1;
    }

    /* Clique em [Desconectar] */
    if (rx >= WIFI_POP_W - 112 && rx <= WIFI_POP_W - 10 && ry >= 32 && ry <= 54) {
        sys_wifi_desconectar();
        wifi_indice_selecionado = -1;
        wifi_copiar_str(wifi_status_msg, "Desconectado", sizeof(wifi_status_msg));
        return 1;
    }

    /* Clique em uma rede da lista para conectar */
    int ly = 62;
    int exibidas = 0;
    for (int i = 0; i < MAX_REDES_WIFI && exibidas < WIFI_MAX_VISIVEIS; i++) {
        if (wifi_scan_lista[i].ssid[0] == '\0') continue;

        if (rx >= 10 && rx <= WIFI_POP_W - 10 && ry >= ly && ry <= ly + 24) {
            wifi_indice_selecionado = i;
            if (sys_wifi_conectar(wifi_scan_lista[i].ssid)) {
                dhcp_cliente_iniciar();
                wifi_copiar_str(wifi_status_msg, "Conectado via DHCP!", sizeof(wifi_status_msg));
            } else {
                wifi_copiar_str(wifi_status_msg, "Falha ao conectar na rede", sizeof(wifi_status_msg));
            }
            return 1;
        }
        ly += 27;
        exibidas++;
    }

    return 1;
}

/* ============================================================================
- MENU INICIAR ORGANIZADO POR CATEGORIA
- ============================================================================ */
static void desenhar_menu_iniciar_categorizado(int menu_x, int menu_y, int menu_w, int menu_h, int mx, int my) {
    int cab_h     = 36;
    int rodape_h  = 40;
    int col_esq_w = 215;
    int col_dir_w = menu_w - col_esq_w;
    int corpo_y   = menu_y + cab_h;
    int corpo_h   = menu_h - cab_h - rodape_h;

    desenhar_caixa_com_borda(menu_x, menu_y, menu_w, menu_h, 2, COR_CIANO_NEON, COR_PAINEL);
    desenhar_retangulo_solido(menu_x + col_esq_w, corpo_y, col_dir_w - 2, corpo_h, COR_PAINEL_SEC);
    desenhar_retangulo_solido(menu_x + col_esq_w, corpo_y, 1, corpo_h, COR_BORDA_SUTIL);

    desenhar_retangulo_solido(menu_x + 2, menu_y + 2, menu_w - 4, cab_h - 2, COR_CARD);
    gpu_desenhar_icone(icone_fydelis_f, menu_x + 10, menu_y + 8, ICONE_TAM, ICONE_TAM);
    gpu_escrever_texto("FYDELISTECH OS v4.2", menu_x + 38, menu_y + 10, COR_CIANO_NEON);
    gpu_escrever_texto("admin@fydelis", menu_x + menu_w - 116, menu_y + 10, COR_VERDE_NEON);

    gpu_escrever_texto("APLICATIVOS", menu_x + 14, corpo_y + 8, COR_ROXO_CLARO);
    gpu_escrever_texto("SISTEMA & CONFIG", menu_x + col_esq_w + 12, corpo_y + 8, COR_ROXO_CLARO);

    int idx_esq = 0;
    int idx_dir = 0;
    for (int i = 0; i < TOTAL_ITENS_MENU; i++) {
        int ix, iy, iw;
        int ih = 32;

        if (itens_menu[i].coluna == 0) {
            ix = menu_x + 10;
            iy = corpo_y + 28 + (idx_esq * 36);
            iw = col_esq_w - 20;
            idx_esq++;
        } else {
            ix = menu_x + col_esq_w + 10;
            iy = corpo_y + 28 + (idx_dir * 36);
            iw = col_dir_w - 20;
            idx_dir++;
        }

        int hover = ponto_no_retangulo(mx, my, ix, iy, iw, ih);
        if (hover) {
            desenhar_caixa_com_borda(ix, iy, iw, ih, 1, COR_CIANO_NEON, COR_HOVER);
        }

        gpu_desenhar_icone(itens_menu[i].icone, ix + 6, iy + 6, ICONE_TAM, ICONE_TAM);
        gpu_escrever_texto(itens_menu[i].rotulo, ix + 32, iy + 8,
                           hover ? COR_CIANO_NEON : COR_TEXTO_BRANCO);
    }

    int rod_y = menu_y + menu_h - rodape_h;
    desenhar_retangulo_solido(menu_x + 2, rod_y, menu_w - 4, 1, COR_BORDA_SUTIL);

    int btn_w = (menu_w - 28) / 3;
    int btn_h = 28;
    int btn_y = rod_y + 6;

    int bx1 = menu_x + 8;
    int h1  = ponto_no_retangulo(mx, my, bx1, btn_y, btn_w, btn_h);
    desenhar_caixa_com_borda(bx1, btn_y, btn_w, btn_h, 1, COR_ROXO_NEON, h1 ? COR_HOVER : COR_CARD);
    gpu_desenhar_icone(icone_bloquear, bx1 + 6, btn_y + 4, ICONE_TAM, ICONE_TAM);
    gpu_escrever_texto("Travar", bx1 + 30, btn_y + 6, COR_TEXTO_BRANCO);

    int bx2 = bx1 + btn_w + 6;
    int h2  = ponto_no_retangulo(mx, my, bx2, btn_y, btn_w, btn_h);
    desenhar_caixa_com_borda(bx2, btn_y, btn_w, btn_h, 1, COR_CIANO_NEON, h2 ? COR_HOVER : COR_CARD);
    gpu_desenhar_icone(icone_relogio, bx2 + 6, btn_y + 4, ICONE_TAM, ICONE_TAM);
    gpu_escrever_texto("Reiniciar", bx2 + 30, btn_y + 6, COR_CIANO_NEON);

    int bx3 = bx2 + btn_w + 6;
    int h3  = ponto_no_retangulo(mx, my, bx3, btn_y, btn_w, btn_h);
    desenhar_caixa_com_borda(bx3, btn_y, btn_w, btn_h, 1, COR_VERMELHO_ALERTA, h3 ? 0xFF5A1830 : COR_CARD);
    gpu_desenhar_icone(icone_desligar, bx3 + 6, btn_y + 4, ICONE_TAM, ICONE_TAM);
    gpu_escrever_texto("Desligar", bx3 + 30, btn_y + 6, COR_VERMELHO_ALERTA);
}

/* ============================================================================
- TELA 3: ÁREA DE TRABALHO GRÁFICA (Via Disco ATA e Drag sem Rastro)
- ============================================================================ */
static int exibir_desktop_grafico(int L, int A) {
    char res_buf[48];
    char tmp[16];
    char sessao_topo[36];

    char tz_buf[8];
    int offset_fuso = -3;
    if (fyd_cfg_ler_chave(fs_ler_config_padrao(), "timezone", tz_buf, sizeof(tz_buf)) == 0) {
        if (tz_buf[0] == '-' && tz_buf[1] >= '0' && tz_buf[1] <= '9') {
            offset_fuso = -(tz_buf[1] - '0');
        } else if (tz_buf[0] >= '0' && tz_buf[0] <= '9') {
            offset_fuso = (tz_buf[0] - '0');
        }
    }

    int win_w = (L * 64) / 100;
    if (win_w < 500) win_w = 500;
    int win_h = (A * 56) / 100;
    if (win_h < 300) win_h = 300;
    int win_x = (L - win_w) / 2;
    int win_y = (A - win_h) / 2 - 20;

    int janela_aberta  = 1;
    int modo_janela    = MODO_JANELA_SISTEMA;
    int arrastando     = 0;
    int drag_offset_x  = 0;
    int drag_offset_y  = 0;

    int arrastando_calc  = 0;
    int calc_drag_off_x  = 0;
    int calc_drag_off_y  = 0;

    int arrastando_logs  = 0;
    int logs_drag_off_x  = 0;
    int logs_drag_off_y  = 0;

    int arrastando_exp   = 0;
    int exp_drag_off_x   = 0;
    int exp_drag_off_y   = 0;

    int arrastando_brw   = 0;
    int brw_drag_off_x   = 0;
    int brw_drag_off_y   = 0;

    int arrastando_notes = 0;
    int notes_drag_off_x = 0;
    int notes_drag_off_y = 0;

    int taskbar_h      = 38;
    int taskbar_y      = A - taskbar_h;
    int btn_f_x        = 8;
    int btn_f_y        = taskbar_y + 3;
    int btn_f_w        = 42;
    int btn_f_h        = 32;

    int menu_aberto    = 0;
    int menu_x         = 8;
    int menu_w         = 410;
    int menu_h         = 372;
    int menu_y         = taskbar_y - menu_h - 4;

    int precisa_redesenhar = 1;
    int btn_ant        = 0;
    int hover_ant      = -1;

    /* Cache de hardware consultado uma única vez para não travar a interface */
    TelemetriaSistema telemetria;
    inicializar_telemetria(&telemetria, L, A);

    int disco_detectado = telemetria.disco_online;
    int link_rede_ativo = (rede_ler_status_link() != 0);
    int bt_estado       = (int)bt_ler_status();
    int audio_estado    = (int)audio_ler_status();

    fydlog_escrever(LOG_INFO, "Desktop grafico iniciado");
    if (!disco_detectado) {
        fydlog_escrever(LOG_AVISO, "Disco ATA primario nao respondeu");
    }

    RtcDataHora dt_atual;
    rtc_ler_agora(&dt_atual);
    int hora_local = ((int)dt_atual.hora + offset_fuso) % 24;
    if (hora_local < 0) hora_local += 24;
    dt_atual.hora = (uint8_t)hora_local;

    uint8_t min_anterior   = dt_atual.min;
    uint64_t ticks_ant     = timer_ler_ticks();
    uint32_t ciclos_poll   = 0;

    str_copy(res_buf, "Video VESA    : ", sizeof(res_buf));
    num_para_str(L, tmp, sizeof(tmp));
    size_t pos = str_len(res_buf);
    if (pos < sizeof(res_buf) - 1) {
        str_copy(res_buf + pos, tmp, sizeof(res_buf) - pos);
    }
    pos = str_len(res_buf);
    if (pos < sizeof(res_buf) - 1) {
        str_copy(res_buf + pos, "x", sizeof(res_buf) - pos);
    }
    num_para_str(A, tmp, sizeof(tmp));
    pos = str_len(res_buf);
    if (pos < sizeof(res_buf) - 1) {
        str_copy(res_buf + pos, tmp, sizeof(res_buf) - pos);
    }
    pos = str_len(res_buf);
    if (pos < sizeof(res_buf) - 1) {
        str_copy(res_buf + pos, " @ 32-bit", sizeof(res_buf) - pos);
    }

    uint64_t tsc_anterior  = ler_tsc();
    uint64_t ciclos_ativos = 0;

    ws_inicializar();

    while (1) {
        int mx, my, mb;
        obter_estado_mouse(&mx, &my, &mb);

        /* Atualiza RTC e telemetria pontualmente (sem repintar a tela inteira) */
        uint64_t ticks_agora = timer_ler_ticks();
        ciclos_poll++;

        if ((ticks_agora - ticks_ant) >= 300 || ciclos_poll >= 250000) {
            ticks_ant   = ticks_agora;
            ciclos_poll = 0;

            rtc_ler_agora(&dt_atual);
            hora_local = ((int)dt_atual.hora + offset_fuso) % 24;
            if (hora_local < 0) hora_local += 24;
            dt_atual.hora = (uint8_t)hora_local;

            int novo_link  = (rede_ler_status_link() != 0);
            int novo_bt    = (int)bt_ler_status();
            int novo_audio = (int)audio_ler_status();

            uint64_t tsc_agora = ler_tsc();
            uint64_t delta_tsc = tsc_agora - tsc_anterior;
            tsc_anterior = tsc_agora;

            if (delta_tsc > 0) {
                int pct = (int)((ciclos_ativos * 100ULL) / delta_tsc);
                if (pct < 2) pct = 2;
                if (pct > 100) pct = 100;
                if (pct != telemetria.cpu_uso_pct) {
                    telemetria.cpu_uso_pct = pct;
                    if (!menu_aberto) {
                        cursor_restaurar_fundo();
                        desenhar_widgets_sistema(L, &telemetria);
                        cursor_desenhar_novo();
                    }
                }
            }
            ciclos_ativos = 0;

            if (dt_atual.min != min_anterior || novo_link != link_rede_ativo ||
                novo_bt != bt_estado || novo_audio != audio_estado) {
                min_anterior    = dt_atual.min;
                link_rede_ativo = novo_link;
                bt_estado       = novo_bt;
                audio_estado    = novo_audio;
                cursor_restaurar_fundo();
                desenhar_systray(L, taskbar_y, taskbar_h, link_rede_ativo, disco_detectado,
                                 bt_estado, audio_estado, &dt_atual, mx, my);
                cursor_desenhar_novo();
            }
        }

        /* Só redesenha o Menu Iniciar quando estiver aberto e o hover mudar */
        int hover_atual = -1;
        if (menu_aberto && ponto_no_retangulo(mx, my, menu_x, menu_y, menu_w, menu_h)) {
            hover_atual = (my - menu_y) / 16;
            if (hover_atual != hover_ant) {
                hover_ant = hover_atual;
                cursor_restaurar_fundo();
                desenhar_menu_iniciar_categorizado(menu_x, menu_y, menu_w, menu_h, mx, my);
                cursor_desenhar_novo();
            }
        } else {
            hover_ant = -1;
        }

        if (precisa_redesenhar) {
            uint64_t t_frame_ini = ler_tsc();
            cursor_restaurar_fundo();
            backbuffer_iniciar_frame();

            fydperm_obter_rotulo_sessao(sessao_topo, sizeof(sessao_topo), "Sessao: ");

            /* 1. Wallpaper do Desktop carregado do Disco ATA */
            desenhar_background_ata(LBA_BG_DESKTOP, L, A);

            /* 2. Painel Superior */
            desenhar_retangulo_solido(0, 0, L, 32, COR_PAINEL);
            desenhar_retangulo_solido(0, 32, L, 2, COR_ROXO_NEON);
            gpu_escrever_titulo("FYDELISTECHOS", 14, 4, COR_CIANO_NEON);
            gpu_escrever_texto(sessao_topo, L - 196, 8, COR_VERDE_NEON);

            /* 3. Atalhos Rapidos na Area de Trabalho */
            gpu_desenhar_icone(icone_pasta_fechada, 22, 54, ICONE_TAM, ICONE_TAM);
            gpu_escrever_texto("Explorer", 48, 56, COR_TEXTO_BRANCO);

            gpu_desenhar_icone(icone_iniciar, 22, 88, ICONE_TAM, ICONE_TAM);
            gpu_escrever_texto("Aplicativos", 48, 90, COR_CIANO_NEON);

            gpu_desenhar_icone(icone_config, 22, 122, ICONE_TAM, ICONE_TAM);
            gpu_escrever_texto("Configuracoes", 48, 124, COR_TEXTO_SUAVE);

            gpu_desenhar_icone(icone_ethernet, 22, 156, ICONE_TAM, ICONE_TAM);
            gpu_escrever_texto("FydelisBrowser", 48, 158, COR_CIANO_NEON);

            /* 3.1 Widgets de CPU, RAM e Disco Total */
            desenhar_widgets_sistema(L, &telemetria);

            /* 4. Janela Arrastável Dinâmica */
            if (janela_aberta) {
                desenhar_caixa_com_borda(win_x, win_y, win_w, win_h, 2,
                    arrastando ? COR_CIANO_NEON : COR_ROXO_NEON, COR_CARD);

                desenhar_retangulo_solido(win_x + 2, win_y + 2, win_w - 4, 30, COR_PAINEL);

                const uint32_t *icone_win = icone_sistema;
                const char *titulo_win    = "Painel do Sistema";
                if (modo_janela == MODO_JANELA_APPS) {
                    icone_win  = icone_iniciar;
                    titulo_win = "Central de Aplicativos";
                } else if (modo_janela == MODO_JANELA_CONFIG) {
                    icone_win  = icone_config;
                    titulo_win = "Dispositivos, Rede & Sistema";
                }

                gpu_desenhar_icone(icone_win, win_x + 10, win_y + 7, ICONE_TAM, ICONE_TAM);
                gpu_escrever_texto(titulo_win, win_x + 36, win_y + 9, COR_TEXTO_BRANCO);

                int close_x = win_x + win_w - 28;
                int close_y = win_y + 6;
                desenhar_retangulo_solido(close_x, close_y, 22, 22, COR_VERMELHO_ALERTA);
                gpu_escrever_texto("X", close_x + 7, close_y + 3, COR_TEXTO_BRANCO);

                int cx = win_x + 22;
                int cy = win_y + 46;

                if (modo_janela == MODO_JANELA_SISTEMA) {
                    gpu_escrever_texto("Bem-vindo ao FydelisTechOS (64-bit Long Mode)!", cx, cy, COR_CIANO_NEON);
                    cy += 26;
                    gpu_escrever_texto("Arquitetura   : x86_64 Assembly + C Freestanding", cx, cy, COR_TEXTO_SUAVE);
                    cy += 22;
                    gpu_escrever_texto(res_buf, cx, cy, COR_TEXTO_SUAVE);
                    cy += 22;
                    gpu_escrever_texto("Diretorio CWD : ", cx, cy, COR_TEXTO_SUAVE);
                    gpu_escrever_texto(diretorio_atual, cx + 128, cy, COR_VERDE_NEON);
                    cy += 34;
                    desenhar_caixa_com_borda(cx, cy, win_w - 44, 42, 1, COR_BORDA_SUTIL, COR_INPUT_BG);
                    gpu_escrever_texto("Clique no botao [F] abaixo para abrir Explorer, Browser ou Config.", cx + 12, cy + 13, COR_ROXO_CLARO);
                } else if (modo_janela == MODO_JANELA_APPS) {
                    gpu_escrever_texto("Aplicativos instalados em /fyd/apps:", cx, cy, COR_CIANO_NEON);
                    cy += 28;
                    gpu_desenhar_icone(icone_terminal, cx, cy - 2, ICONE_TAM, ICONE_TAM);
                    gpu_escrever_texto("FydelTerm Shell (CLI Nativo)", cx + 28, cy, COR_VERDE_NEON);
                    cy += 28;
                    gpu_desenhar_icone(icone_arquivo, cx, cy - 2, ICONE_TAM, ICONE_TAM);
                    gpu_escrever_texto("FydelNotes (Editor de Texto / VFS)", cx + 28, cy, COR_CIANO_NEON);
                    cy += 28;
                    gpu_desenhar_icone(icone_agenda, cx, cy - 2, ICONE_TAM, ICONE_TAM);
                    gpu_escrever_texto("Agenda & Calendario do Sistema", cx + 28, cy, COR_TEXTO_BRANCO);
                    cy += 28;
                    gpu_desenhar_icone(icone_video, cx, cy - 2, ICONE_TAM, ICONE_TAM);
                    gpu_escrever_texto("FydelisMedia Player (/fyd/midia)", cx + 28, cy, COR_TEXTO_BRANCO);
                    cy += 28;
                    gpu_desenhar_icone(icone_imagem, cx, cy - 2, ICONE_TAM, ICONE_TAM);
                    gpu_escrever_texto("Visualizador de Imagens (/fyd/usuario/imagens)", cx + 28, cy, COR_TEXTO_BRANCO);
                } else if (modo_janela == MODO_JANELA_CONFIG) {
                    gpu_escrever_texto("Dispositivos & Hardware (/fyd/config):", cx, cy, COR_CIANO_NEON);
                    cy += 26;
                    gpu_desenhar_icone(icone_ethernet, cx, cy - 2, ICONE_TAM, ICONE_TAM);
                    gpu_escrever_texto(link_rede_ativo ? "Rede Cabeada (E1000): CONECTADA" : "Rede Cabeada (E1000): Aguardando cabo",
                                       cx + 28, cy, link_rede_ativo ? COR_VERDE_NEON : COR_TEXTO_SUAVE);
                    cy += 26;
                    gpu_desenhar_icone(icone_wifi, cx, cy - 2, ICONE_TAM, ICONE_TAM);
                    gpu_escrever_texto("Controlador Wi-Fi: Pronto (/fyd/rede)", cx + 28, cy, COR_TEXTO_BRANCO);
                    cy += 26;
                    gpu_desenhar_icone(icone_bluetooth, cx, cy - 2, ICONE_TAM, ICONE_TAM);
                    gpu_escrever_texto(bt_estado == 2 ? "Bluetooth HCI: Conectado" : (bt_estado == 1 ? "Bluetooth HCI: Ativo" : "Bluetooth HCI: Nao detectado"),
                                       cx + 28, cy, bt_estado ? COR_CIANO_NEON : COR_TEXTO_SUAVE);
                    cy += 26;
                    gpu_desenhar_icone(icone_audio, cx, cy - 2, ICONE_TAM, ICONE_TAM);
                    gpu_escrever_texto(audio_estado == 1 ? "Audio (AC97/HDA): Ativo" : (audio_estado == 2 ? "Audio: MUDO" : "Audio: Nao detectado"),
                                       cx + 28, cy, audio_estado == 1 ? COR_VERDE_NEON : (audio_estado == 2 ? COR_VERMELHO_ALERTA : COR_TEXTO_SUAVE));
                    cy += 26;
                    gpu_desenhar_icone(icone_disco, cx, cy - 2, ICONE_TAM, ICONE_TAM);
                    gpu_escrever_texto(disco_detectado ? "Disco ATA Primario (0x1F0): Online" : "Disco ATA: Offline",
                                       cx + 28, cy, disco_detectado ? COR_VERDE_NEON : COR_VERMELHO_ALERTA);
                }
            }

            /* Janelas Modulares Independentes */
            if (app_calculadora.aberta) {
                app_calculadora.desenhar();
            }
            if (app_visualizador_logs.aberta) {
                app_visualizador_logs.desenhar();
            }
            if (app_explorer.aberta) {
                app_explorer.desenhar();
            }
            if (app_browser.aberta) {
                app_browser.desenhar();
            }
            if (app_notepad.aberta) {
                app_notepad.desenhar();
            }
            painel_win7_desenhar();

            /* 5. Barra de Tarefas Inferior */
            desenhar_retangulo_solido(0, taskbar_y, L, taskbar_h, COR_PAINEL);
            desenhar_retangulo_solido(0, taskbar_y, L, 2, COR_CIANO_NEON);

            desenhar_caixa_com_borda(btn_f_x, btn_f_y, btn_f_w, btn_f_h, 1,
                menu_aberto ? COR_CIANO_NEON : COR_ROXO_NEON,
                menu_aberto ? COR_HOVER : COR_CARD);
            gpu_desenhar_icone(icone_fydelis_f, btn_f_x + 11, btn_f_y + 6, ICONE_TAM, ICONE_TAM);

            int tab_x = btn_f_x + btn_f_w + 10;
            desenhar_caixa_com_borda(tab_x, btn_f_y + 1, 195, 30, 1,
                janela_aberta ? COR_CIANO_NEON : COR_BORDA_SUTIL,
                janela_aberta ? COR_HOVER : COR_INPUT_BG);
            const char *rotulo_aba = "Painel do Sistema";
            if (modo_janela == MODO_JANELA_APPS) rotulo_aba = "Aplicativos";
            else if (modo_janela == MODO_JANELA_CONFIG) rotulo_aba = "Configuracoes";
            gpu_escrever_texto(rotulo_aba, tab_x + 16, btn_f_y + 8, COR_TEXTO_BRANCO);

            /* Abas dinâmicas dos aplicativos abertos/minimizados */
            int prox_tab_x = tab_x + 203;

            if (app_explorer.aberta) {
                int exp_ativo = !explorer_esta_minimizado();
                desenhar_caixa_com_borda(prox_tab_x, btn_f_y + 1, 130, 30, 1,
                    exp_ativo ? COR_CIANO_NEON : COR_ROXO_NEON,
                    exp_ativo ? COR_HOVER : COR_INPUT_BG);
                gpu_desenhar_icone(icone_pasta_aberta, prox_tab_x + 8, btn_f_y + 6, ICONE_TAM, ICONE_TAM);
                gpu_escrever_texto("Explorer", prox_tab_x + 32, btn_f_y + 8, COR_TEXTO_BRANCO);
                prox_tab_x += 136;
            }

            if (app_browser.aberta) {
                int brw_ativo = !browser_esta_minimizado();
                desenhar_caixa_com_borda(prox_tab_x, btn_f_y + 1, 130, 30, 1,
                    brw_ativo ? COR_CIANO_NEON : COR_ROXO_NEON,
                    brw_ativo ? COR_HOVER : COR_INPUT_BG);
                gpu_desenhar_icone(icone_ethernet, prox_tab_x + 8, btn_f_y + 6, ICONE_TAM, ICONE_TAM);
                gpu_escrever_texto("Browser", prox_tab_x + 32, btn_f_y + 8, COR_TEXTO_BRANCO);
                prox_tab_x += 136;
            }

            if (app_notepad.aberta) {
                int ntc_ativo = !notepad_esta_minimizado();
                desenhar_caixa_com_borda(prox_tab_x, btn_f_y + 1, 130, 30, 1,
                    ntc_ativo ? COR_CIANO_NEON : COR_ROXO_NEON,
                    ntc_ativo ? COR_HOVER : COR_INPUT_BG);
                gpu_desenhar_icone(icone_arquivo, prox_tab_x + 8, btn_f_y + 6, ICONE_TAM, ICONE_TAM);
                gpu_escrever_texto("Notes", prox_tab_x + 32, btn_f_y + 8, COR_TEXTO_BRANCO);
                prox_tab_x += 136;
            }

            desenhar_systray(L, taskbar_y, taskbar_h, link_rede_ativo, disco_detectado, bt_estado, audio_estado, &dt_atual, mx, my);

            int term_btn_w = 132;
            int term_btn_x = L - SYSTRAY_LARGURA - term_btn_w - 16;
            desenhar_caixa_com_borda(term_btn_x, btn_f_y + 1, term_btn_w, 30, 1, COR_ROXO_NEON, COR_CARD);
            gpu_desenhar_icone(icone_terminal, term_btn_x + 8, btn_f_y + 6, ICONE_TAM, ICONE_TAM);
            gpu_escrever_texto("FydelTerm", term_btn_x + 34, btn_f_y + 8, COR_VERDE_NEON);

            if (menu_aberto) {
                desenhar_menu_iniciar_categorizado(menu_x, menu_y, menu_w, menu_h, mx, my);
            }

            wifi_popup_desenhar();
            eth_popup_desenhar();

            backbuffer_apresentar_frame(L, A);
            cursor_desenhar_novo();

            ciclos_ativos += (ler_tsc() - t_frame_ini);
            precisa_redesenhar = 0;
        }

        ws_atualizar_cursor();

        int botao_esq_pressionado = (mb & 0x01) != 0;
        int clique_agora = botao_esq_pressionado && !(btn_ant & 0x01);
        btn_ant = mb;

        /* Polling nao-bloqueante do Cliente DHCP (Discover -> Offer -> Request -> Ack) */
        uint32_t dhcp_st_antes = dhcp_ler_status();
        if (dhcp_st_antes == 1 || dhcp_st_antes == 2) {
            dhcp_cliente_processar();
            if (dhcp_ler_status() == 3) {
                const char *ip_atual = rede_ler_ip();
                if (ip_atual && ip_atual[0] != '\0') {
                    eth_copiar_str(eth_status_msg, "DHCP Ativo: ", sizeof(eth_status_msg));
                    size_t p = (size_t)eth_str_len(eth_status_msg);
                    if (p < sizeof(eth_status_msg) - 1) {
                        eth_copiar_str(eth_status_msg + p, ip_atual, (int)(sizeof(eth_status_msg) - p));
                    }
                    precisa_redesenhar = 1;
                }
            }
        }

        if (g_painel_win7.aberta && g_painel_win7.arrastando) {
            if (botao_esq_pressionado) {
                int nx = mx - g_painel_win7.drag_off_x;
                int ny = my - g_painel_win7.drag_off_y;
                if (nx < 0) nx = 0;
                if (nx + g_painel_win7.w > L) nx = L - g_painel_win7.w;
                if (ny < 34) ny = 34;
                if (ny + g_painel_win7.h > taskbar_y) ny = taskbar_y - g_painel_win7.h;
                if (nx != g_painel_win7.x || ny != g_painel_win7.y) {
                    g_painel_win7.x = nx;
                    g_painel_win7.y = ny;
                    precisa_redesenhar = 1;
                }
            } else {
                g_painel_win7.arrastando = 0;
                precisa_redesenhar = 1;
            }
        }

        if (arrastando) {
            if (botao_esq_pressionado) {
                int novo_x = mx - drag_offset_x;
                int novo_y = my - drag_offset_y;

                if (novo_x < 0) novo_x = 0;
                if (novo_x + win_w > L) novo_x = L - win_w;
                if (novo_y < 34) novo_y = 34;
                if (novo_y + win_h > taskbar_y) novo_y = taskbar_y - win_h;

                if (novo_x != win_x || novo_y != win_y) {
                    win_x = novo_x;
                    win_y = novo_y;
                    precisa_redesenhar = 1;
                }
            } else {
                arrastando = 0;
                precisa_redesenhar = 1;
            }
        }

        if (arrastando_calc) {
            if (botao_esq_pressionado) {
                int nx = mx - calc_drag_off_x;
                int ny = my - calc_drag_off_y;

                if (nx < 0) nx = 0;
                if (nx + app_calculadora.w > L) nx = L - app_calculadora.w;
                if (ny < 34) ny = 34;
                if (ny + app_calculadora.h > taskbar_y) ny = taskbar_y - app_calculadora.h;

                if (nx != app_calculadora.x || ny != app_calculadora.y) {
                    app_calculadora.x = nx;
                    app_calculadora.y = ny;
                    precisa_redesenhar = 1;
                }
            } else {
                arrastando_calc = 0;
                precisa_redesenhar = 1;
            }
        }

        if (arrastando_logs) {
            if (botao_esq_pressionado) {
                int nx = mx - logs_drag_off_x;
                int ny = my - logs_drag_off_y;
                if (nx < 0) nx = 0;
                if (nx + app_visualizador_logs.w > L) nx = L - app_visualizador_logs.w;
                if (ny < 34) ny = 34;
                if (ny + app_visualizador_logs.h > taskbar_y) ny = taskbar_y - app_visualizador_logs.h;
                if (nx != app_visualizador_logs.x || ny != app_visualizador_logs.y) {
                    app_visualizador_logs.x = nx;
                    app_visualizador_logs.y = ny;
                    precisa_redesenhar = 1;
                }
            } else {
                arrastando_logs = 0;
                precisa_redesenhar = 1;
            }
        }

        if (arrastando_exp) {
            if (botao_esq_pressionado) {
                int nx = mx - exp_drag_off_x;
                int ny = my - exp_drag_off_y;
                if (nx < 0) nx = 0;
                if (nx + app_explorer.w > L) nx = L - app_explorer.w;
                if (ny < 34) ny = 34;
                if (ny + app_explorer.h > taskbar_y) ny = taskbar_y - app_explorer.h;
                if (nx != app_explorer.x || ny != app_explorer.y) {
                    app_explorer.x = nx;
                    app_explorer.y = ny;
                    precisa_redesenhar = 1;
                }
            } else {
                arrastando_exp = 0;
                precisa_redesenhar = 1;
            }
        }

        if (arrastando_brw) {
            if (botao_esq_pressionado) {
                int nx = mx - brw_drag_off_x;
                int ny = my - brw_drag_off_y;
                if (nx < 0) nx = 0;
                if (nx + app_browser.w > L) nx = L - app_browser.w;
                if (ny < 34) ny = 34;
                if (ny + app_browser.h > taskbar_y) ny = taskbar_y - app_browser.h;
                if (nx != app_browser.x || ny != app_browser.y) {
                    app_browser.x = nx;
                    app_browser.y = ny;
                    precisa_redesenhar = 1;
                }
            } else {
                arrastando_brw = 0;
                precisa_redesenhar = 1;
            }
        }

        if (arrastando_notes) {
            if (botao_esq_pressionado) {
                int nx = mx - notes_drag_off_x;
                int ny = my - notes_drag_off_y;
                if (nx < 0) nx = 0;
                if (nx + app_notepad.w > L) nx = L - app_notepad.w;
                if (ny < 34) ny = 34;
                if (ny + app_notepad.h > taskbar_y) ny = taskbar_y - app_notepad.h;
                if (nx != app_notepad.x || ny != app_notepad.y) {
                    app_notepad.x = nx;
                    app_notepad.y = ny;
                    precisa_redesenhar = 1;
                }
            } else {
                arrastando_notes = 0;
                precisa_redesenhar = 1;
            }
        }

        if (clique_agora) {
            int term_btn_w = 132;
            int term_btn_x = L - SYSTRAY_LARGURA - term_btn_w - 16;
            int tray_x     = L - SYSTRAY_LARGURA - 8;

            if (eth_popup_aberto && eth_popup_processar_clique(mx, my)) {
                precisa_redesenhar = 1;
            }
            else if (wifi_popup_aberto && wifi_popup_processar_clique(mx, my)) {
                precisa_redesenhar = 1;
            }
            else if (g_painel_win7.aberta && painel_win7_processar_clique(mx, my)) {
                if (g_painel_win7.travar_solicitado) {
                    g_painel_win7.travar_solicitado = 0;
                    cursor_restaurar_fundo();
                    return 1;
                }
                menu_aberto = 0;
                precisa_redesenhar = 1;
            }
            else if (ponto_no_retangulo(mx, my, btn_f_x, btn_f_y, btn_f_w, btn_f_h)) {
                menu_aberto = !menu_aberto;
                precisa_redesenhar = 1;
            }
            else if (menu_aberto && ponto_no_retangulo(mx, my, menu_x, menu_y, menu_w, menu_h)) {
                int rod_y = menu_y + menu_h - 40;
                int btn_w = (menu_w - 28) / 3;
                int btn_y = rod_y + 6;

                if (ponto_no_retangulo(mx, my, menu_x + 8, btn_y, btn_w, 28)) {
                    cursor_restaurar_fundo();
                    return 1;
                } else if (ponto_no_retangulo(mx, my, menu_x + 14 + btn_w, btn_y, btn_w, 28)) {
                    energia_reiniciar_agora();
                } else if (ponto_no_retangulo(mx, my, menu_x + 20 + (btn_w * 2), btn_y, btn_w, 28)) {
                    energia_desligar_agora();
                } else {
                    int cab_h = 36, col_esq_w = 215, col_dir_w = menu_w - col_esq_w;
                    int corpo_y = menu_y + cab_h;
                    int idx_e = 0, idx_d = 0;

                    for (int i = 0; i < TOTAL_ITENS_MENU; i++) {
                        int ix = (itens_menu[i].coluna == 0) ? (menu_x + 10) : (menu_x + col_esq_w + 10);
                        int iy = corpo_y + 28 + ((itens_menu[i].coluna == 0 ? idx_e++ : idx_d++) * 36);
                        int iw = (itens_menu[i].coluna == 0) ? (col_esq_w - 20) : (col_dir_w - 20);

                        if (ponto_no_retangulo(mx, my, ix, iy, iw, 32)) {
                            int acao = itens_menu[i].acao_id;
                            if (acao == 1)       { app_explorer.abrir(); }
                            else if (acao == 2)  { modo_janela = MODO_JANELA_APPS;    janela_aberta = 1; }
                            else if (acao == 3)  { cursor_restaurar_fundo(); return 0; }
                            else if (acao == 4)  { modo_janela = MODO_JANELA_APPS;    janela_aberta = 1; }
                            else if (acao == 5)  { modo_janela = MODO_JANELA_SISTEMA; janela_aberta = 1; }
                            else if (acao == 6)  { janela_aberta = 0; painel_win7_abrir(); }
                            else if (acao == 7)  { janela_aberta = 0; painel_win7_abrir(); }
                            else if (acao == 8)  { app_calculadora.abrir(); }
                            else if (acao == 9)  { app_visualizador_logs.abrir(); }
                            else if (acao == 10) { app_browser.abrir(); }
                            else if (acao == 11) { app_notepad.abrir(); }

                            menu_aberto = 0;
                            precisa_redesenhar = 1;
                            break;
                        }
                    }
                }
            }
            else if (app_notepad.aberta && !notepad_esta_minimizado() &&
                     ponto_no_retangulo(mx, my, app_notepad.x, app_notepad.y,
                                        app_notepad.w, app_notepad.h)) {
                int rel_x = mx - app_notepad.x;
                int rel_y = my - app_notepad.y;

                if (rel_y >= 2 && rel_y <= 28 && rel_x < app_notepad.w - 72 && app_notepad.w < L) {
                    arrastando_notes = 1;
                    notes_drag_off_x = rel_x;
                    notes_drag_off_y = rel_y;
                } else {
                    app_notepad.on_click(rel_x, rel_y);
                }

                menu_aberto = 0;
                precisa_redesenhar = 1;
            }
            else if (app_browser.aberta && !browser_esta_minimizado() &&
                     ponto_no_retangulo(mx, my, app_browser.x, app_browser.y,
                                        app_browser.w, app_browser.h)) {
                int rel_x = mx - app_browser.x;
                int rel_y = my - app_browser.y;

                if (rel_x >= app_browser.w - 24 && rel_x <= app_browser.w - 4 &&
                    rel_y >= 3 && rel_y <= 24) {
                    app_browser.aberta = 0;
                    arrastando_brw = 0;
                } else if (rel_y >= 0 && rel_y <= 28 && rel_x < app_browser.w - 72 && app_browser.w < L) {
                    arrastando_brw = 1;
                    brw_drag_off_x = rel_x;
                    brw_drag_off_y = rel_y;
                } else {
                    app_browser.on_click(rel_x, rel_y);
                }

                menu_aberto = 0;
                precisa_redesenhar = 1;
            }
            else if (app_explorer.aberta && !explorer_esta_minimizado() &&
                     ponto_no_retangulo(mx, my, app_explorer.x, app_explorer.y,
                                        app_explorer.w, app_explorer.h)) {
                int rel_x = mx - app_explorer.x;
                int rel_y = my - app_explorer.y;

                if (rel_x >= app_explorer.w - 24 && rel_x <= app_explorer.w - 4 &&
                    rel_y >= 3 && rel_y <= 24) {
                    app_explorer.aberta = 0;
                    arrastando_exp = 0;
                } else if (rel_y >= 0 && rel_y <= 28 && rel_x < app_explorer.w - 72 && app_explorer.w < L) {
                    arrastando_exp = 1;
                    exp_drag_off_x = rel_x;
                    exp_drag_off_y = rel_y;
                } else {
                    app_explorer.on_click(rel_x, rel_y);
                }

                menu_aberto = 0;
                precisa_redesenhar = 1;
            }
            else if (app_calculadora.aberta &&
                     ponto_no_retangulo(mx, my, app_calculadora.x, app_calculadora.y,
                                        app_calculadora.w, app_calculadora.h)) {
                int rel_x = mx - app_calculadora.x;
                int rel_y = my - app_calculadora.y;

                if (rel_x >= app_calculadora.w - 24 && rel_x <= app_calculadora.w - 4 &&
                    rel_y >= 3 && rel_y <= 23) {
                    app_calculadora.aberta = 0;
                    arrastando_calc = 0;
                } else if (rel_y >= 0 && rel_y <= 26) {
                    arrastando_calc = 1;
                    calc_drag_off_x = rel_x;
                    calc_drag_off_y = rel_y;
                } else {
                    app_calculadora.on_click(rel_x, rel_y);
                }

                menu_aberto = 0;
                precisa_redesenhar = 1;
            }
            else if (app_visualizador_logs.aberta &&
                     ponto_no_retangulo(mx, my, app_visualizador_logs.x, app_visualizador_logs.y,
                                        app_visualizador_logs.w, app_visualizador_logs.h)) {
                int rel_x = mx - app_visualizador_logs.x;
                int rel_y = my - app_visualizador_logs.y;

                if (rel_x >= app_visualizador_logs.w - 24 && rel_x <= app_visualizador_logs.w - 4 &&
                    rel_y >= 3 && rel_y <= 23) {
                    app_visualizador_logs.aberta = 0;
                    arrastando_logs = 0;
                } else if (rel_y >= 0 && rel_y <= 26) {
                    arrastando_logs = 1;
                    logs_drag_off_x = rel_x;
                    logs_drag_off_y = rel_y;
                } else {
                    app_visualizador_logs.on_click(rel_x, rel_y);
                }

                menu_aberto = 0;
                precisa_redesenhar = 1;
            }
            else if (ponto_no_retangulo(mx, my, btn_f_x + btn_f_w + 10, btn_f_y + 1, 195, 30)) {
                janela_aberta = !janela_aberta;
                menu_aberto = 0;
                precisa_redesenhar = 1;
            }
            else if (ponto_no_retangulo(mx, my, tray_x, btn_f_y, SYSTRAY_LARGURA, 32)) {
                int eth_ico_x  = tray_x + 8;
                int wifi_ico_x = tray_x + 34;

                if (ponto_no_retangulo(mx, my, eth_ico_x - 2, btn_f_y, 26, 32)) {
                    eth_popup_alternar();
                } else if (ponto_no_retangulo(mx, my, wifi_ico_x - 2, btn_f_y, 26, 32)) {
                    eth_popup_aberto = 0;
                    wifi_popup_alternar();
                } else {
                    eth_popup_aberto = 0;
                    wifi_popup_aberto = 0;
                    modo_janela = MODO_JANELA_CONFIG;
                    janela_aberta = 1;
                    painel_win7_abrir();
                }
                menu_aberto = 0;
                precisa_redesenhar = 1;
            }
            else if (ponto_no_retangulo(mx, my, term_btn_x, btn_f_y + 1, term_btn_w, 30)) {
                cursor_restaurar_fundo();
                return 0;
            }
            else if (my >= taskbar_y) {
                int prox_tab_x = (btn_f_x + btn_f_w + 10) + 203;
                if (app_explorer.aberta) {
                    if (ponto_no_retangulo(mx, my, prox_tab_x, btn_f_y + 1, 130, 30)) {
                        explorer_alternar_minimizar();
                        arrastando_exp = 0;
                        menu_aberto = 0;
                        precisa_redesenhar = 1;
                    }
                    prox_tab_x += 136;
                }
                if (app_browser.aberta) {
                    if (ponto_no_retangulo(mx, my, prox_tab_x, btn_f_y + 1, 130, 30)) {
                        browser_alternar_minimizar();
                        arrastando_brw = 0;
                        menu_aberto = 0;
                        precisa_redesenhar = 1;
                    }
                    prox_tab_x += 136;
                }
                if (app_notepad.aberta) {
                    if (ponto_no_retangulo(mx, my, prox_tab_x, btn_f_y + 1, 130, 30)) {
                        notepad_alternar_minimizar();
                        arrastando_notes = 0;
                        menu_aberto = 0;
                        precisa_redesenhar = 1;
                    }
                    prox_tab_x += 136;
                }
            }
            else if (ponto_no_retangulo(mx, my, 22, 54, 110, 22)) {
                app_explorer.abrir();
                menu_aberto = 0;
                precisa_redesenhar = 1;
            }
            else if (ponto_no_retangulo(mx, my, 22, 88, 125, 22)) {
                modo_janela = MODO_JANELA_APPS;
                janela_aberta = 1;
                menu_aberto = 0;
                precisa_redesenhar = 1;
            }
            else if (janela_aberta && modo_janela == MODO_JANELA_APPS &&
                     ponto_no_retangulo(mx, my, win_x + 22, win_y + 72, 260, 22)) {
                app_notepad.abrir();
                menu_aberto = 0;
                precisa_redesenhar = 1;
            }
            else if (ponto_no_retangulo(mx, my, 22, 122, 140, 22)) {
                modo_janela = MODO_JANELA_CONFIG;
                janela_aberta = 1;
                painel_win7_abrir();
                menu_aberto = 0;
                precisa_redesenhar = 1;
            }
            else if (ponto_no_retangulo(mx, my, 22, 156, 150, 22)) {
                app_browser.abrir();
                menu_aberto = 0;
                precisa_redesenhar = 1;
            }
            else if (janela_aberta) {
                int close_x = win_x + win_w - 28;
                int close_y = win_y + 6;

                if (ponto_no_retangulo(mx, my, close_x, close_y, 22, 22)) {
                    janela_aberta = 0;
                    menu_aberto = 0;
                    precisa_redesenhar = 1;
                } else if (ponto_no_retangulo(mx, my, win_x, win_y, win_w, 32)) {
                    arrastando = 1;
                    drag_offset_x = mx - win_x;
                    drag_offset_y = my - win_y;
                    menu_aberto = 0;
                    precisa_redesenhar = 1;
                } else if (menu_aberto) {
                    menu_aberto = 0;
                    precisa_redesenhar = 1;
                }
            } else if (menu_aberto) {
                menu_aberto = 0;
                precisa_redesenhar = 1;
            }
        }

        char tecla;
        while ((tecla = ler_tecla_ps2()) != 0) {
            if (eth_popup_aberto) {
                eth_popup_on_key(tecla);
                precisa_redesenhar = 1;
            } else if (g_painel_win7.aberta) {
                painel_win7_on_key(tecla);
                precisa_redesenhar = 1;
            } else if (app_notepad.aberta && !notepad_esta_minimizado()) {
                if (tecla == 27) {
                    app_notepad.aberta = 0;
                    arrastando_notes = 0;
                } else {
                    app_notepad.on_key(tecla);
                }
                precisa_redesenhar = 1;
            } else if (app_browser.aberta && !browser_esta_minimizado()) {
                if (tecla == 27) {
                    app_browser.aberta = 0;
                    arrastando_brw = 0;
                } else {
                    app_browser.on_key(tecla);
                }
                precisa_redesenhar = 1;
            } else if (app_explorer.aberta && !explorer_esta_minimizado()) {
                if (tecla == 27) {
                    app_explorer.aberta = 0;
                    arrastando_exp = 0;
                } else {
                    app_explorer.on_key(tecla);
                }
                precisa_redesenhar = 1;
            } else if (app_calculadora.aberta) {
                if (tecla == 27) {
                    app_calculadora.aberta = 0;
                    arrastando_calc = 0;
                } else {
                    app_calculadora.on_key(tecla);
                }
                precisa_redesenhar = 1;
            } else if (tecla == 27) {
                cursor_restaurar_fundo();
                return 0;
            }
        }

        descansar_cpu_hlt();
    }
}

/* ============================================================================
- PONTO DE ENTRADA CHAMADO PELO KERNEL (kernel_exec_bin)
- ============================================================================ */
int kernel_exec_bin(void) {
    gpu_inicializar();

    if (!fb_base || fb_largura == 0 || fb_altura == 0) {
        return -1;
    }

    int L = (int)fb_largura;
    int A = (int)fb_altura;

    auth_garantir_adm_padrao();
    mouse_inicializar();
    ws_inicializar();

    exibir_splash_carregamento(L, A);

    while (1) {
        exibir_tela_login(L, A);
        int acao = exibir_desktop_grafico(L, A);
        if (acao == 0) {
            break;
        }
    }

    return 0;
}
