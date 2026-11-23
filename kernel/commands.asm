; ============================================================================
; INTERPRETADOR DE COMANDOS — FYDELTERM v4.2 (ARQUITETURA REAL x86_64)
; Conectado a fs.asm (FAT32), particao.asm/disco.asm e net_core/rede/dhcp.asm
; Salvador • Bahia
; ============================================================================
BITS 64
default rel

%include "fydelterm.inc"

; ============================================================================
; MACROS DE ORGANIZACAO E SEGURANCA ABI (C <-> ASSEMBLY)
; ============================================================================
%macro CALL_C 1
    push    rbp
    mov     rbp, rsp
    and     rsp, -16
    call    %1
    mov     rsp, rbp
    pop     rbp
%endmacro

%macro REGISTRAR_CMD 3
    dq %1, %2, %3
%endmacro

; ============================================================================
; SIMBOLOS EXTERNOS REAIS (KERNEL, FAT32, PARTICOES, REDE & CVE GUARD)
; ============================================================================

; --- Console & Utilidades ---
extern clear_screen, print_string, print_newline, print_char, get_key, set_color
extern strcmpi, int_para_str, print_num
extern mapa_unidades, argc, argv

; --- Video VESA & Desktop ---
extern fb_base, fb_inicializar, gpu_preencher_tela
extern gpu_inicializar_todos, ws_inicializar, kernel_exec_bin

; --- Sistema de Arquivos Real FAT32 (fs.asm & estrutura.asm) ---
extern fs_inicializar, fs_listar_dir, fs_criar_pasta, fs_remover, fs_copiar
extern construir_estrutura_sistema, listar_estrutura

; --- Discos & Particoes Reais (disco.asm & particao.asm) ---
extern listar_unidades, criar_unidade, remover_unidade, formatar_unidade
extern obter_tamanho_disco, inicializar_disco

; --- Seguranca (CVE Guard & Logs) ---
extern cve_guard_iniciar, cve_guard_adicionar_regra
extern cve_guard_total_regras, cve_guard_total_alertas, cve_guard_zerar_alertas
extern fydlog_ler_todos, fydlog_escrever

; --- Rede Real (net_core.asm, rede.asm & dhcp.asm) ---
extern net_inicializar
extern net_iface_nome, net_obter_mac_str
extern net_obter_ip_str, net_obter_mascara_str
extern net_obter_gateway_str, net_obter_dns_str
extern net_link_ativo, net_bytes_rx, net_bytes_tx
extern net_ping_real, net_traceroute_real
extern net_arp_listar, net_conexoes_listar
extern net_dhcp_renovar
extern do_ipconfig, do_wifi, do_netstat
extern rx_bytes_total, tx_bytes_total
extern dhcp_cliente_iniciar, dhcp_ip_atual
extern dhcp_servidor_iniciar, dhcp_servidor_status, dhcp_servidor_ativo
extern ip_para_string

; --- Perifericos & Apps ---
extern usb_listar_dispositivos
extern do_fydel, do_pentest

; ============================================================================
; EXPORTACOES GLOBAIS
; ============================================================================
global interpret_command
global do_cls, do_echo, do_help, do_ver, do_exit, do_reboot, do_poweroff
global do_login, do_desktop, do_listar, do_estrutura, do_criar_pasta, do_remover, do_copiar
global do_mkpart, do_rmpart, do_format, do_fstype, do_bootmode, do_blkid, do_df, do_fsinfo
global do_bt, do_usb, do_cve
global cmd_ping, cmd_traceroute, cmd_dhcp, cmd_status_rede, cmd_arp
global cmd_wifi, cmd_limpar_rede, cmd_dhcp_servidor, cmd_fydlog

; ============================================================================
; CONSTANTES
; ============================================================================
MBR_TIPO_FAT32       equ 0x0B
MBR_TIPO_FAT32_LBA   equ 0x0C
MBR_TIPO_EXFAT       equ 0x07
LIMIAR_GPT_SETORES   equ 4000000000
COR_FUNDO_TERM       equ 0xFF090611
DIR_LIST_BUF_TAM     equ 4096

; ============================================================================
; DADOS SOMENTE LEITURA (.rodata) — COMANDOS E TEXTOS
; ============================================================================
section .rodata

; --- Nomes dos Comandos ---
cmd_str_cls:         db 'cls', 0
cmd_str_limpar:      db 'limpar', 0
cmd_str_dizer:       db 'dizer', 0
cmd_str_ajuda:       db 'ajuda', 0
cmd_str_versao:      db 'versao', 0
cmd_str_sair:        db 'sair', 0
cmd_str_reiniciar:   db 'reiniciar', 0
cmd_str_desligar:    db 'desligar', 0
cmd_str_login:       db 'login', 0
cmd_str_desktop:     db 'desktop', 0

cmd_str_listar:      db 'listar', 0
cmd_str_dir:         db 'dir', 0
cmd_str_estrutura:   db 'estrutura', 0
cmd_str_criar_pasta: db 'criar_pasta', 0
cmd_str_remover:     db 'remover', 0
cmd_str_copiar:      db 'copiar', 0

cmd_str_mkpart:      db 'mkpart', 0
cmd_str_rmpart:      db 'rmpart', 0
cmd_str_format:      db 'format', 0
cmd_str_fstype:      db 'fstype', 0
cmd_str_bootmode:    db 'bootmode', 0
cmd_str_blkid:       db 'blkid', 0
cmd_str_df:          db 'df', 0
cmd_str_fsinfo:      db 'fsinfo', 0

cmd_str_cve:         db 'cve', 0
cmd_str_fydlog:      db 'fydlog', 0
cmd_str_pentest:     db 'pentest', 0
cmd_str_fydel:       db 'fydel', 0

cmd_str_bt:          db 'bt', 0
cmd_str_usb:         db 'usb', 0
cmd_str_ipconfig:    db 'ipconfig', 0
cmd_str_ping:        db 'ping', 0
cmd_str_traceroute:  db 'traceroute', 0
cmd_str_dhcp:        db 'dhcp', 0
cmd_str_status_rede: db 'status_rede', 0
cmd_str_arp:         db 'arp', 0
cmd_str_netstat:     db 'netstat', 0
cmd_str_wifi:        db 'wifi', 0
cmd_str_limpar_rede: db 'limpar_rede', 0
cmd_str_dhcp_serv:   db 'dhcp_servidor', 0

; --- Textos de Ajuda ---
hlp_cls:             db 'cls / limpar       - Limpa a tela do terminal', 0
hlp_dizer:           db 'dizer <texto>      - Exibe mensagem na tela', 0
hlp_ajuda:           db 'ajuda              - Lista todos os comandos disponiveis', 0
hlp_versao:          db 'versao             - Exibe versao do FydelisTech OS', 0
hlp_sair:            db 'sair               - Encerra sessao atual', 0
hlp_reiniciar:       db 'reiniciar          - Reinicia o computador', 0
hlp_desligar:        db 'desligar           - Desliga o computador', 0
hlp_login:           db 'login <user> <sen> - Autentica e abre modo grafico', 0
hlp_desktop:         db 'desktop            - Inicia Area de Trabalho Grafica', 0

hlp_listar:          db 'listar [caminho]   - Lista arquivos/pastas FAT32 (padrao: /fyd)', 0
hlp_estrutura:       db 'estrutura          - Exibe arvore de diretorios /fyd do boot', 0
hlp_criar_pasta:     db 'criar_pasta <nome> - Cria novo diretorio no FAT32', 0
hlp_remover:         db 'remover <alvo>     - Remove arquivo ou pasta do FAT32', 0
hlp_copiar:          db 'copiar <orig> <dst>- Copia arquivo no FAT32', 0

hlp_mkpart:          db 'mkpart <L:> <TAM>  - Cria particao real (Ex: mkpart D: 50M)', 0
hlp_rmpart:          db 'rmpart <L:>        - Remove particao', 0
hlp_format:          db 'format <L:> <FS>   - Formata unidade (FAT32/exFAT/FydelisFS)', 0
hlp_fstype:          db 'fstype <L:>        - Exibe sistema de arquivos da unidade', 0
hlp_bootmode:        db 'bootmode           - Mostra modo MBR ou GPT', 0
hlp_blkid:           db 'blkid              - Lista unidades e particoes detectadas', 0
hlp_df:              db 'df                 - Espaco livre e total das unidades', 0
hlp_fsinfo:          db 'fsinfo             - Informacoes detalhadas do disco', 0

hlp_cve:             db 'cve <status|zerar> - Gerencia escudo CVE Guard em tempo real', 0
hlp_fydlog:          db 'fydlog             - Exibe logs internos do sistema', 0
hlp_pentest:         db 'pentest            - Abre suite de seguranca FydelisTech', 0
hlp_fydel:           db 'fydel [arquivo]    - Abre editor de texto', 0

hlp_bt:              db 'bt <scan|conectar|desconectar> - Controla Bluetooth', 0
hlp_usb:             db 'usb                - Lista dispositivos USB', 0
hlp_ipconfig:        db 'ipconfig [/renew]  - Exibe/renova IPv4, MAC e placa PCI', 0
hlp_ping:            db 'ping <ip>          - Testa conectividade ICMP real', 0
hlp_traceroute:      db 'traceroute <ip>    - Rastreia rota de rede', 0
hlp_dhcp:            db 'dhcp               - Solicita IP automatico via DHCP real', 0
hlp_status_rede:     db 'status_rede        - Exibe IP, MAC, Gateway e trafego NIC', 0
hlp_arp:             db 'arp                - Exibe tabela ARP real', 0
hlp_netstat:         db 'netstat            - Exibe sockets e portas abertas', 0
hlp_wifi:            db 'wifi               - Status da interface wireless/Ethernet', 0
hlp_limpar_rede:     db 'limpar_rede        - Zera contadores RX/TX', 0
hlp_dhcp_serv:       db 'dhcp_servidor <iniciar|parar|status> - Servidor DHCP', 0

; --- Mensagens do Sistema ---
dir_padrao_fyd:      db '/fyd', 0
msg_unknown:         db 'Comando nao reconhecido. Digite "ajuda".', 10, 0
msg_ver:             db 'FydelisTech OS v4.2 (FydelTerm 64-bit VESA) · Salvador-BA', 10, 0
msg_bye:             db 'Sessao encerrada. Sistema em espera.', 10, 0
msg_help_head:       db '=== COMANDOS DISPONIVEIS NO FYDELTERM ===', 10, 0
msg_pausa:           db '-- Pressione qualquer tecla para continuar --', 0
msg_rebooting:       db 'Reiniciando o sistema...', 10, 0
msg_power_off:       db 'Desligando o sistema...', 10, 0

msg_listar_head:     db '=== Conteudo FAT32 de: ', 0
msg_listar_fim_h:    db ' ===', 10, 0
msg_dir_vazio:       db '  (diretorio vazio ou nao encontrado)', 10, 0
msg_estrutura_head:  db '=== Estrutura de Diretorios do Sistema (/fyd) ===', 10, 0
msg_pasta_criada:    db 'Pasta criada: ', 0
msg_removido:        db 'Removido: ', 0
msg_copiado:         db 'Copiado com sucesso.', 10, 0

msg_part_ok:         db 'Unidade criada: ', 0
msg_part_del:        db 'Unidade removida: ', 0
msg_fmt_ok:          db 'Sistema aplicado: ', 0
msg_letra_inv:       db 'Letra invalida! Use: A: B: C: ... Z:', 10, 0
msg_erro_op:         db 'Erro ao executar operacao.', 10, 0
msg_fs_leg:          db 'Modo de Boot: MBR (Legacy BIOS)', 10, 0
msg_disco_gpt:       db 'Modo de Boot: GPT (UEFI / > 2TB)', 10, 0
msg_disco_mbr:       db 'Disco <= 2 TB -> usando MBR', 10, 0
msg_fat32:           db 'FAT32', 0
msg_exfat:           db 'exFAT', 0
msg_fydfs:           db 'FydelisFS', 0
df_cab:              db 'UNIDADE    TOTAL    LIVRE    SISTEMA', 10, '-----------------------------------', 10, 0

msg_login_ok:        db 'Autenticado com sucesso! Carregando ambiente grafico...', 10, 0
msg_login_erro:      db 'Usuario ou senha invalidos.', 10, 0
msg_sem_vesa:        db 'Erro: Framebuffer VESA nao inicializado no boot.', 10, 0
login_user_padrao:   db 'admin', 0
login_pass_padrao:   db 'fydelis2026', 0
caminho_fyd_desktop: db 'interface/sistema/bin/fyd_desktop', 0

msg_cve_titulo:      db '=== CVE GUARD (KERNEL SHIELD x86_64) ===', 10, 0
msg_cve_status:      db 'Status: ATIVO | Regras carregadas: ', 0
msg_cve_alertas:     db ' | Ameacas bloqueadas: ', 0
msg_cve_zerado:      db 'Contador de alertas do CVE Guard zerado.', 10, 0
str_zerar:           db 'zerar', 0

msg_ping_uso:        db 'Uso: ping <ip_ipv4>', 10, 0
msg_ping_ok:         db 'Resposta ICMP recebida!', 10, 0
msg_ping_fail:       db 'Sem resposta do host.', 10, 0
msg_dhcp_aguarde:    db 'Solicitando IP via DHCP real...', 10, 0
msg_dhcp_ok:         db 'IP obtido com sucesso via DHCP!', 10, 0
msg_dhcp_fail:       db 'Timeout DHCP: verifique conexao com gateway.', 10, 0
msg_rede_titulo:     db '=== Status da Rede (Hardware Real) ===', 10, 0
msg_rede_iface:      db 'Interface: ', 0
msg_rede_mac:        db 'MAC: ', 0
msg_rede_ip:         db 'IP: ', 0
msg_rede_mask:       db 'Mascara: ', 0
msg_rede_gw:         db 'Gateway: ', 0
msg_rede_dns:        db 'DNS: ', 0
msg_rede_link_up:    db 'Link: Ativo (UP)', 10, 0
msg_rede_link_down:  db 'Link: Desconectado (DOWN)', 10, 0
msg_rede_rx:         db 'RX: ', 0
msg_rede_tx:         db 'TX: ', 0
msg_limpo:           db 'Contadores de rede zerados.', 10, 0
msg_bytes:           db ' bytes', 0
msg_sep:             db ' / ', 0
msg_bt_info:         db 'Controlador Bluetooth HCI: nenhum adaptador ativo.', 10, 0

; ============================================================================
; BUFFERS (.bss)
; ============================================================================
section .bss
align 16
ip_buf:          resb 16
mac_buf:         resb 18
buffer_conv:     resb 32
dir_list_buf:    resb DIR_LIST_BUF_TAM

; ============================================================================
; TABELA CENTRAL DE COMANDOS (.data)
; ============================================================================
section .data
align 16
cmd_table:
    ; --- Sistema & Sessao ---
    REGISTRAR_CMD cmd_str_cls,         do_cls,            hlp_cls
    REGISTRAR_CMD cmd_str_limpar,      do_cls,            hlp_cls
    REGISTRAR_CMD cmd_str_dizer,       do_echo,           hlp_dizer
    REGISTRAR_CMD cmd_str_ajuda,       do_help,           hlp_ajuda
    REGISTRAR_CMD cmd_str_versao,      do_ver,            hlp_versao
    REGISTRAR_CMD cmd_str_sair,        do_exit,           hlp_sair
    REGISTRAR_CMD cmd_str_reiniciar,   do_reboot,         hlp_reiniciar
    REGISTRAR_CMD cmd_str_desligar,    do_poweroff,       hlp_desligar
    REGISTRAR_CMD cmd_str_login,       do_login,          hlp_login
    REGISTRAR_CMD cmd_str_desktop,     do_desktop,        hlp_desktop

    ; --- Arquivos & Estrutura /fyd ---
    REGISTRAR_CMD cmd_str_listar,      do_listar,         hlp_listar
    REGISTRAR_CMD cmd_str_dir,         do_listar,         hlp_listar
    REGISTRAR_CMD cmd_str_estrutura,   do_estrutura,      hlp_estrutura
    REGISTRAR_CMD cmd_str_criar_pasta, do_criar_pasta,    hlp_criar_pasta
    REGISTRAR_CMD cmd_str_remover,     do_remover,        hlp_remover
    REGISTRAR_CMD cmd_str_copiar,      do_copiar,         hlp_copiar

    ; --- Discos & Particoes ---
    REGISTRAR_CMD cmd_str_mkpart,      do_mkpart,         hlp_mkpart
    REGISTRAR_CMD cmd_str_rmpart,      do_rmpart,         hlp_rmpart
    REGISTRAR_CMD cmd_str_format,      do_format,         hlp_format
    REGISTRAR_CMD cmd_str_fstype,      do_fstype,         hlp_fstype
    REGISTRAR_CMD cmd_str_bootmode,    do_bootmode,       hlp_bootmode
    REGISTRAR_CMD cmd_str_blkid,       do_blkid,          hlp_blkid
    REGISTRAR_CMD cmd_str_df,          do_df,             hlp_df
    REGISTRAR_CMD cmd_str_fsinfo,      do_fsinfo,         hlp_fsinfo

    ; --- Seguranca & Utilitarios ---
    REGISTRAR_CMD cmd_str_cve,         do_cve,            hlp_cve
    REGISTRAR_CMD cmd_str_fydlog,      cmd_fydlog,        hlp_fydlog
    REGISTRAR_CMD cmd_str_pentest,     do_pentest,        hlp_pentest
    REGISTRAR_CMD cmd_str_fydel,       do_fydel,          hlp_fydel

    ; --- Rede & Perifericos ---
    REGISTRAR_CMD cmd_str_bt,          do_bt,             hlp_bt
    REGISTRAR_CMD cmd_str_usb,         do_usb,            hlp_usb
    REGISTRAR_CMD cmd_str_ipconfig,    do_ipconfig,       hlp_ipconfig
    REGISTRAR_CMD cmd_str_ping,        cmd_ping,          hlp_ping
    REGISTRAR_CMD cmd_str_traceroute,  cmd_traceroute,    hlp_traceroute
    REGISTRAR_CMD cmd_str_dhcp,        cmd_dhcp,          hlp_dhcp
    REGISTRAR_CMD cmd_str_status_rede, cmd_status_rede,   hlp_status_rede
    REGISTRAR_CMD cmd_str_arp,         cmd_arp,           hlp_arp
    REGISTRAR_CMD cmd_str_netstat,     do_netstat,        hlp_netstat
    REGISTRAR_CMD cmd_str_wifi,        cmd_wifi,          hlp_wifi
    REGISTRAR_CMD cmd_str_limpar_rede, cmd_limpar_rede,   hlp_limpar_rede
    REGISTRAR_CMD cmd_str_dhcp_serv,   cmd_dhcp_servidor, hlp_dhcp_serv

    ; --- Fim da Tabela ---
    dq 0, 0, 0

; ============================================================================
; CODIGO (.text) — INTERPRETADOR E COMANDOS
; ============================================================================
section .text

interpret_command:
    push    rbx
    push    rsi
    push    rdi

    mov     rax, [rel argc]
    cmp     rax, 0
    jle     .fim

    lea     rbx, [rel cmd_table]
.busca:
    mov     rsi, [rbx]
    test    rsi, rsi
    jz      .nao_encontrado

    lea     rdi, [rel argv]
    mov     rdi, [rdi]
    call    strcmpi
    test    rax, rax
    jz      .encontrado

    add     rbx, 24
    jmp     .busca

.encontrado:
    mov     rax, [rbx + 8]
    test    rax, rax
    jz      .fim
    call    rax
    jmp     .fim

.nao_encontrado:
    lea     rsi, [rel argv]
    mov     rsi, [rsi]
    call    print_string
    mov     al, ':'
    call    print_char
    mov     al, ' '
    call    print_char
    lea     rsi, [rel msg_unknown]
    call    print_warning

.fim:
    pop     rdi
    pop     rsi
    pop     rbx
    ret

; ============================================================================
; 1. COMANDOS DE SISTEMA & CONSOLE VESA
; ============================================================================

do_cls:
    call    clear_screen
    cmp     qword [rel fb_base], 0
    je      .fallback_vga
    mov     rdi, COR_FUNDO_TERM
    CALL_C  gpu_preencher_tela
.fallback_vga:
    call    clear_screen
    ret

do_echo:
    mov     rax, [rel argc]
    cmp     rax, 2
    jl      .fim
    lea     rsi, [rel argv]
    mov     rsi, [rsi + 8]
    call    print_string
    call    print_newline
.fim:
    ret

do_ver:
    lea     rsi, [rel msg_ver]
    call    print_success
    ret

do_help:
    push    rbx
    push    rcx
    mov     rdi, 0x0E
    call    set_color

    xor     rcx, rcx
    lea     rsi, [rel msg_help_head]
    call    print_string
    lea     rbx, [rel cmd_table]

.loop:
    mov     rsi, [rbx]
    test    rsi, rsi
    jz      .fim

    inc     rcx
    cmp     rcx, 18
    jl      .imp
    lea     rsi, [rel msg_pausa]
    call    print_string
    call    get_key
    call    print_newline
    xor     rcx, rcx

.imp:
    mov     al, ' '
    call    print_char
    mov     rsi, [rbx + 16]
    call    print_string
    call    print_newline
    add     rbx, 24
    jmp     .loop

.fim:
    mov     rdi, DEF_ATTR
    call    set_color
    pop     rcx
    pop     rbx
    ret

do_exit:
    lea     rsi, [rel msg_bye]
    call    print_success
    cli
.halt:
    hlt
    jmp     .halt

do_reboot:
    lea     rsi, [rel msg_rebooting]
    call    print_warning
    mov     dx, 0x64
.esp1:
    in      al, dx
    test    al, 2
    jnz     .esp1
    mov     al, 0xFE
    out     dx, al
    cli
.halt:
    hlt
    jmp     .halt

do_poweroff:
    lea     rsi, [rel msg_power_off]
    call    print_warning
    mov     dx, 0x604
    xor     eax, eax
    out     dx, eax
    cli
.halt:
    hlt
    jmp     .halt

; ============================================================================
; 2. LOGIN & AMBIENTE GRAFICO VESA
; ============================================================================

do_login:
    mov     rax, [rel argc]
    cmp     rax, 3
    jl      .uso

    lea     rsi, [rel argv]
    mov     rsi, [rsi + 8]
    lea     rdi, [rel login_user_padrao]
    call    strcmpi
    jne     .erro

    lea     rsi, [rel argv]
    mov     rsi, [rsi + 16]
    lea     rdi, [rel login_pass_padrao]
    call    strcmpi
    jne     .erro

    lea     rsi, [rel msg_login_ok]
    call    print_success
    call    do_desktop
    ret

.uso:
    lea     rsi, [rel hlp_login]
    call    print_warning
    call    print_newline
    ret

.erro:
    lea     rsi, [rel msg_login_erro]
    call    print_error
    ret

do_desktop:
    cmp     qword [rel fb_base], 0
    je      .sem_video

    CALL_C  fb_inicializar
    CALL_C  gpu_inicializar_todos
    CALL_C  ws_inicializar

    lea     rdi, [rel caminho_fyd_desktop]
    CALL_C  kernel_exec_bin
    ret

.sem_video:
    lea     rsi, [rel msg_sem_vesa]
    call    print_error
    ret

; ============================================================================
; 3. SISTEMA DE ARQUIVOS REAL FAT32 & ESTRUTURA /fyd
; ============================================================================

do_listar:
    push    r12
    mov     rax, [rel argc]
    cmp     rax, 2
    jl      .usar_padrao
    lea     r12, [rel argv]
    mov     r12, [r12 + 8]
    jmp     .exec_listar

.usar_padrao:
    lea     r12, [rel dir_padrao_fyd]

.exec_listar:
    lea     rsi, [rel msg_listar_head]
    call    print_string
    mov     rsi, r12
    call    print_string
    lea     rsi, [rel msg_listar_fim_h]
    call    print_string

    ; Zera buffer de listagem
    lea     rdi, [rel dir_list_buf]
    mov     rcx, DIR_LIST_BUF_TAM / 8
    xor     eax, eax
    rep     stosq

    ; fs_listar_dir(rdi=caminho, rsi=dir_list_buf, rdx=DIR_LIST_BUF_TAM-1)
    mov     rdi, r12
    lea     rsi, [rel dir_list_buf]
    mov     rdx, DIR_LIST_BUF_TAM - 1
    CALL_C  fs_listar_dir

    test    rax, rax
    jle     .vazio

    lea     rsi, [rel dir_list_buf]
    call    print_string
    call    print_newline
    pop     r12
    ret

.vazio:
    lea     rsi, [rel msg_dir_vazio]
    call    print_warning
    pop     r12
    ret

do_estrutura:
    lea     rsi, [rel msg_estrutura_head]
    call    print_string
    CALL_C  listar_estrutura
    call    print_newline
    ret

do_criar_pasta:
    mov     rax, [rel argc]
    cmp     rax, 2
    jl      .uso
    lea     rdi, [rel argv]
    mov     rdi, [rdi + 8]
    CALL_C  fs_criar_pasta
    test    rax, rax
    jz      .erro
    lea     rsi, [rel msg_pasta_criada]
    call    print_success
    lea     rsi, [rel argv]
    mov     rsi, [rsi + 8]
    call    print_string
    call    print_newline
    ret
.erro:
    lea     rsi, [rel msg_erro_op]
    call    print_error
    ret
.uso:
    lea     rsi, [rel hlp_criar_pasta]
    call    print_warning
    call    print_newline
    ret

do_remover:
    mov     rax, [rel argc]
    cmp     rax, 2
    jl      .uso
    lea     rdi, [rel argv]
    mov     rdi, [rdi + 8]
    CALL_C  fs_remover
    test    rax, rax
    jz      .erro
    lea     rsi, [rel msg_removido]
    call    print_success
    lea     rsi, [rel argv]
    mov     rsi, [rsi + 8]
    call    print_string
    call    print_newline
    ret
.erro:
    lea     rsi, [rel msg_erro_op]
    call    print_error
    ret
.uso:
    lea     rsi, [rel hlp_remover]
    call    print_warning
    call    print_newline
    ret

do_copiar:
    mov     rax, [rel argc]
    cmp     rax, 3
    jl      .uso
    lea     rax, [rel argv]
    mov     rdi, [rax + 8]
    mov     rsi, [rax + 16]
    CALL_C  fs_copiar
    test    rax, rax
    jz      .erro
    lea     rsi, [rel msg_copiado]
    call    print_success
    ret
.erro:
    lea     rsi, [rel msg_erro_op]
    call    print_error
    ret
.uso:
    lea     rsi, [rel hlp_copiar]
    call    print_warning
    call    print_newline
    ret

; ============================================================================
; 4. SEGURANCA: CVE GUARD & LOGS
; ============================================================================

do_cve:
    mov     rax, [rel argc]
    cmp     rax, 2
    jl      .status

    lea     rdi, [rel argv]
    mov     rdi, [rdi + 8]
    lea     rsi, [rel str_zerar]
    call    strcmpi
    jz      .zerar

.status:
    lea     rsi, [rel msg_cve_titulo]
    call    print_string

    lea     rsi, [rel msg_cve_status]
    call    print_string
    CALL_C  cve_guard_total_regras
    mov     rdi, rax
    call    print_num

    lea     rsi, [rel msg_cve_alertas]
    call    print_string
    CALL_C  cve_guard_total_alertas
    mov     rdi, rax
    call    print_num
    call    print_newline
    ret

.zerar:
    CALL_C  cve_guard_zerar_alertas
    lea     rsi, [rel msg_cve_zerado]
    call    print_success
    ret

cmd_fydlog:
    CALL_C  fydlog_ler_todos
    call    print_newline
    ret

; ============================================================================
; 5. GERENCIAMENTO REAL DE DISCOS & PARTICOES (disco.asm & particao.asm)
; ============================================================================

; Extrai indice (0..25) de "C:" ou "c" -> rax = 0..25 (ou -1 se invalido)
letra_para_indice:
    mov     al, [rsi]
    cmp     al, 'A'
    jb      .minuscula
    cmp     al, 'Z'
    ja      .minuscula
    sub     al, 'A'
    movzx   rax, al
    ret
.minuscula:
    cmp     al, 'a'
    jb      .invalido
    cmp     al, 'z'
    ja      .invalido
    sub     al, 'a'
    movzx   rax, al
    ret
.invalido:
    mov     rax, -1
    ret

tamanho_para_setores:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    xor     rax, rax
    xor     rcx, rcx
.ler_digito:
    mov     cl, [rsi]
    cmp     cl, '0'
    jb      .fim_numeros
    cmp     cl, '9'
    ja      .fim_numeros
    imul    rax, 10
    add     rax, rcx
    sub     rax, '0'
    inc     rsi
    jmp     .ler_digito
.fim_numeros:
    mov     cl, [rsi]
    or      cl, 0x20
    cmp     cl, 'k'
    je      .mult_k
    cmp     cl, 'm'
    je      .mult_m
    cmp     cl, 'g'
    je      .mult_g
    cmp     cl, 't'
    je      .mult_t
    jmp     .fim
.mult_k:
    mov     rbx, 2
    mul     rbx
    jmp     .fim
.mult_m:
    mov     rbx, 2048
    mul     rbx
    jmp     .fim
.mult_g:
    mov     rbx, 2097152
    mul     rbx
    jmp     .fim
.mult_t:
    mov     rbx, 2147483648
    mul     rbx
.fim:
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

do_mkpart:
    push    rbx
    mov     rax, [rel argc]
    cmp     rax, 3
    jl      .uso

    ; Garante disco ATA/NVMe inicializado antes de criar particao
    CALL_C  inicializar_disco

    lea     rbx, [rel argv]
    mov     rsi, [rbx + 8]
    call    letra_para_indice
    cmp     rax, -1
    je      .letra_inv

    mov     rdi, rax                ; rdi = indice da unidade (0..25)
    mov     rsi, [rbx + 16]
    call    tamanho_para_setores
    mov     rsi, rax                ; rsi = setores (ABI 2o arg)
    mov     rdx, rax                ; rdx = setores (compatibilidade 3o arg)
    CALL_C  criar_unidade
    test    rax, rax
    jz      .erro

    lea     rsi, [rel msg_part_ok]
    call    print_success
    mov     rsi, [rbx + 8]
    call    print_string
    call    print_newline
    pop     rbx
    ret
.letra_inv:
    lea     rsi, [rel msg_letra_inv]
    call    print_error
    pop     rbx
    ret
.erro:
    lea     rsi, [rel msg_erro_op]
    call    print_error
    pop     rbx
    ret
.uso:
    lea     rsi, [rel hlp_mkpart]
    call    print_warning
    call    print_newline
    pop     rbx
    ret

do_rmpart:
    push    rbx
    mov     rax, [rel argc]
    cmp     rax, 2
    jl      .uso

    CALL_C  inicializar_disco

    lea     rbx, [rel argv]
    mov     rsi, [rbx + 8]
    call    letra_para_indice
    cmp     rax, -1
    je      .letra_inv

    mov     rdi, rax
    CALL_C  remover_unidade
    test    rax, rax
    jz      .erro

    lea     rsi, [rel msg_part_del]
    call    print_success
    mov     rsi, [rbx + 8]
    call    print_string
    call    print_newline
    pop     rbx
    ret
.letra_inv:
    lea     rsi, [rel msg_letra_inv]
    call    print_error
    pop     rbx
    ret
.erro:
    lea     rsi, [rel msg_erro_op]
    call    print_error
    pop     rbx
    ret
.uso:
    lea     rsi, [rel hlp_rmpart]
    call    print_warning
    call    print_newline
    pop     rbx
    ret

do_format:
    push    rbx
    mov     rax, [rel argc]
    cmp     rax, 3
    jl      .uso

    CALL_C  inicializar_disco

    lea     rbx, [rel argv]
    mov     rsi, [rbx + 8]
    call    letra_para_indice
    cmp     rax, -1
    je      .letra_inv

    mov     rdi, rax
    mov     rsi, [rbx + 16]
    CALL_C  formatar_unidade
    test    rax, rax
    jz      .erro

    lea     rsi, [rel msg_fmt_ok]
    call    print_success
    mov     rsi, [rbx + 16]
    call    print_string
    call    print_newline
    pop     rbx
    ret
.letra_inv:
    lea     rsi, [rel msg_letra_inv]
    call    print_error
    pop     rbx
    ret
.erro:
    lea     rsi, [rel msg_erro_op]
    call    print_error
    pop     rbx
    ret
.uso:
    lea     rsi, [rel hlp_format]
    call    print_warning
    call    print_newline
    pop     rbx
    ret

do_fstype:
    push    rbx
    mov     rax, [rel argc]
    cmp     rax, 2
    jl      .uso

    lea     rbx, [rel argv]
    mov     rsi, [rbx + 8]
    call    letra_para_indice
    cmp     rax, -1
    je      .letra_inv

    mov     rdi, rax
    shl     rdi, 3
    add     rdi, rax
    shl     rdi, 3
    lea     rcx, [rel mapa_unidades]
    mov     al, [rcx + rdi + 1]
    cmp     al, MBR_TIPO_FAT32
    je      .fat32
    cmp     al, MBR_TIPO_FAT32_LBA
    je      .fat32
    cmp     al, MBR_TIPO_EXFAT
    je      .exfat
    lea     rsi, [rel msg_fydfs]
    jmp     .imp
.fat32:
    lea     rsi, [rel msg_fat32]
    jmp     .imp
.exfat:
    lea     rsi, [rel msg_exfat]
.imp:
    push    rsi
    mov     rsi, [rbx + 8]
    call    print_string
    mov     al, ':'
    call    print_char
    mov     al, ' '
    call    print_char
    pop     rsi
    call    print_string
    call    print_newline
    pop     rbx
    ret
.letra_inv:
    lea     rsi, [rel msg_letra_inv]
    call    print_error
    pop     rbx
    ret
.uso:
    lea     rsi, [rel hlp_fstype]
    call    print_warning
    call    print_newline
    pop     rbx
    ret

do_bootmode:
    CALL_C  inicializar_disco
    CALL_C  obter_tamanho_disco
    mov     rbx, LIMIAR_GPT_SETORES
    cmp     rax, rbx
    jae     .gpt
    lea     rsi, [rel msg_disco_mbr]
    call    print_warning
    lea     rsi, [rel msg_fs_leg]
    call    print_string
    ret
.gpt:
    lea     rsi, [rel msg_disco_gpt]
    call    print_success
    ret

do_blkid:
    CALL_C  inicializar_disco
    CALL_C  listar_unidades
    ret

do_df:
    CALL_C  inicializar_disco
    lea     rsi, [rel df_cab]
    call    print_string
    CALL_C  listar_unidades
    ret

do_fsinfo:
    CALL_C  inicializar_disco
    CALL_C  obter_tamanho_disco
    mov     rdi, rax
    call    print_num
    lea     rsi, [rel msg_bytes]
    call    print_string
    call    print_newline
    ret

; ============================================================================
; 6. REDE REAL (E1000 + DHCP + ICMP + ARP), USB & BLUETOOTH
; ============================================================================

do_bt:
    lea     rsi, [rel msg_bt_info]
    call    print_warning
    ret

do_usb:
    CALL_C  usb_listar_dispositivos
    ret

cmd_ping:
    mov     rax, [rel argc]
    cmp     rax, 2
    jl      .uso
    lea     rdi, [rel argv]
    mov     rdi, [rdi + 8]
    CALL_C  net_ping_real
    ret
.uso:
    lea     rsi, [rel msg_ping_uso]
    call    print_warning
    ret

cmd_traceroute:
    mov     rax, [rel argc]
    cmp     rax, 2
    jl      .uso
    lea     rdi, [rel argv]
    mov     rdi, [rdi + 8]
    CALL_C  net_traceroute_real
    ret
.uso:
    lea     rsi, [rel msg_ping_uso]
    call    print_warning
    ret

cmd_dhcp:
    lea     rsi, [rel msg_dhcp_aguarde]
    call    print_string
    CALL_C  net_dhcp_renovar
    test    rax, rax
    jz      .erro
    lea     rsi, [rel msg_dhcp_ok]
    call    print_success
    call    cmd_status_rede
    ret
.erro:
    lea     rsi, [rel msg_dhcp_fail]
    call    print_error
    ret

cmd_status_rede:
    lea     rsi, [rel msg_rede_titulo]
    call    print_string

    lea     rsi, [rel msg_rede_iface]
    call    print_string
    CALL_C  net_iface_nome
    mov     rsi, rax
    call    print_string
    call    print_newline

    lea     rsi, [rel msg_rede_mac]
    call    print_string
    CALL_C  net_obter_mac_str
    mov     rsi, rax
    call    print_string
    call    print_newline

    lea     rsi, [rel msg_rede_ip]
    call    print_string
    CALL_C  net_obter_ip_str
    mov     rsi, rax
    call    print_string
    call    print_newline

    lea     rsi, [rel msg_rede_mask]
    call    print_string
    CALL_C  net_obter_mascara_str
    mov     rsi, rax
    call    print_string
    call    print_newline

    lea     rsi, [rel msg_rede_gw]
    call    print_string
    CALL_C  net_obter_gateway_str
    mov     rsi, rax
    call    print_string
    call    print_newline

    lea     rsi, [rel msg_rede_dns]
    call    print_string
    CALL_C  net_obter_dns_str
    mov     rsi, rax
    call    print_string
    call    print_newline

    CALL_C  net_link_ativo
    test    rax, rax
    jz      .down
    lea     rsi, [rel msg_rede_link_up]
    call    print_success
    jmp     .trafego
.down:
    lea     rsi, [rel msg_rede_link_down]
    call    print_error
.trafego:
    lea     rsi, [rel msg_rede_rx]
    call    print_string
    CALL_C  net_bytes_rx
    mov     rdi, rax
    call    print_num
    lea     rsi, [rel msg_bytes]
    call    print_string
    lea     rsi, [rel msg_sep]
    call    print_string
    lea     rsi, [rel msg_rede_tx]
    call    print_string
    CALL_C  net_bytes_tx
    mov     rdi, rax
    call    print_num
    lea     rsi, [rel msg_bytes]
    call    print_string
    call    print_newline
    ret

cmd_arp:
    CALL_C  net_arp_listar
    ret

cmd_limpar_rede:
    mov     qword [rel rx_bytes_total], 0
    mov     qword [rel tx_bytes_total], 0
    lea     rsi, [rel msg_limpo]
    call    print_success
    ret

cmd_wifi:
    call    do_wifi
    ret

cmd_dhcp_servidor:
    mov     rax, [rel argc]
    cmp     rax, 2
    jl      .status
    lea     rdi, [rel argv]
    mov     rdi, [rdi + 8]
    cmp     byte [rdi], 'i'
    je      .iniciar
    cmp     byte [rdi], 'p'
    je      .parar
.status:
    CALL_C  dhcp_servidor_status
    ret
.iniciar:
    CALL_C  dhcp_servidor_iniciar
    ret
.parar:
    mov     dword [rel dhcp_servidor_ativo], 0
    ret

; ============================================================================
; 7. AUXILIARES DE FORMATACAO E CORES
; ============================================================================

print_colored:
    push    rdi
    push    rsi
    call    set_color
    call    print_string
    mov     rdi, DEF_ATTR
    call    set_color
    pop     rsi
    pop     rdi
    ret

print_error:
    push    rdi
    mov     rdi, 0x0C
    call    print_colored
    pop     rdi
    ret

print_warning:
    push    rdi
    mov     rdi, 0x0E
    call    print_colored
    pop     rdi
    ret

print_success:
    push    rdi
    mov     rdi, 0x0A
    call    print_colored
    pop     rdi
    ret
