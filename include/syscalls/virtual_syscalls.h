// ==========================================
// FYDELIS TECH OS — Syscalls: Virtualização & Sandbox
// Compartilhado: kernel (Assembly) ↔ C puro ↔ GTK 4
// ==========================================
#ifndef VIRTUAL_SYSCALLS_H
#define VIRTUAL_SYSCALLS_H

#include <stdint.h>

typedef struct {
    int      id;
    char     nome[32];
    uint64_t ram_alocada;
    int      cpu_nucleos;
    int      ativo;
    uint64_t tempo_execucao;
} VMInfo;

// === MÁQUINAS VIRTUAIS ===
int     vm_criar(const char* nome, uint64_t ram, int nucleos);
int     vm_iniciar(int id);
int     vm_parar(int id);
int     vm_destruir(int id);
int     vm_listar(void* buffer, int max);
VMInfo* vm_status(int id);

// === SANDBOX / ISOLAMENTO ===
int     sandbox_iniciar(const char* programa, const char* restricoes);
int     sandbox_verificar_recurso(const char* caminho, int tipo_acesso);
int     sandbox_encerrar(void);

// === RECURSOS ===
int     limite_memoria(uint64_t max_bytes);
int     limite_cpu(int porcentagem);
int     monitorar_recursos(int* uso_cpu, uint64_t* uso_memoria);

#endif // VIRTUAL_SYSCALLS_H
