// ==========================================
// FYDELIS TECH OS — Syscalls: Usuários & Autenticação
// Compartilhado: kernel (Assembly) ↔ C puro ↔ GTK 4
// ==========================================
#ifndef USER_SYSCALLS_H
#define USER_SYSCALLS_H

#include <stdint.h>

#define USUARIO_NOME_MAX  32
#define SENHA_HASH_LEN    32

typedef struct {
    char     nome[USUARIO_NOME_MAX];
    uint8_t  senha_hash[SENHA_HASH_LEN];
    int      nivel;      // 0=admin, 1=usuario, 2=convidado
    int      ativo;
    uint64_t ultimo_acesso;
} UsuarioInfo;

// === AUTENTICAÇÃO ===
int  login(const char* usuario, const char* senha);
int  logout(void);
int  usuario_ativo(char* saida_nome, int tam);
int  permissao_atual(void);

// === GERENCIAMENTO ===
int  criar_usuario(const char* nome, const char* senha, int nivel);
int  remover_usuario(const char* nome);
int  alterar_senha(const char* nome, const char* senha_antiga, const char* senha_nova);
int  listar_usuarios(void* buffer, int max);

// === PERMISSÕES ===
int  verificar_permissao(const char* recurso, int acao);
int  definir_permissao(const char* usuario, const char* recurso, int permissao);

#endif // USER_SYSCALLS_H
