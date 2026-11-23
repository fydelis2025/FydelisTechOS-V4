; ==========================================
; GERENCIADOR DE IDIOMAS
; Conecta pacotes → fornece strings ao sistema
; ==========================================
[BITS 64]
[DEFAULT REL]

%include "idioma.inc"

; === LISTA DE PACOTES DISPONÍVEIS ===
; Adicionar aqui cada novo pacote
extern pacote_pt_br
extern pacote_en_us


section .rodata
align 8
lista_pacotes:
    dq pacote_pt_br
    dq pacote_en_us
    dq 0                     ; Termina lista com NULL
qtd_pacotes equ ($ - lista_pacotes) / 8

section .data
align 8
idioma_ativo:     dd IDIOMA_PT_BR   ; Padrão: Português
tabela_ativa:     dq 0              ; Ponteiro para tabela corrente

section .text

; ------------------------------------------
; idioma_iniciar — Carregar idioma padrão
; ------------------------------------------
idioma_iniciar:
    ; Usar primeiro da lista (ou detecção futura)
    mov rdi, IDIOMA_PT_BR
    jmp idioma_selecionar

; ------------------------------------------
; idioma_selecionar — Trocar idioma em tempo real
; ENTRADA: EDI = código do idioma
; SAÍDA: RAX = 0 se OK, -1 se inválido
; ------------------------------------------
idioma_selecionar:
    push rbx
    push rcx
    push rsi

    ; Percorrer lista procurando o código
    mov rsi, lista_pacotes
    xor rbx, rbx
.proximo:
    mov rcx, [rsi + rbx * 8]
    test rcx, rcx
    jz .nao_encontrado

    cmp [rcx + PacoteIdioma.codigo], edi
    je .encontrado

    inc rbx
    jmp .proximo

.encontrado:
    mov [idioma_ativo], edi
    mov rax, [rcx + PacoteIdioma.tabela]
    mov [tabela_ativa], rax
    xor rax, rax
    jmp .fim

.nao_encontrado:
    mov rax, -1
.fim:
    pop rsi
    pop rcx
    pop rbx
    ret

; ------------------------------------------
; idioma_por_indice — Pegar ponteiro de pacote N
; ENTRADA: EDI = índice (0, 1, 2...)
; SAÍDA: RAX = ponteiro PacoteIdioma ou 0
; ------------------------------------------
idioma_por_indice:
    cmp edi, qtd_pacotes
    jae .invalido
    mov rax, [lista_pacotes + rdi * 8]
    ret
.invalido:
    xor rax, rax
    ret

; ------------------------------------------
; idioma_quantos — Devolver total de pacotes
; SAÍDA: EAX = quantidade
; ------------------------------------------
idioma_quantos:
    mov eax, qtd_pacotes
    ret
