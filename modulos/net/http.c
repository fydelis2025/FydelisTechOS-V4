#include "tcp.h"
#include <stdint.h>
#include <stddef.h>

#define HTTP_BUF_SIZE 16384

typedef enum {
    HTTP_IDLE = 0,
    HTTP_DNS,
    HTTP_CONNECT,
    HTTP_HEADERS,
    HTTP_BODY,
    HTTP_ERRO,
    HTTP_OK
} http_estado_t;

typedef struct {
    http_estado_t estado;
    tcp_conn_t   *conn;
    char          host[96];
    char          caminho[128];
    uint32_t      ip;

    char          resposta[HTTP_BUF_SIZE];
    int           resp_len;
    int           corpo_offset;
    int           content_length;
    uint32_t      ticks_espera;
} http_req_t;

static http_req_t req;

/* Resolve IP literal "10.0.2.2" (big-endian host) */
static uint32_t http_resolver(const char *host) {
    uint32_t ip = 0;
    int parte = 0, val = 0;
    for (int i = 0; ; i++) {
        char ch = host[i];
        if (ch >= '0' && ch <= '9') {
            val = val * 10 + (ch - '0');
        } else if (ch == '.' || ch == '\0' || ch == ':') {
            ip = (ip << 8) | (uint32_t)(val & 0xFF);
            parte++;
            val = 0;
            if (ch == '\0' || ch == ':') break;
        } else {
            return 0;
        }
    }
    return (parte == 4) ? ip : 0;
}

static void http_on_state(void *user, int estado) {
    (void)user;
    if (estado == TCP_STATE_ESTABLISHED) {
        char r[512];
        int n = 0;
        const char *p1 = "GET /";
        const char *p2 = " HTTP/1.1\r\nHost: ";
        const char *p3 = "\r\nConnection: close\r\nUser-Agent: FydelisBrowser/1.0\r\n\r\n";
        int i = 0;
        for (; p1[i]; i++) r[n++] = p1[i];
        for (i = 0; req.caminho[i]; i++) r[n++] = req.caminho[i];
        for (i = 0; p2[i]; i++) r[n++] = p2[i];
        for (i = 0; req.host[i]; i++) r[n++] = req.host[i];
        for (i = 0; p3[i]; i++) r[n++] = p3[i];

        if (req.conn) {
            tcp_send(req.conn, (const uint8_t *)r, n);
        }
        req.estado = HTTP_HEADERS;
    } else if (estado == TCP_STATE_CLOSE_WAIT || estado == TCP_STATE_CLOSED) {
        req.estado = (req.resp_len > 0) ? HTTP_OK : HTTP_ERRO;
    }
}

static void http_on_recv(void *user, const uint8_t *dados, int len) {
    (void)user;
    for (int i = 0; i < len; i++) {
        if (req.resp_len < HTTP_BUF_SIZE - 1) {
            req.resposta[req.resp_len++] = (char)dados[i];
        }
    }
    req.resposta[req.resp_len] = '\0';

    if (req.corpo_offset == 0) {
        for (int i = 0; i + 3 < req.resp_len; i++) {
            if (req.resposta[i] == '\r' && req.resposta[i + 1] == '\n' &&
                req.resposta[i + 2] == '\r' && req.resposta[i + 3] == '\n') {
                req.corpo_offset = i + 4;
                req.estado = HTTP_BODY;
                break;
            }
        }
        if (req.corpo_offset > 0) {
            const char *cl = "Content-Length:";
            for (int i = 0; i < req.corpo_offset; i++) {
                int j = 0;
                while (cl[j] && (req.resposta[i + j] | 32) == (cl[j] | 32)) j++;
                if (!cl[j]) {
                    req.content_length = 0;
                    const char *v = req.resposta + i + j;
                    while (*v == ' ') v++;
                    while (*v >= '0' && *v <= '9') {
                        req.content_length = req.content_length * 10 + (*v++ - '0');
                    }
                    break;
                }
            }
        }
    }

    if (req.corpo_offset > 0 && req.content_length >= 0 &&
        (req.resp_len - req.corpo_offset) >= req.content_length) {
        req.estado = HTTP_OK;
        if (req.conn) {
            tcp_close(req.conn);
        }
    }
}

void http_reset(void) {
    req.estado = HTTP_IDLE;
    req.conn = 0;
    req.resp_len = 0;
    req.corpo_offset = 0;
    req.content_length = -1;
    req.ticks_espera = 0;
    req.resposta[0] = '\0';
}

/* API chamada pelo FydelisBrowser (browser.c) */
int http_estado(void) {
    if (req.estado == HTTP_IDLE) return 0;
    if (req.estado == HTTP_DNS || req.estado == HTTP_CONNECT || req.estado == HTTP_HEADERS) return 1;
    if (req.estado == HTTP_BODY) return 2;
    if (req.estado == HTTP_OK) return 3;
    return -1; /* HTTP_ERRO */
}

const char *http_corpo(void) {
    if (req.corpo_offset > 0 && req.corpo_offset <= req.resp_len) {
        return req.resposta + req.corpo_offset;
    }
    return req.resposta;
}

int http_corpo_len(void) {
    if (req.corpo_offset > 0 && req.corpo_offset <= req.resp_len) {
        return req.resp_len - req.corpo_offset;
    }
    return req.resp_len;
}

int http_get(const char *url) {
    http_reset();

    /* Remove prefixo "http://" se existir */
    if (url[0] == 'h' && url[1] == 't' && url[2] == 't' && url[3] == 'p' &&
        url[4] == ':' && url[5] == '/' && url[6] == '/') {
        url += 7;
    }

    int i = 0, hi = 0, ci = 0;
    while (url[i] && url[i] != '/' && hi < 95) req.host[hi++] = url[i++];
    req.host[hi] = '\0';
    if (url[i] == '/') i++;
    while (url[i] && ci < 127) req.caminho[ci++] = url[i++];
    req.caminho[ci] = '\0';

    req.ip = http_resolver(req.host);
    if (!req.ip) {
        req.estado = HTTP_ERRO;
        return -1;
    }

    req.estado = HTTP_CONNECT;
    int idx = tcp_connect(req.ip, 80, http_on_recv, http_on_state, 0);
    if (idx < 0) {
        req.estado = HTTP_ERRO;
        return -1;
    }
    return 0;
}

void http_tick(void) {
    tcp_tick();
    if (req.estado == HTTP_CONNECT || req.estado == HTTP_HEADERS || req.estado == HTTP_BODY) {
        if (++req.ticks_espera > 500000) {
            req.estado = (req.resp_len > 0) ? HTTP_OK : HTTP_ERRO;
        }
    }
}
