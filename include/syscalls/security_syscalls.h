// ==========================================
// FYDELIS TECH OS — Syscalls: Segurança, Firewall & Criptografia
// Compartilhado: kernel (Assembly) ↔ C puro ↔ GTK 4
// ==========================================
#ifndef SECURITY_SYSCALLS_H
#define SECURITY_SYSCALLS_H

#include <stdint.h>

// === FydelisGuard — Firewall/Detecção ===
int  fg_inicializar(void);
int  fg_bloquear_ip(const char* ip);
int  fg_desbloquear_ip(const char* ip);
int  fg_verificar_pacote(const void* pacote, int tamanho);
int  fg_adicionar_regra(const char* regra);

// === Criptografia ===
int  aes256_criptografar(const void* entrada, void* saida, int tamanho, const uint8_t* chave);
int  aes256_descriptografar(const void* entrada, void* saida, int tamanho, const uint8_t* chave);
int  gerar_chave_aleatoria(uint8_t* saida, int tamanho);

// === Antivírus/Integridade ===
int  av_verificar_arquivo(const char* caminho);
int  av_atualizar_assinaturas(const void* dados, int tamanho);
int  verificar_integridade_sistema(void);
int  calcular_hash_arquivo(const char* caminho, char* saida_hash);

// === Log de Eventos ===
int  log_evento(const char* modulo, int nivel, const char* mensagem);
int  listar_eventos(const char* filtro, void* buffer, int max);

#endif // SECURITY_SYSCALLS_H
