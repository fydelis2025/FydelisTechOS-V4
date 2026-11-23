#ifndef TCP_H
#define TCP_H
#include <stdint.h>
#include <stddef.h>

#define TCP_STATE_CLOSED      0
#define TCP_STATE_SYN_SENT    1
#define TCP_STATE_ESTABLISHED 2
#define TCP_STATE_FIN_WAIT    3
#define TCP_STATE_CLOSE_WAIT  4

typedef void (*tcp_recv_cb)(void *user, const uint8_t *dados, int len);
typedef void (*tcp_state_cb)(void *user, int estado); /* chamado em connect/fechar/erro */

typedef struct tcp_conn {
    uint32_t ip_remoto;
    uint16_t porta_remota;
    uint16_t porta_local;

    uint32_t seq_local;     /* próximo byte a enviar */
    uint32_t ack_remoto;    /* próximo byte esperado do peer */
    uint32_t seq_enviada;   /* último byte enviado, aguardando ACK */

    uint8_t  estado;
    uint8_t  ativa;

    /* Retransmissão */
    uint32_t ticks_ultimo_envio;
    uint8_t  retransmitindo;
    uint8_t  buf_envio[1460];
    int      buf_envio_len;

    /* Callbacks */
    tcp_recv_cb  on_recv;
    tcp_state_cb on_state;
    void        *user;
} tcp_conn_t;

int  tcp_connect(uint32_t ip, uint16_t porta, tcp_recv_cb cb_recv, tcp_state_cb cb_state, void *user);
int  tcp_send(tcp_conn_t *c, const uint8_t *dados, int len);
void tcp_close(tcp_conn_t *c);
void tcp_tick(void);                 /* chame no loop principal ou timer: retransmissão */
void tcp_rx_segmento(const uint8_t *pkt, int len); /* LIGAR: chame do seu driver IP */

#endif
