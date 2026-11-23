#ifndef FYDB_H
#define FYDB_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define FYDB_ASSINATURA_U32  0x42445946u
#define FYDB_VERSAO_ATUAL    1u
#define FYDB_CABECALHO_BYTES 64u
#define FYDB_TAM_MAX_REG     512u

enum {
    FYDB_OK             =  0,
    FYDB_ERRO_IO        = -1,
    FYDB_NAO_ENCONTRADO = -2,
    FYDB_CHEIO          = -3,
    FYDB_ERRO_PARAM     = -4
};

int  fydb_init(int fd, size_t tam_registro, size_t max_registros);
int  fydb_ler(int fd, size_t indice, void *buffer);
int  fydb_escrever(int fd, size_t indice, const void *registro);
long fydb_inserir(int fd, const void *registro);
int  fydb_remover(int fd, size_t indice);
long fydb_buscar(int fd, const void *chave, size_t offset_campo, size_t tam_campo);
long fydb_contar(int fd);
long fydb_capacidade(int fd);
int  fydb_proteger(int fd);

#ifdef __cplusplus
}
#endif

#endif
