#ifndef CVE_GUARD_H
#define CVE_GUARD_H

#include <stdint.h>

void     cve_guard_iniciar(void);
int      cve_guard_verificar_padrao(const char *texto, const char *padrao);
int      cve_guard_adicionar_regra(const char *id, const char *padrao, const char *mensagem);
int      cve_guard_inspecionar_comando(const char *buffer);
uint64_t cve_guard_total_alertas(void);
void     cve_guard_zerar_alertas(void);
uint64_t cve_guard_total_regras(void);
int      cve_guard_obter_regra(uint64_t indice, char *out_id, char *out_padrao, char *out_msg);

#endif
