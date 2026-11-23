; ==========================================
; FYDELIS TECH OS — memmap.asm
; Detecção e Gerenciamento de Memória
; De Salvador • Bahia 🇧🇷
; ==========================================
bits 64

section .data
mem_total       dq 0        ; Memória total em bytes
mem_usado       dq 0        ; Em uso pelo kernel/reservado
mem_livre       dq 0        ; Disponível para programas

; Estrutura de entrada E820
; 0:  endereço base baixo  (4 bytes)
; 4:  endereço base alto   (4 bytes)
; 8:  tamanho baixo        (4 bytes)
; 12: tamanho alto         (4 bytes)
; 16: tipo                 (4 bytes)
; 20: atributos            (4 bytes) → presente em entradas estendidas

E820_TIPO_LIVRE     equ 1
E820_TIPO_RESERVADO  equ 2
E820_TIPO_ACPI_RECL  equ 3
E820_TIPO_NVS        equ 4
E820_TIPO_NAO_USAVEL equ 5

section .text
global mem_detect_e820
global mem_get_total
global mem_get_free
global mem_get_used
global mem_inicializar

; ==========================================
; 🔍 LER MAPA DE MEMÓRIA (E820 — da BIOS/UEFI)
; ==========================================
; ENTRADA: RSI = ponteiro para tabela E820 passada pelo bootloader
; SAÍDA:   preenche mem_total, mem_livre, mem_usado
mem_detect_e820:
    push rbx
    push rcx
    push rdx
    push rsi
    push rax

    xor rcx, rcx        ; Contador de entradas
    xor rdx, rdx        ; Soma total livre
    xor rbx, rbx        ; Soma total de memória

mem_loop:
    cmp rcx, 256        ; Máximo 256 entradas
    jae mem_done

    ; Verifica se chegamos ao fim da lista (entrada vazia)
    mov rax, [rsi]
    or  rax, [rsi + 8]
    jz mem_done

    ; Soma TOTAL (todas as regiões)
    mov rax, [rsi + 8]          ; Tamanho da região
    add rbx, rax                ; Acumula no total

    ; Verifica tipo: 1 = Livre
    mov rax, [rsi + 16]
    cmp rax, E820_TIPO_LIVRE
    jne mem_next

    ; Área livre — soma
    add rdx, rax

mem_next:
    add rsi, 32                 ; Próxima entrada (32 bytes = padrão estendido)
    inc rcx
    jmp mem_loop

mem_done:
    ; Guarda valores calculados
    mov [mem_livre], rdx
    mov [mem_total], rbx

    ; Calcula memória em uso = total - livre
    mov rax, rbx
    sub rax, rdx
    mov [mem_usado], rax

    pop rax
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; ==========================================
; 📋 INICIALIZAÇÃO COMPLETA
; ==========================================
; Chama isso do seu bootloader/kernel passando o ponteiro da tabela
mem_inicializar:
    ; RSI = endereço da tabela E820 (passado pelo bootloader)
    call mem_detect_e820

    ; Validação de segurança — se não detectou nada, usa fallback
    cmp qword [mem_total], 0
    jne .validado

    ; Fallback seguro: assume 2GB se tabela falhou
    mov qword [mem_total], 2 * 1024 * 1024 * 1024
    mov qword [mem_livre], 1 * 1024 * 1024 * 1024
    mov qword [mem_usado], 1 * 1024 * 1024 * 1024

.validado:
    ret

; ==========================================
; 📋 FUNÇÕES DE CONSULTA
; ==========================================
mem_get_total:
    mov rax, [mem_total]
    ret

mem_get_free:
    mov rax, [mem_livre]
    ret

mem_get_used:
    mov rax, [mem_usado]
    ret