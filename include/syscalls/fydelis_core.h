#ifndef FYDELIS_CORE_H
#define FYDELIS_CORE_H

#include <stdint.h>

/* Rotinas de Energia (kernel/energia.asm) */
extern void energia_reiniciar_agora(void);
extern void energia_desligar_agora(void);

/* Rotinas de Estrutura de Diretorios (kernel/estrutura.asm) */
extern void         construir_estrutura_sistema(void);
extern void         listar_estrutura(void);
extern uint64_t     fs_caminho_existe(const char *caminho);
extern uint64_t     fs_criar_diretorio(const char *caminho);
extern const char **fs_obter_lista_pastas(void);
extern uint64_t     fs_total_pastas(void);
extern char         diretorio_atual[128];

#endif /* FYDELIS_CORE_H */
