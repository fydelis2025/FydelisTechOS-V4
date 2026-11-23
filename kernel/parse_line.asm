BITS 64
%include "../inc/fydelterm.inc"

extern buffer
extern argc, argv       ; ✅ PRECISA TER ESTAS DUAS LINHAS!

global parse_line

section .text
parse_line:
    push rsi
    push rdi
    push rbx

    mov  rsi, buffer       ; Lê o que foi digitado
    mov  rdi, argv         ; Vetor de argumentos
    xor  rcx, rcx          ; argc = 0 no começo

    ; PULA ESPAÇOS NO INÍCIO
.skip_spc:
    cmp  rcx, MAX_ARGS
    jae  .fim

    mov  al, [rsi]
    cmp  al, KEY_SPACE
    je   .avanca
    cmp  al, 0
    je   .fim
    jmp  .salva_ponteiro

.avanca:
    inc  rsi
    jmp  .skip_spc

.salva_ponteiro:
    mov  [rdi], rsi        ; Salva início da palavra
    add  rdi, 8
    inc  rcx               ; ✅ conta +1 argumento

.letras:
    mov  al, [rsi]
    cmp  al, 0
    je   .fecha_palavra
    cmp  al, KEY_SPACE
    je   .fecha_palavra
    inc  rsi
    jmp  .letras

.fecha_palavra:
    mov  byte [rsi], 0     ; fecha string
    cmp  al, 0
    je   .fim
    inc  rsi
    jmp  .skip_spc

.fim:
    mov  qword [rdi], 0    ; NULL no fim
    mov  [argc], rcx        ; ✅ GUARDA quantidade

    pop  rbx
    pop  rdi
    pop  rsi
    ret
