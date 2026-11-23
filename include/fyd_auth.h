#ifndef AUTH_FYDELIS_H
#define AUTH_FYDELIS_H

#include <stddef.h>
#include <stdint.h>

typedef enum {
    FYD_PERM_CONVIDADO = 0,
    FYD_PERM_USUARIO   = 1,
    FYD_PERM_ADMIN     = 100,
    FYD_PERM_ROOT      = 255
} FydPermNivel;

typedef struct {
    int autenticado;
    char usuario[24];
    FydPermNivel nivel;
    uint64_t token_sessao;
} FydSessaoAtiva;

/* Inicializa módulos de banco, criptografia, cifra e permissões */
int auth_sistema_inicializar(void);

/* Verifica se já existe algum usuário cadastrado no fydb */
int auth_tem_usuarios_cadastrados(void);

/* Registra um novo usuário (exige permissão ADMIN/ROOT, ou primeiro cadastro sem usuários) */
int auth_registrar_usuario(const char *usuario, const char *senha, FydPermNivel nivel);

/* Valida credenciais usando fydb + fycrypto + fydcipher e abre sessão no fydperm */
int auth_login(const char *usuario, const char *senha);

/* Encerra sessão ativa e limpa dados sensíveis */
void auth_logout(void);

/* Consulta a sessão atual */
const FydSessaoAtiva *auth_sessao_atual(void);

/* Helper seguro para zerar buffers sensíveis na memória */
void fyd_zerar_memoria(void *ptr, size_t tam);

#endif
