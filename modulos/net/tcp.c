#include "tcp.h"

/* ==== LIGAR às funções e variáveis globais do driver de rede (rede.asm) ==== */
extern void     tx_pacote(const uint8_t *frame, uint64_t len);
extern uint32_t meu_ip;        /* IPv4 local configurado no rede.asm */
extern uint8_t  mac_addr[6];   /* Endereço MAC da E1000 */

#define PROTO_TCP 6
#define TCP_FLAG_FIN 0x01
#define TCP_FLAG_SYN 0x02
#define TCP_FLAG_RST 0x04
#define TCP_FLAG_PSH 0x08
#define TCP_FLAG_ACK 0x10

#define TCP_RETRANS_TICKS 50
#define TCP_MAX_RETRANS   5

static tcp_conn_t conexoes[8];
static uint16_t prox_porta_efemera = 49152;

static uint16_t htons(uint16_t v) {
    return (uint16_t)((v << 8) | (v >> 8));
}

static uint16_t ntohs(uint16_t v) {
    return htons(v);
}

static uint32_t htonl(uint32_t v) {
    return ((v & 0x000000FFU) << 24) |
           ((v & 0x0000FF00U) << 8)  |
           ((v & 0x00FF0000U) >> 8)  |
           ((v & 0xFF000000U) >> 24);
}

static uint32_t ntohl(uint32_t v) {
    return htonl(v);
}

static uint16_t tcp_prox_porto(void) {
    uint16_t p = prox_porta_efemera++;
    if (prox_porta_efemera < 49152) prox_porta_efemera = 49152;
    return p; /* armazenado em host-order na struct */
}

static uint16_t cksum(const uint16_t *d, int len) {
    uint32_t s = 0;
    while (len > 1) { s += *d++; len -= 2; }
    if (len) s += *(const uint8_t *)d;
    while (s >> 16) s = (s & 0xFFFF) + (s >> 16);
    return (uint16_t)~s;
}

/* Pseudo-header IPv4 para checksum TCP (seg já está em network byte order) */
static uint16_t cksum_tcp(uint32_t ip_src_be, uint32_t ip_dst_be,
                          const uint8_t *seg, int seg_len) {
    uint32_t total = 0;
    const uint16_t *s1 = (const uint16_t *)&ip_src_be;
    const uint16_t *s2 = (const uint16_t *)&ip_dst_be;
    total += s1[0] + s1[1];
    total += s2[0] + s2[1];
    total += htons(PROTO_TCP);
    total += htons((uint16_t)seg_len);

    const uint16_t *p = (const uint16_t *)seg;
    int n = seg_len;
    while (n > 1) { total += *p++; n -= 2; }
    if (n) total += *(const uint8_t *)p;
    while (total >> 16) total = (total & 0xFFFF) + (total >> 16);
    return (uint16_t)~total;
}

/* Encapsula segmento TCP em Ethernet + IPv4 e envia pela E1000 */
static void ip_enviar(uint32_t ip_dest_be, uint8_t proto,
                      const uint8_t *payload, int len) {
    uint8_t frame[1514];
    int ip_len = 20 + len;
    int total_len = 14 + ip_len;
    if (total_len > 1514) return;

    /* Cabeçalho Ethernet (14 bytes) */
    for (int i = 0; i < 6; i++) frame[i] = 0xFF;
    for (int i = 0; i < 6; i++) frame[6 + i] = mac_addr[i];
    frame[12] = 0x08;
    frame[13] = 0x00;

    /* Cabeçalho IPv4 (20 bytes) */
    uint8_t *ip = frame + 14;
    ip[0] = 0x45;
    ip[1] = 0x00;
    ip[2] = (uint8_t)(ip_len >> 8);
    ip[3] = (uint8_t)(ip_len & 0xFF);
    ip[4] = 0x00; ip[5] = 0x01;
    ip[6] = 0x00; ip[7] = 0x00;
    ip[8] = 64;
    ip[9] = proto;
    ip[10] = 0; ip[11] = 0;

    uint32_t src_be = htonl(meu_ip);
    *(uint32_t *)(ip + 12) = src_be;
    *(uint32_t *)(ip + 16) = ip_dest_be;

    uint16_t cs = cksum((const uint16_t *)ip, 20);
    *(uint16_t *)(ip + 10) = cs;

    for (int i = 0; i < len; i++) frame[34 + i] = payload[i];
    tx_pacote(frame, (uint64_t)total_len);
}

/* Cabeçalho TCP: 20 bytes (sem opções) */
typedef struct __attribute__((packed)) {
    uint16_t porta_src, porta_dst;
    uint32_t seq, ack;
    uint8_t  offset_res;
    uint8_t  flags;
    uint16_t janela, checksum, urgente;
} tcp_hdr_t;

static void tcp_enviar_segmento(tcp_conn_t *c, uint8_t flags,
                                const uint8_t *payload, int plen) {
    uint8_t seg[1460 + 20];
    tcp_hdr_t *h = (tcp_hdr_t *)seg;

    uint32_t seq_atual = c->seq_local;
    h->porta_src  = htons(c->porta_local);
    h->porta_dst  = htons(c->porta_remota);
    h->seq        = htonl(seq_atual);
    h->ack        = htonl(c->ack_remoto);
    h->offset_res = 0x50;
    h->flags      = flags;
    h->janela     = htons(8192);
    h->checksum   = 0;
    h->urgente    = 0;

    for (int i = 0; i < plen; i++) seg[20 + i] = payload[i];

    if (flags & (TCP_FLAG_SYN | TCP_FLAG_FIN)) c->seq_local++;
    else c->seq_local += (uint32_t)plen;

    uint32_t ip_src_be = htonl(meu_ip);
    uint32_t ip_dst_be = htonl(c->ip_remoto);
    h->checksum = cksum_tcp(ip_src_be, ip_dst_be, seg, 20 + plen);

    if ((flags & (TCP_FLAG_SYN | TCP_FLAG_FIN)) || plen > 0) {
        c->seq_enviada = seq_atual;
        c->buf_envio_len = plen;
        for (int i = 0; i < plen; i++) c->buf_envio[i] = payload[i];
        c->ticks_ultimo_envio = 0;
        c->retransmitindo = 1;
    }

    ip_enviar(ip_dst_be, PROTO_TCP, seg, 20 + plen);
}

void tcp_rx_segmento(const uint8_t *pkt, int len) {
    if (len < 20) return;
    const tcp_hdr_t *h = (const tcp_hdr_t *)pkt;
    uint16_t porta_dst = ntohs(h->porta_dst);

    tcp_conn_t *c = 0;
    for (int i = 0; i < 8; i++) {
        if (conexoes[i].ativa && conexoes[i].porta_local == porta_dst) {
            c = &conexoes[i];
            break;
        }
    }
    if (!c) return;

    int hdr_len = (h->offset_res >> 4) * 4;
    if (hdr_len < 20 || hdr_len > len) return;
    const uint8_t *payload = pkt + hdr_len;
    int plen = len - hdr_len;
    uint8_t flags = h->flags;

    if ((flags & TCP_FLAG_ACK) && c->retransmitindo) {
        c->retransmitindo = 0;
    }

    switch (c->estado) {
    case TCP_STATE_SYN_SENT:
        if ((flags & (TCP_FLAG_SYN | TCP_FLAG_ACK)) == (TCP_FLAG_SYN | TCP_FLAG_ACK)) {
            c->ack_remoto = ntohl(h->seq) + 1;
            c->estado = TCP_STATE_ESTABLISHED;
            tcp_enviar_segmento(c, TCP_FLAG_ACK, 0, 0);
            if (c->on_state) c->on_state(c->user, TCP_STATE_ESTABLISHED);
        }
        break;

    case TCP_STATE_ESTABLISHED:
        if (plen > 0) {
            if (c->on_recv) c->on_recv(c->user, payload, plen);
            c->ack_remoto += (uint32_t)plen;
            tcp_enviar_segmento(c, TCP_FLAG_ACK, 0, 0);
        }
        if (flags & TCP_FLAG_FIN) {
            c->ack_remoto++;
            tcp_enviar_segmento(c, TCP_FLAG_ACK, 0, 0);
            c->estado = TCP_STATE_CLOSE_WAIT;
            if (c->on_state) c->on_state(c->user, TCP_STATE_CLOSE_WAIT);
        }
        break;

    case TCP_STATE_FIN_WAIT:
        if (flags & TCP_FLAG_FIN) {
            c->ack_remoto++;
            tcp_enviar_segmento(c, TCP_FLAG_ACK, 0, 0);
            c->estado = TCP_STATE_CLOSED;
            c->ativa = 0;
            if (c->on_state) c->on_state(c->user, TCP_STATE_CLOSED);
        }
        break;
    }
}

int tcp_connect(uint32_t ip, uint16_t porta, tcp_recv_cb cb_recv,
                tcp_state_cb cb_state, void *user) {
    tcp_conn_t *c = 0;
    int idx = -1;
    for (int i = 0; i < 8; i++) {
        if (!conexoes[i].ativa) {
            c = &conexoes[i];
            idx = i;
            break;
        }
    }
    if (!c) return -1;

    c->ip_remoto      = ip;
    c->porta_remota   = porta;
    c->porta_local    = tcp_prox_porto();
    c->seq_local      = 1000;
    c->ack_remoto     = 0;
    c->estado         = TCP_STATE_SYN_SENT;
    c->ativa          = 1;
    c->retransmitindo = 0;
    c->on_recv        = cb_recv;
    c->on_state       = cb_state;
    c->user           = user;

    tcp_enviar_segmento(c, TCP_FLAG_SYN, 0, 0);
    return idx;
}

tcp_conn_t *tcp_obter_conn(int idx) {
    if (idx < 0 || idx >= 8 || !conexoes[idx].ativa) return 0;
    return &conexoes[idx];
}

int tcp_send(tcp_conn_t *c, const uint8_t *dados, int len) {
    if (!c || c->estado != TCP_STATE_ESTABLISHED) return -1;
    if (c->retransmitindo) return -1;
    tcp_enviar_segmento(c, TCP_FLAG_ACK | TCP_FLAG_PSH, dados, len);
    return 0;
}

void tcp_close(tcp_conn_t *c) {
    if (!c) return;
    if (c->estado == TCP_STATE_ESTABLISHED) {
        tcp_enviar_segmento(c, TCP_FLAG_FIN | TCP_FLAG_ACK, 0, 0);
    }
    c->estado = TCP_STATE_FIN_WAIT;
}

void tcp_tick(void) {
    for (int i = 0; i < 8; i++) {
        tcp_conn_t *c = &conexoes[i];
        if (!c->ativa || !c->retransmitindo) continue;
        if (++c->ticks_ultimo_envio > TCP_RETRANS_TICKS) {
            c->ticks_ultimo_envio = 0;
            uint8_t flags = TCP_FLAG_ACK;
            if (c->estado == TCP_STATE_SYN_SENT) flags = TCP_FLAG_SYN;
            else if (c->estado == TCP_STATE_FIN_WAIT) flags |= TCP_FLAG_FIN;
            else if (c->buf_envio_len > 0) flags |= TCP_FLAG_PSH;

            c->seq_local = c->seq_enviada;
            tcp_enviar_segmento(c, flags, c->buf_envio, c->buf_envio_len);
        }
    }
}
