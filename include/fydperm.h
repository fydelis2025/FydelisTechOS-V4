#ifndef FYDPERM_H
#define FYDPERM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PERM_EXEC     0x01u
#define PERM_ESCRITA  0x02u
#define PERM_LEITURA  0x04u

#define PERM_DONO_SHIFT   6u
#define PERM_GRUPO_SHIFT  3u
#define PERM_OUTROS_SHIFT 0u

#define PERM_FYD_ONLY 0x00008000u

#define FYDPERM_OK      0
#define FYDPERM_NEGADO (-1)

typedef struct {
    uint32_t modo;
    uint32_t dono_uid;
    uint32_t grupo_gid;
    uint32_t reservado;
} FydPerm;

_Static_assert(sizeof(FydPerm) == 16, "FydPerm deve ter exatamente 16 bytes");

int fydperm_inicializar(uint32_t uid_sistema, uint32_t gid_sistema);
int fydperm_verificar(uint32_t uid, uint32_t gid,
                      const FydPerm *perm_ptr, uint32_t acesso_solicitado);
int fydperm_definir(FydPerm *perm_ptr, uint32_t modo,
                    uint32_t dono_uid, uint32_t grupo_gid);
int fydperm_bloquear_fydb(FydPerm *perm_ptr);

#ifdef __cplusplus
}
#endif

#endif
