; ============================================================================
; ESTRUTURA.ASM — Arvore de Diretorios e Configuracao Real no FAT32 (/fyd)
; Conectado ao fs.asm + particao.asm + disco.asm · Persistencia Real
; FydelisTech OS v4.2 · Salvador - Bahia
; ============================================================================
BITS 64
default rel

global construir_estrutura_sistema
global listar_estrutura
global fs_caminho_existe
global fs_criar_diretorio
global fs_obter_lista_pastas
global fs_total_pastas
global fs_ler_config_padrao
global fs_tamanho_config_padrao
global diretorio_atual

extern print_string
extern print_newline
extern print_char

; Pontes reais do disco, particao e FAT32
extern inicializar_disco
extern fs_inicializar
extern fs_existe
extern fs_criar_pasta
extern fs_ler_arquivo
extern salvar_arquivo
extern fs_definir_caminho_atual

%define MAX_DIRETORIOS 64

section .data

; ======= RAIZ & RUNTIME =======
pasta_raiz:          db "/fyd", 0
pasta_tmp:           db "/fyd/tmp", 0
pasta_dev:           db "/fyd/dev", 0

; ======= DISCO E ARMAZENAMENTO =======
pasta_disco:         db "/fyd/disco", 0
pasta_disco_f1:      db "/fyd/disco/fyd1", 0
pasta_disco_f2:      db "/fyd/disco/fyd2", 0
pasta_usb:           db "/fyd/usb", 0
pasta_usb_u1:        db "/fyd/usb/fydu1", 0
pasta_usb_u2:        db "/fyd/usb/fydu2", 0
pasta_midia:         db "/fyd/midia", 0
pasta_rede:          db "/fyd/rede", 0

; ======= SISTEMA E BINARIOS =======
pasta_bin:           db "/fyd/bin", 0
pasta_lib:           db "/fyd/lib", 0
pasta_apps:          db "/fyd/apps", 0
pasta_terminal:      db "/fyd/terminal", 0
pasta_boot:          db "/fyd/boot", 0
pasta_config:        db "/fyd/config", 0
arq_sistema_fcfg:    db "/fyd/config/sistema.fcfg", 0

; ======= USUARIO =======
pasta_home:          db "/fyd/usuario", 0
pasta_documentos:    db "/fyd/usuario/documentos", 0
pasta_imagens:       db "/fyd/usuario/imagens", 0
pasta_musica:        db "/fyd/usuario/musica", 0
pasta_downloads:     db "/fyd/usuario/downloads", 0
pasta_area_trabalho: db "/fyd/usuario/area_trabalho", 0
pasta_projetos:      db "/fyd/usuario/projetos", 0

; ======= SEGURANCA E DADOS =======
pasta_secure:        db "/fyd/secure", 0
pasta_contas:        db "/fyd/secure/contas", 0
pasta_dados:         db "/fyd/dados", 0
pasta_logs:          db "/fyd/dados/logs", 0
pasta_temas:         db "/fyd/temas", 0
pasta_icons:         db "/fyd/temas/icones", 0
pasta_estilos:       db "/fyd/temas/estilos", 0

; ======= REDE E FERRAMENTAS =======
pasta_rede_cfg:      db "/fyd/rede/cfg", 0
pasta_pentest:       db "/fyd/pentest", 0
pasta_relatorios:    db "/fyd/pentest/relatorios", 0
pasta_capturas:      db "/fyd/pentest/capturas", 0

; ======= LISTA MESTRE DE DIRETORIOS (APENAS PASTAS REAIS) =======
lista_pastas:
    dq pasta_raiz, pasta_tmp, pasta_dev
    dq pasta_disco, pasta_disco_f1, pasta_disco_f2
    dq pasta_usb, pasta_usb_u1, pasta_usb_u2
    dq pasta_midia, pasta_rede
    dq pasta_bin, pasta_lib, pasta_apps, pasta_terminal
    dq pasta_boot, pasta_config
    dq pasta_home, pasta_documentos, pasta_imagens
    dq pasta_musica, pasta_downloads
    dq pasta_area_trabalho, pasta_projetos
    dq pasta_secure, pasta_contas, pasta_dados, pasta_logs
    dq pasta_temas, pasta_icons, pasta_estilos
    dq pasta_rede_cfg, pasta_pentest
    dq pasta_relatorios, pasta_capturas
    dq 0    ; FIM DA LISTA

; ======= CONTEUDO PADRAO DE /fyd/config/sistema.fcfg =======
conteudo_sistema_fcfg:
    db "#!FYDCFG v1", 10
    db "# Configuracao nativa FydelisTech OS", 10
    db "os_nome=FydelisTech OS", 10
    db "versao=4.2", 10
    db "tema=roxo_neon", 10
    db "timezone=-3", 10
    db "usuario_padrao=admin", 10
    db "rede_dhcp=1", 10, 0
conteudo_sistema_fcfg_len equ $ - conteudo_sistema_fcfg - 1

; Mensagens (ASCII puro compativel com VGA e VESA)
msg_criando:         db "[*] Montando arvore de diretorios real (/fyd) no FAT32...", 10, 0
msg_sem_disco:       db "[!] Volume FAT32 ausente: operando em cache temporario RAM.", 10, 0
msg_ok_prefixo:      db "  [OK] ", 0
msg_ja_existe:       db " (no disco)", 0
msg_erro:            db "  [ERRO] Falha ao gravar: ", 0
msg_cfg_gravado:     db "[OK] /fyd/config/sistema.fcfg gravado no disco FAT32!", 10, 0
msg_cfg_carregado:   db "[OK] /fyd/config/sistema.fcfg carregado do disco FAT32!", 10, 0
msg_concluido:       db "[OK] Estrutura /fyd pronta! CWD inicial: /fyd/usuario", 10, 0
msg_arvore:          db "ESTRUTURA DE DIRETORIOS DO SISTEMA (/fyd)", 10, \
                        "-----------------------------------------", 10, 0

section .bss
tabela_diretorios:   resq MAX_DIRETORIOS   ; Cache indexado para listagem rapida na GUI
total_diretorios:    resq 1                ; Quantidade total registrada
diretorio_atual:     resb 128              ; Diretorio corrente (CWD) da sessao
buffer_sistema_fcfg: resb 512              ; Conteudo vivo de /fyd/config/sistema.fcfg
tam_sistema_fcfg:    resq 1                ; Tamanho atual em bytes do arquivo .fcfg
fs_disco_ativo:      resb 1                ; 1 = FAT32 real montado, 0 = fallback RAM

section .text

; ============================================================================
; CONSTRUIR ESTRUTURA REAL NO BOOT
; Inicializa disco/particao/FAT32 e materializa toda a arvore /fyd no disco
; ============================================================================
construir_estrutura_sistema:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    lea rsi, [rel msg_criando]
    call print_string

    ; 1. Detecta tabela MBR/GPT e inicializa driver FAT32 real
    call inicializar_disco
    call fs_inicializar
    mov [rel fs_disco_ativo], al
    test al, al
    jnz .montar_pastas

    lea rsi, [rel msg_sem_disco]
    call print_string

.montar_pastas:
    lea rbx, [rel lista_pastas]

.loop_proxima:
    mov rdi, [rbx]
    test rdi, rdi
    jz .processar_fcfg

    ; Registra no indice rapido em RAM (se ainda nao estiver)
    call registrar_indice_ram

    ; Se disco FAT32 real nao estiver disponivel, avanca
    cmp byte [rel fs_disco_ativo], 1
    jne .avancar

    ; Verifica se diretorio ja existe fisicamente no FAT32
    push rbx
    call fs_existe
    pop rbx
    test rax, rax
    jnz .ja_no_disco

    ; Cria diretorio real no disco FAT32
    push rbx
    mov rdi, [rbx]
    call fs_criar_pasta
    pop rbx
    test rax, rax
    jz .falha_disco

    lea rsi, [rel msg_ok_prefixo]
    call print_string
    mov rsi, [rbx]
    call print_string
    call print_newline
    jmp .avancar

.ja_no_disco:
    lea rsi, [rel msg_ok_prefixo]
    call print_string
    mov rsi, [rbx]
    call print_string
    lea rsi, [rel msg_ja_existe]
    call print_string
    call print_newline
    jmp .avancar

.falha_disco:
    lea rsi, [rel msg_erro]
    call print_string
    mov rsi, [rbx]
    call print_string
    call print_newline

.avancar:
    add rbx, 8
    jmp .loop_proxima

    ; 2. Materializa ou carrega /fyd/config/sistema.fcfg no disco FAT32 real
.processar_fcfg:
    lea rdi, [rel arq_sistema_fcfg]
    call registrar_indice_ram

    cmp byte [rel fs_disco_ativo], 1
    jne .fcfg_fallback_ram

    lea rdi, [rel arq_sistema_fcfg]
    call fs_existe
    test rax, rax
    jnz .ler_fcfg_existente

    ; Arquivo ainda nao existe no disco: grava configuracao inicial real
    lea rdi, [rel arq_sistema_fcfg]
    lea rsi, [rel conteudo_sistema_fcfg]
    mov rdx, conteudo_sistema_fcfg_len
    call salvar_arquivo
    test rax, rax
    jz .fcfg_fallback_ram

    ; Copia tambem para o buffer em RAM
    lea rsi, [rel conteudo_sistema_fcfg]
    lea rdi, [rel buffer_sistema_fcfg]
    mov rcx, conteudo_sistema_fcfg_len
    mov [rel tam_sistema_fcfg], rcx
    rep movsb
    mov byte [rdi], 0

    lea rsi, [rel msg_cfg_gravado]
    call print_string
    jmp .definir_cwd

.ler_fcfg_existente:
    ; Le o arquivo real salvo no disco (preserva alteracoes de reboots anteriores)
    lea rdi, [rel arq_sistema_fcfg]
    lea rsi, [rel buffer_sistema_fcfg]
    mov rdx, 511
    call fs_ler_arquivo
    cmp rax, 0
    jl .fcfg_fallback_ram

    mov [rel tam_sistema_fcfg], rax
    lea rdi, [rel buffer_sistema_fcfg]
    mov byte [rdi + rax], 0

    lea rsi, [rel msg_cfg_carregado]
    call print_string
    jmp .definir_cwd

.fcfg_fallback_ram:
    cmp qword [rel tam_sistema_fcfg], 0
    jnz .definir_cwd
    lea rsi, [rel conteudo_sistema_fcfg]
    lea rdi, [rel buffer_sistema_fcfg]
    mov rcx, conteudo_sistema_fcfg_len
    mov [rel tam_sistema_fcfg], rcx
    rep movsb
    mov byte [rdi], 0

    ; 3. Define CWD inicial como "/fyd/usuario" tanto no VFS quanto no driver FAT32
.definir_cwd:
    lea rsi, [rel pasta_home]
    lea rdi, [rel diretorio_atual]
.copia_cwd:
    lodsb
    stosb
    test al, al
    jnz .copia_cwd

    cmp byte [rel fs_disco_ativo], 1
    jne .concluido
    lea rdi, [rel pasta_home]
    call fs_definir_caminho_atual

.concluido:
    lea rsi, [rel msg_concluido]
    call print_string

    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ============================================================================
; AUXILIAR INTERNO: Registra ponteiro na tabela_diretorios sem duplicar
; ============================================================================
registrar_indice_ram:
    push rax
    push rbx
    push rcx
    push rsi
    push rdi

    mov rcx, [rel total_diretorios]
    test rcx, rcx
    jz .inserir

    lea rbx, [rel tabela_diretorios]
.busca:
    mov rsi, [rbx]
    push rdi
    call comparar_strings
    pop rdi
    test rax, rax
    jnz .fim
    add rbx, 8
    dec rcx
    jnz .busca

.inserir:
    mov rcx, [rel total_diretorios]
    cmp rcx, MAX_DIRETORIOS
    jae .fim
    lea rbx, [rel tabela_diretorios]
    mov [rbx + rcx * 8], rdi
    inc qword [rel total_diretorios]

.fim:
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    pop rax
    ret

; ============================================================================
; ACESSORES PARA C (exec.c / fyd_formatos.c lerem /fyd/config/sistema.fcfg)
; ============================================================================
fs_ler_config_padrao:
    cmp byte [rel fs_disco_ativo], 1
    jne .ret_buf
    push rdi
    push rsi
    push rdx
    lea rdi, [rel arq_sistema_fcfg]
    lea rsi, [rel buffer_sistema_fcfg]
    mov rdx, 511
    call fs_ler_arquivo
    cmp rax, 0
    jl .pop_ret
    mov [rel tam_sistema_fcfg], rax
    lea rdi, [rel buffer_sistema_fcfg]
    mov byte [rdi + rax], 0
.pop_ret:
    pop rdx
    pop rsi
    pop rdi
.ret_buf:
    lea rax, [rel buffer_sistema_fcfg]
    ret

fs_tamanho_config_padrao:
    mov rax, [rel tam_sistema_fcfg]
    ret

; ============================================================================
; FS_CAMINHO_EXISTE: rdi = ponteiro string -> rax = 1 existe, 0 nao
; Consulta o FAT32 real primeiro e faz fallback para o indice RAM
; ============================================================================
fs_caminho_existe:
    push rbx
    push rcx
    push rsi
    push rdi

    cmp byte [rel fs_disco_ativo], 1
    jne .checa_ram

    push rdi
    call fs_existe
    pop rdi
    test rax, rax
    jnz .encontrado

.checa_ram:
    mov rcx, [rel total_diretorios]
    test rcx, rcx
    jz .nao_existe

    lea rbx, [rel tabela_diretorios]
.busca:
    mov rsi, [rbx]
    push rdi
    call comparar_strings
    pop rdi
    test rax, rax
    jnz .encontrado

    add rbx, 8
    dec rcx
    jnz .busca

.nao_existe:
    xor rax, rax
    jmp .sair

.encontrado:
    mov rax, 1

.sair:
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    ret

; ============================================================================
; FS_CRIAR_DIRETORIO: rdi = ponteiro string -> rax = 1 sucesso, 0 falha
; Cria o diretorio fisicamente no FAT32 e registra no indice RAM
; ============================================================================
fs_criar_diretorio:
    push rbx
    push rcx
    push rdi

    cmp byte [rel fs_disco_ativo], 1
    jne .apenas_ram

    push rdi
    call fs_criar_pasta
    pop rdi
    test rax, rax
    jz .falha

.apenas_ram:
    call registrar_indice_ram
    mov rax, 1
    jmp .sair

.falha:
    xor rax, rax

.sair:
    pop rdi
    pop rcx
    pop rbx
    ret

; ============================================================================
; INTERFACE PARA C (exec.c — Gerenciador de Arquivos Grafico)
; ============================================================================
fs_obter_lista_pastas:
    lea rax, [rel tabela_diretorios]
    ret

fs_total_pastas:
    mov rax, [rel total_diretorios]
    ret

; ============================================================================
; LISTAR ESTRUTURA (Comando "listar" / "arvore" no FydelTerm)
; ============================================================================
listar_estrutura:
    push rax
    push rbx
    push rcx
    push rsi
    push rdi

    call print_newline
    lea rsi, [rel msg_arvore]
    call print_string

    mov rcx, [rel total_diretorios]
    test rcx, rcx
    jz .fim

    lea rbx, [rel tabela_diretorios]

.loop:
    mov rdi, [rbx]
    push rcx

    call contar_barras
    mov rcx, rax
.indent:
    cmp rcx, 1
    jbe .mostra
    mov al, '|'
    call print_char
    mov al, ' '
    call print_char
    dec rcx
    jmp .indent

.mostra:
    mov al, '+'
    call print_char
    mov al, '-'
    call print_char
    mov al, ' '
    call print_char

    mov rsi, rdi
    call print_string
    call print_newline

    pop rcx
    add rbx, 8
    dec rcx
    jnz .loop

.fim:
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    pop rax
    ret

; ============================================================================
; UTILITARIOS INTERNOS
; ============================================================================
contar_barras:
    push rdx
    xor edx, edx
    mov rsi, rdi
.conta:
    lodsb
    test al, al
    jz .fim
    cmp al, '/'
    jne .conta
    inc edx
    jmp .conta
.fim:
    mov eax, edx
    pop rdx
    ret

comparar_strings:
    push rsi
    push rdi
.cmp_loop:
    mov al, [rsi]
    mov ah, [rdi]
    cmp al, ah
    jne .diferente
    test al, al
    jz .igual
    inc rsi
    inc rdi
    jmp .cmp_loop
.diferente:
    xor rax, rax
    jmp .fim
.igual:
    mov rax, 1
.fim:
    pop rdi
    pop rsi
    ret
