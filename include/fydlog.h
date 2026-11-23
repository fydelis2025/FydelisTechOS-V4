#ifndef FYDLOG_H
#define FYDLOG_H

#include <stdint.h>

#define LOG_INFO    0
#define LOG_AVISO   1
#define LOG_ERRO    2
#define LOG_CRITICO 3

extern uint64_t    fydlog_inicializar(void);
extern void        fydlog_escrever(int tipo, const char *mensagem);
extern void        fydlog_ler_todos(void);
extern const char *fydlog_obter_buffer(void);
extern uint64_t    fydlog_obter_tamanho(void);
extern void        fydlog_fechar(void);

#endif
