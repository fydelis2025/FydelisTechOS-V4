#include <stdint.h>
#include "../include/fydlog.h"

extern uint32_t *fb_base;
extern uint32_t  fb_largura;
extern uint32_t  fb_altura;
extern uint32_t  fb_pitch;

extern void gpu_escrever_texto(const char *texto, int x, int y, uint32_t cor);
extern void print_string(const char *s);
extern void print_newline(void);
extern void fydelis_panic_excecao(void);

static volatile uint32_t g_panic_em_andamento = 0;

static void u64_para_hex(uint64_t val, char *out) {
    static const char hex[] = "0123456789ABCDEF";
    out[0] = '0';
    out[1] = 'x';
    for (int i = 0; i < 16; i++) {
        out[2 + i] = hex[(val >> ((15 - i) * 4)) & 0xFU];
    }
    out[18] = '\0';
}

static void u64_para_dec(uint64_t val, char *out, int tam) {
    if (tam <= 1) {
        if (tam == 1) out[0] = '\0';
        return;
    }

    char tmp[24];
    int pos = 0;
    if (val == 0) {
        tmp[pos++] = '0';
    } else {
        while (val > 0 && pos < (int)sizeof(tmp) - 1) {
            tmp[pos++] = (char)('0' + (val % 10ULL));
            val /= 10ULL;
        }
    }

    int out_pos = 0;
    while (pos > 0 && out_pos + 1 < tam) {
        out[out_pos++] = tmp[--pos];
    }
    out[out_pos] = '\0';
}

static void copiar_str(char *dst, int tam, const char *src) {
    if (tam <= 0) return;
    int i = 0;
    while (src && src[i] != '\0' && i + 1 < tam) {
        dst[i] = src[i];
        i++;
    }
    dst[i] = '\0';
}

static void anexar_str(char *dst, int tam, const char *src) {
    if (tam <= 0 || !src) return;
    int pos = 0;
    while (pos < tam - 1 && dst[pos] != '\0') {
        pos++;
    }
    int i = 0;
    while (src[i] != '\0' && pos + 1 < tam) {
        dst[pos++] = src[i++];
    }
    dst[pos] = '\0';
}

static void panic_retangulo(int x, int y, int w, int h, uint32_t cor) {
    if (!fb_base || fb_largura == 0 || fb_altura == 0 || w <= 0 || h <= 0) {
        return;
    }

    uint64_t stride = (fb_pitch > 0) ? ((uint64_t)fb_pitch / 4ULL) : (uint64_t)fb_largura;
    int max_w = (int)fb_largura;
    int max_h = (int)fb_altura;

    for (int dy = 0; dy < h; dy++) {
        int py = y + dy;
        if (py < 0 || py >= max_h) {
            continue;
        }
        uint32_t *linha = fb_base + ((uint64_t)py * stride);
        for (int dx = 0; dx < w; dx++) {
            int px = x + dx;
            if (px >= 0 && px < max_w) {
                linha[px] = cor;
            }
        }
    }
}

static void decodificar_pf_flags(uint64_t err, char *buf, int tam) {
    /* Bit 0: P (0=nao-presente, 1=violacao de protecao)
       Bit 1: W/R (0=leitura, 1=escrita)
       Bit 2: U/S (0=kernel, 1=usuario)
       Bit 3: RSVD (1=bit reservado em tabela de pagina)
       Bit 4: I/D (1=busca de instrucao) */
    const char *p  = (err & (1ULL << 0)) ? "PROT" : "NOT_PRES";
    const char *rw = (err & (1ULL << 1)) ? "WRITE" : "READ";
    const char *us = (err & (1ULL << 2)) ? "USER" : "KERNEL";
    const char *id = (err & (1ULL << 4)) ? " | IFETCH" : "";

    copiar_str(buf, tam, "[");
    anexar_str(buf, tam, p);
    anexar_str(buf, tam, " | ");
    anexar_str(buf, tam, rw);
    anexar_str(buf, tam, " | ");
    anexar_str(buf, tam, us);
    anexar_str(buf, tam, id);
    anexar_str(buf, tam, " ]");
}

static void formatar_excecao(
    uint64_t vetor_id,
    char *nome_out, int nome_tam,
    char *log_out,  int log_tam
) {
    const char *mnem = "EXC";
    const char *desc = "EXCECAO DE CPU";
    const char *logd = "Excecao critica de CPU";
    int conhecida = 1;

    switch (vetor_id) {
        case 0:  mnem = "#DE"; desc = "DIVISAO POR ZERO";               logd = "Divisao por zero no kernel"; break;
        case 1:  mnem = "#DB"; desc = "DEBUG / TRAP";                  logd = "Excecao de debug/trap"; break;
        case 2:  mnem = "NMI"; desc = "INTERRUPCAO NAO MASCARAVEL";    logd = "NMI disparada"; break;
        case 3:  mnem = "#BP"; desc = "BREAKPOINT";                    logd = "Breakpoint int3"; break;
        case 4:  mnem = "#OF"; desc = "OVERFLOW";                      logd = "Overflow INTO"; break;
        case 5:  mnem = "#BR"; desc = "BOUND RANGE EXCEEDED";          logd = "Limite de faixa excedido"; break;
        case 6:  mnem = "#UD"; desc = "INSTRUCAO INVALIDA / UNDEFINED";logd = "Opcode invalido ou nao suportado"; break;
        case 7:  mnem = "#NM"; desc = "DISPOSITIVO NAO DISPONIVEL";    logd = "FPU/SSE/MMX indisponivel ou CR0.TS"; break;
        case 8:  mnem = "#DF"; desc = "FALHA DUPLA / DOUBLE FAULT";    logd = "Falha dupla de pilha/IDT"; break;
        case 9:  mnem = "CSO"; desc = "COPROCESSOR SEGMENT OVERRUN";   logd = "Coprocessor segment overrun"; break;
        case 10: mnem = "#TS"; desc = "TSS INVALIDO";                  logd = "Task State Segment invalido"; break;
        case 11: mnem = "#NP"; desc = "SEGMENTO NAO PRESENTE";         logd = "Segmento/descritor nao presente"; break;
        case 12: mnem = "#SS"; desc = "FALHA DE PILHA / STACK FAULT";  logd = "Falha de segmento de pilha"; break;
        case 13: mnem = "#GP"; desc = "FALHA DE PROTECAO GERAL";       logd = "Violacao de protecao geral"; break;
        case 14: mnem = "#PF"; desc = "FALHA DE PAGINA / PAGE FAULT";  logd = "Acesso a pagina nao mapeada"; break;
        case 15: mnem = "RSV"; desc = "VETOR RESERVADO (15)";          logd = "Vetor reservado 15"; break;
        case 16: mnem = "#MF"; desc = "FALHA X87 FPU";                 logd = "Erro matematico x87 FPU"; break;
        case 17: mnem = "#AC"; desc = "FALHA DE ALINHAMENTO";          logd = "Acesso desalinhado na memoria"; break;
        case 18: mnem = "#MC"; desc = "MACHINE CHECK";                 logd = "Erro critico de hardware (#MC)"; break;
        case 19: mnem = "#XM"; desc = "EXCECAO SIMD / SSE";            logd = "Excecao de ponto flutuante SIMD"; break;
        case 20: mnem = "#VE"; desc = "VIRTUALIZATION EXCEPTION";      logd = "Excecao de virtualizacao (#VE)"; break;
        case 21: mnem = "#CP"; desc = "CONTROL PROTECTION";            logd = "Violacao de protecao de controle"; break;
        case 28: mnem = "#HV"; desc = "HYPERVISOR INJECTION";          logd = "Injecao de hipervisor (#HV)"; break;
        case 29: mnem = "#VC"; desc = "VMM COMMUNICATION";             logd = "Comunicacao VMM (#VC)"; break;
        case 30: mnem = "#SX"; desc = "SECURITY EXCEPTION";            logd = "Excecao de seguranca (#SX)"; break;
        default:
            conhecida = 0;
            mnem = "VEC";
            desc = "EXCECAO / VETOR DE CPU";
            logd = "Vetor de excecao/interrupcao nao tratado";
            break;
    }

    char dec_buf[24];
    char hex_buf[20];
    u64_para_dec(vetor_id, dec_buf, sizeof(dec_buf));
    u64_para_hex(vetor_id, hex_buf);

    copiar_str(nome_out, nome_tam, mnem);
    anexar_str(nome_out, nome_tam, " - ");
    anexar_str(nome_out, nome_tam, desc);
    if (!conhecida) {
        anexar_str(nome_out, nome_tam, " [NAO MAPEADA]");
    }
    anexar_str(nome_out, nome_tam, " (Vetor ");
    anexar_str(nome_out, nome_tam, dec_buf);
    anexar_str(nome_out, nome_tam, " / ");
    anexar_str(nome_out, nome_tam, hex_buf);
    anexar_str(nome_out, nome_tam, ")");

    copiar_str(log_out, log_tam, "PANIC ");
    anexar_str(log_out, log_tam, mnem);
    anexar_str(log_out, log_tam, " [vet=");
    anexar_str(log_out, log_tam, dec_buf);
    anexar_str(log_out, log_tam, "]: ");
    anexar_str(log_out, log_tam, logd);
}

void kernel_panic_handler(
    uint64_t vetor_id,
    uint64_t error_code,
    uint64_t rip,
    uint64_t cr2,
    uint64_t rsp_orig,
    const uint64_t *regs
) {
    /* Evita cascata de excecoes caso o proprio handler falhe */
    if (g_panic_em_andamento) {
        fydelis_panic_excecao();
    }
    g_panic_em_andamento = 1;

    char nome_exc[128];
    char log_msg[128];
    formatar_excecao(vetor_id, nome_exc, sizeof(nome_exc), log_msg, sizeof(log_msg));

    char hex_rip[20], hex_cr2[20], hex_err[20], hex_rsp[20], hex_vec[20], dec_vec[24];
    u64_para_hex(rip, hex_rip);
    u64_para_hex(cr2, hex_cr2);
    u64_para_hex(error_code, hex_err);
    u64_para_hex(rsp_orig, hex_rsp);
    u64_para_hex(vetor_id, hex_vec);
    u64_para_dec(vetor_id, dec_vec, sizeof(dec_vec));

    char detalhe_info[64];
    detalhe_info[0] = '\0';
    if (vetor_id == 14) {
        decodificar_pf_flags(error_code, detalhe_info, sizeof(detalhe_info));
    } else {
        copiar_str(detalhe_info, sizeof(detalhe_info), "Vetor: ");
        anexar_str(detalhe_info, sizeof(detalhe_info), dec_vec);
        anexar_str(detalhe_info, sizeof(detalhe_info), " (");
        anexar_str(detalhe_info, sizeof(detalhe_info), hex_vec);
        anexar_str(detalhe_info, sizeof(detalhe_info), ")");
    }

    /* 1. Regista no FydLog antes de desenhar a tela grafica para evitar sobreposicao */
    fydlog_escrever(LOG_CRITICO, log_msg);

    /* 2. Saida no console texto */
    print_newline();
    print_string("================ [ FYDELISTECH OS - KERNEL PANIC ] ================");
    print_newline();
    print_string(nome_exc);
    if (detalhe_info[0] != '\0') {
        print_string(" ");
        print_string(detalhe_info);
    }
    print_newline();

    print_string("RIP: "); print_string(hex_rip);
    print_string("  CR2: "); print_string(hex_cr2);
    print_newline();
    print_string("ERR: "); print_string(hex_err);
    print_string("  RSP: "); print_string(hex_rsp);
    print_newline();

    if (regs) {
        char hex_r0[20], hex_r1[20], hex_r2[20];
        u64_para_hex(regs[0], hex_r0);
        u64_para_hex(regs[1], hex_r1);
        u64_para_hex(regs[2], hex_r2);
        print_string("REGS[0..2]: ");
        print_string(hex_r0); print_string(" ");
        print_string(hex_r1); print_string(" ");
        print_string(hex_r2);
        print_newline();
    }

    /* 3. Tela de Panic Grafica no Framebuffer VESA */
    if (fb_base && fb_largura > 0 && fb_altura > 0) {
        int L = (int)fb_largura;
        int A = (int)fb_altura;

        panic_retangulo(0, 0, L, A, 0xFF1A050D);
        panic_retangulo(0, 0, L, 48, 0xFF991B1B);
        panic_retangulo(0, 48, L, 3, 0xFFFF4D6D);

        gpu_escrever_texto("FYDELISTECH OS - KERNEL PANIC (PARADA DE SEGURANCA)", 24, 16, 0xFFFFFFFF);

        int bx = 40;
        int by = 80;
        int bw = L - 80;
        int bh = A - 130;
        if (bw > 0 && bh > 0) {
            panic_retangulo(bx, by, bw, bh, 0xFF290A14);

            gpu_escrever_texto("O nucleo interceptou uma excecao critica e interrompeu a execucao:", bx + 20, by + 20, 0xFFFCA5A5);
            gpu_escrever_texto(nome_exc, bx + 20, by + 50, 0xFF00F5D4);
            if (detalhe_info[0] != '\0') {
                gpu_escrever_texto(detalhe_info, bx + 20, by + 72, 0xFFFDE047);
            }

            gpu_escrever_texto("Ponteiro de Instrucao (RIP) :", bx + 20, by + 100, 0xFFCBD5E1);
            gpu_escrever_texto(hex_rip,                        bx + 260, by + 100, 0xFFFFFFFF);

            gpu_escrever_texto("Endereco Faltante (CR2)     :", bx + 20, by + 130, 0xFFCBD5E1);
            gpu_escrever_texto(hex_cr2,                        bx + 260, by + 130, 0xFFFF4D6D);

            gpu_escrever_texto("Codigo de Erro (ERR)        :", bx + 20, by + 160, 0xFFCBD5E1);
            gpu_escrever_texto(hex_err,                        bx + 260, by + 160, 0xFFFFFFFF);

            gpu_escrever_texto("Pilha Original (RSP)        :", bx + 20, by + 190, 0xFFCBD5E1);
            gpu_escrever_texto(hex_rsp,                        bx + 260, by + 190, 0xFFFFFFFF);

            if (regs) {
                char hex_reg0[20];
                u64_para_hex(regs[0], hex_reg0);
                gpu_escrever_texto("Registrador Base (regs[0])  :", bx + 20, by + 220, 0xFFCBD5E1);
                gpu_escrever_texto(hex_reg0,                       bx + 260, by + 220, 0xFFFFFFFF);
            }

            gpu_escrever_texto("Evento registrado em /fyd/dados/logs/sistema.flog [LOG_CRITICO].", bx + 20, by + 255, 0xFF00FF9C);
            gpu_escrever_texto("Reinicie a maquina virtual ou pressione Reset para reiniciar.", bx + 20, by + 285, 0xFFCBD5E1);
        }
    }

    /* 4. Paralisa a CPU com seguranca */
    fydelis_panic_excecao();
}
