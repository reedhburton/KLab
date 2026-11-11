#define _GNU_SOURCE
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <dirent.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define AGENT_VERSION "1"
#define MAX_PROCS 128
#define MAX_ID 64
#define MAX_PATH 1024
#define MAX_LINE 16384
#define MAX_CMD 8192
#define MAX_REPLY 512

typedef struct {
    int used;
    char id[MAX_ID];
    pid_t pid;
    int exited;
    int exit_code;
    int term_sig;
    char out_path[MAX_PATH];
    char err_path[MAX_PATH];
} proc_t;

static proc_t procs[MAX_PROCS];
static char g_socket[MAX_PATH] = "/tmp/klab-agent.sock";
static char g_state[MAX_PATH] = "/tmp/klab-agent";
static volatile sig_atomic_t g_stop = 0;

static void die(const char *msg) { perror(msg); exit(2); }

static int copy_checked(char *dst, size_t cap, const char *src) {
    size_t n = strlen(src);
    if (n >= cap) return -1;
    memcpy(dst, src, n + 1);
    return 0;
}

static int path_join2(char *dst, size_t cap, const char *a, const char *b) {
    size_t na = strlen(a), nb = strlen(b);
    int slash = (na > 0 && a[na - 1] != '/');
    if (na + (size_t)slash + nb + 1 > cap) return -1;
    memcpy(dst, a, na);
    size_t p = na;
    if (slash) dst[p++] = '/';
    memcpy(dst + p, b, nb);
    dst[p + nb] = '\0';
    return 0;
}

static int safe_name(const char *s) {
    size_t n = strlen(s);
    if (!n || n >= MAX_ID) return 0;
    for (size_t i = 0; i < n; i++) {
        char c = s[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.')) return 0;
    }
    return 1;
}

static int mkdir_p(const char *path, mode_t mode) {
    char tmp[MAX_PATH];
    if (copy_checked(tmp, sizeof(tmp), path) < 0 || !tmp[0]) return -1;
    for (char *p = tmp + 1; *p; p++) {
        if (*p != '/') continue;
        *p = '\0';
        if (mkdir(tmp, mode) < 0 && errno != EEXIST) return -1;
        *p = '/';
    }
    if (mkdir(tmp, mode) < 0 && errno != EEXIST) return -1;
    return 0;
}

static long long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (long long)ts.tv_sec * 1000LL + ts.tv_nsec / 1000000;
}

static void sleep_ms(int ms) {
    struct timespec ts = { ms / 1000, (long)(ms % 1000) * 1000000L };
    while (nanosleep(&ts, &ts) < 0 && errno == EINTR) { }
}

static void on_sig(int sig) { (void)sig; g_stop = 1; }

static const char b64tab[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static int b64val(unsigned char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

static unsigned char *b64decode(const char *in, size_t *outlen) {
    size_t len = strlen(in), cap = (len / 4 + 1) * 3 + 1, oi = 0;
    unsigned char *out = malloc(cap);
    if (!out) return NULL;
    int val = 0, valb = -8;
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)in[i];
        if (c == '=') break;
        int d = b64val(c);
        if (d < 0) { free(out); return NULL; }
        val = (val << 6) | d;
        valb += 6;
        if (valb >= 0) {
            out[oi++] = (unsigned char)((val >> valb) & 0xff);
            valb -= 8;
        }
    }
    out[oi] = '\0';
    *outlen = oi;
    return out;
}

static char *b64encode(const unsigned char *in, size_t len) {
    size_t olen = 4 * ((len + 2) / 3), i = 0, o = 0;
    char *out = malloc(olen + 1);
    if (!out) return NULL;
    while (i < len) {
        uint32_t a = i < len ? in[i++] : 0;
        uint32_t b = i < len ? in[i++] : 0;
        uint32_t c = i < len ? in[i++] : 0;
        uint32_t t = (a << 16) | (b << 8) | c;
        out[o++] = b64tab[(t >> 18) & 63];
        out[o++] = b64tab[(t >> 12) & 63];
        out[o++] = b64tab[(t >> 6) & 63];
        out[o++] = b64tab[t & 63];
    }
    if (len % 3) {
        out[olen - 1] = '=';
        if (len % 3 == 1) out[olen - 2] = '=';
    }
    out[olen] = '\0';
    return out;
}

static unsigned char *read_file(const char *path, size_t *len) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return NULL;
    size_t cap = 4096, n = 0;
    unsigned char *buf = malloc(cap + 1);
    if (!buf) { close(fd); return NULL; }
    for (;;) {
        if (n == cap) {
            if (cap >= 16U * 1024U * 1024U) break;
            size_t ncap = cap * 2;
            unsigned char *nbuf = realloc(buf, ncap + 1);
            if (!nbuf) { free(buf); close(fd); return NULL; }
            buf = nbuf; cap = ncap;
        }
        ssize_t r = read(fd, buf + n, cap - n);
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) break;
        n += (size_t)r;
    }
    close(fd);
    buf[n] = '\0';
    *len = n;
    return buf;
}

static int write_all(int fd, const void *buf, size_t n) {
    const char *p = (const char *)buf;
    while (n) {
        ssize_t w = write(fd, p, n);
        if (w < 0) { if (errno == EINTR) continue; return -1; }
        p += w; n -= (size_t)w;
    }
    return 0;
}

static int sendf(int fd, const char *fmt, ...) {
    char buf[4096];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (n < 0) return -1;
    if ((size_t)n >= sizeof(buf)) return -1;
    return write_all(fd, buf, (size_t)n);
}

static proc_t *find_proc(const char *id) {
    for (int i = 0; i < MAX_PROCS; i++) if (procs[i].used && !strcmp(procs[i].id, id)) return &procs[i];
    return NULL;
}

static proc_t *new_proc(const char *id) {
    if (find_proc(id)) return NULL;
    for (int i = 0; i < MAX_PROCS; i++) {
        if (procs[i].used) continue;
        memset(&procs[i], 0, sizeof(procs[i]));
        procs[i].used = 1;
        if (copy_checked(procs[i].id, sizeof(procs[i].id), id) < 0) return NULL;
        return &procs[i];
    }
    return NULL;
}

static void reap(void) {
    int st; pid_t p;
    while ((p = waitpid(-1, &st, WNOHANG)) > 0) {
        for (int i = 0; i < MAX_PROCS; i++) {
            if (!procs[i].used || procs[i].pid != p) continue;
            procs[i].exited = 1;
            if (WIFEXITED(st)) procs[i].exit_code = WEXITSTATUS(st);
            else if (WIFSIGNALED(st)) procs[i].term_sig = WTERMSIG(st);
            break;
        }
    }
}

static void status_line(int fd, proc_t *p, const char *prefix) {
    reap();
    sendf(fd, "OK %s %s %s %ld %d %d\n", prefix, p->id,
          p->exited ? "exited" : "running", (long)p->pid,
          p->exited ? p->exit_code : -1, p->term_sig);
}

static int spawn_proc(proc_t *p, const char *cmd) {
    char logs[MAX_PATH], outname[MAX_ID + 16], errname[MAX_ID + 16];
    if (path_join2(logs, sizeof(logs), g_state, "processes") < 0) return -1;
    if (mkdir_p(logs, 0755) < 0) return -1;
    if (snprintf(outname, sizeof(outname), "%s.stdout", p->id) < 0) return -1;
    if (snprintf(errname, sizeof(errname), "%s.stderr", p->id) < 0) return -1;
    if (path_join2(p->out_path, sizeof(p->out_path), logs, outname) < 0) return -1;
    if (path_join2(p->err_path, sizeof(p->err_path), logs, errname) < 0) return -1;

    pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid == 0) {
        setpgid(0, 0);
        int out = open(p->out_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        int err = open(p->err_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (out < 0 || err < 0) _exit(126);
        dup2(out, STDOUT_FILENO); dup2(err, STDERR_FILENO);
        if (out > 2) close(out);
        if (err > 2) close(err);
        setenv("KLAB_AGENT_SOCKET", g_socket, 1);
        setenv("KLAB_AGENT_STATE", g_state, 1);
        execl("/bin/sh", "sh", "-c", cmd, (char *)NULL);
        _exit(127);
    }
    setpgid(pid, pid);
    p->pid = pid;
    return 0;
}

static void kill_running(void) {
    reap();
    for (int i = 0; i < MAX_PROCS; i++) if (procs[i].used && !procs[i].exited && procs[i].pid > 1) kill(-procs[i].pid, SIGTERM);
    sleep_ms(100);
    reap();
    for (int i = 0; i < MAX_PROCS; i++) if (procs[i].used && !procs[i].exited && procs[i].pid > 1) kill(-procs[i].pid, SIGKILL);
}

static int send_file_data(int fd, const char *path) {
    size_t len = 0; unsigned char *buf = read_file(path, &len);
    if (!buf) return sendf(fd, "DATA \n");
    char *enc = b64encode(buf, len); free(buf);
    if (!enc) return sendf(fd, "ERR oom\n");
    int rc = sendf(fd, "DATA %s\n", enc); free(enc); return rc;
}

static void handle_client(int fd) {
    char *line = malloc(MAX_LINE);
    if (!line) { close(fd); return; }
    ssize_t n = read(fd, line, MAX_LINE - 1);
    if (n <= 0) { free(line); close(fd); return; }
    line[n] = '\0'; char *nl = strchr(line, '\n'); if (nl) *nl = '\0';
    char *save = NULL, *cmd = strtok_r(line, " ", &save);
    if (!cmd) { sendf(fd, "ERR empty\n"); goto out; }
    reap();

    if (!strcmp(cmd, "PING")) { sendf(fd, "OK PONG %s\n", AGENT_VERSION); goto out; }
    if (!strcmp(cmd, "SPAWN64")) {
        char *id = strtok_r(NULL, " ", &save), *enc = strtok_r(NULL, " ", &save);
        if (!id || !enc || !safe_name(id)) { sendf(fd, "ERR spawn-args\n"); goto out; }
        proc_t *p = new_proc(id);
        if (!p) { sendf(fd, "ERR duplicate-or-full %s\n", id); goto out; }
        size_t clen = 0; unsigned char *dec = b64decode(enc, &clen);
        if (!dec || clen > MAX_CMD) { p->used = 0; free(dec); sendf(fd, "ERR bad-base64\n"); goto out; }
        if (spawn_proc(p, (char *)dec) < 0) { p->used = 0; free(dec); sendf(fd, "ERR spawn-failed\n"); goto out; }
        free(dec); sendf(fd, "OK SPAWN %s %ld\n", id, (long)p->pid); goto out;
    }
    if (!strcmp(cmd, "STATUS")) {
        char *id = strtok_r(NULL, " ", &save); proc_t *p = id ? find_proc(id) : NULL;
        if (!p) { sendf(fd, "ERR no-such-process\n"); goto out; }
        status_line(fd, p, "STATUS"); goto out;
    }
    if (!strcmp(cmd, "WAIT")) {
        char *id = strtok_r(NULL, " ", &save), *tm = strtok_r(NULL, " ", &save); proc_t *p = id ? find_proc(id) : NULL;
        if (!p) { sendf(fd, "ERR no-such-process\n"); goto out; }
        int timeout = tm ? atoi(tm) : 30000; if (timeout < 0) timeout = 0;
        long long end = now_ms() + timeout;
        while (!p->exited && now_ms() < end) { reap(); if (!p->exited) sleep_ms(20); }
        reap();
        if (!p->exited) { sendf(fd, "ERR TIMEOUT %s\n", id); goto out; }
        status_line(fd, p, "WAIT"); goto out;
    }
    if (!strcmp(cmd, "SIGNAL")) {
        char *id = strtok_r(NULL, " ", &save), *ss = strtok_r(NULL, " ", &save); proc_t *p = id ? find_proc(id) : NULL;
        if (!p || !ss) { sendf(fd, "ERR signal-args\n"); goto out; }
        int sig = atoi(ss); if (sig <= 0 || sig >= NSIG) { sendf(fd, "ERR bad-signal\n"); goto out; }
        if (kill(-p->pid, sig) < 0 && errno != ESRCH) { sendf(fd, "ERR signal-failed\n"); goto out; }
        sendf(fd, "OK SIGNAL %s %d\n", id, sig); goto out;
    }
    if (!strcmp(cmd, "OUTPUT")) {
        char *id = strtok_r(NULL, " ", &save), *which = strtok_r(NULL, " ", &save); proc_t *p = id ? find_proc(id) : NULL;
        if (!p || !which) { sendf(fd, "ERR output-args\n"); goto out; }
        const char *path = !strcmp(which, "stdout") ? p->out_path : (!strcmp(which, "stderr") ? p->err_path : NULL);
        if (!path) { sendf(fd, "ERR output-stream\n"); goto out; }
        send_file_data(fd, path); goto out;
    }
    if (!strcmp(cmd, "EVENTS")) {
        char path[MAX_PATH]; if (path_join2(path, sizeof(path), g_state, "events.log") < 0) { sendf(fd, "ERR state-path\n"); goto out; }
        send_file_data(fd, path); goto out;
    }
    if (!strcmp(cmd, "SHUTDOWN")) { sendf(fd, "OK SHUTDOWN\n"); g_stop = 1; goto out; }
    sendf(fd, "ERR unknown-command\n");
out:
    free(line); close(fd);
}

static int fill_sockaddr(struct sockaddr_un *un) {
    memset(un, 0, sizeof(*un)); un->sun_family = AF_UNIX;
    if (strlen(g_socket) >= sizeof(un->sun_path)) return -1;
    memcpy(un->sun_path, g_socket, strlen(g_socket) + 1);
    return 0;
}

static int daemon_main(void) {
    if (mkdir_p(g_state, 0755) < 0) die("mkdir state");
    unlink(g_socket);
    int s = socket(AF_UNIX, SOCK_STREAM, 0); if (s < 0) die("socket");
    struct sockaddr_un un; if (fill_sockaddr(&un) < 0) { fprintf(stderr, "socket path too long\n"); return 2; }
    if (bind(s, (struct sockaddr *)&un, sizeof(un)) < 0) die("bind");
    chmod(g_socket, 0600); if (listen(s, 16) < 0) die("listen");
    signal(SIGTERM, on_sig); signal(SIGINT, on_sig); signal(SIGPIPE, SIG_IGN);
    while (!g_stop) {
        int fd = accept(s, NULL, NULL);
        if (fd < 0) { if (g_stop) break; if (errno != EINTR) sleep_ms(10); continue; }
        handle_client(fd);
    }
    kill_running(); close(s); unlink(g_socket); return 0;
}

static int connect_agent(void) {
    int s = socket(AF_UNIX, SOCK_STREAM, 0); if (s < 0) return -1;
    struct sockaddr_un un; if (fill_sockaddr(&un) < 0) { close(s); return -1; }
    if (connect(s, (struct sockaddr *)&un, sizeof(un)) < 0) { close(s); return -1; }
    return s;
}

static int client_line(const char *line, int decode_data) {
    int s = connect_agent(); if (s < 0) { perror("connect"); return 2; }
    size_t request_len = strlen(line);
    char *request = malloc(request_len + 2);
    if (!request) { fprintf(stderr, "agent request allocation failed: %zu bytes\n", request_len + 2); close(s); return 2; }
    memcpy(request, line, request_len); request[request_len++] = '\n';
    if (write_all(s, request, request_len) < 0) { perror("agent request write"); free(request); close(s); return 2; }
    free(request);
    size_t cap = decode_data ? MAX_LINE : MAX_REPLY;
    char *buf = malloc(cap); if (!buf) { fprintf(stderr, "agent reply allocation failed: %zu bytes\n", cap); close(s); return 2; }
    ssize_t n = read(s, buf, cap - 1); close(s);
    if (n <= 0) { if (n < 0) perror("agent reply read"); else fprintf(stderr, "agent reply closed before response\n"); free(buf); return 2; }
    buf[n] = '\0';
    if (!strncmp(buf, "DATA ", 5) && decode_data) {
        char *enc = buf + 5, *nl = strchr(enc, '\n'); if (nl) *nl = '\0';
        size_t len = 0; unsigned char *dec = b64decode(enc, &len);
        if (dec) { write_all(STDOUT_FILENO, dec, len); free(dec); }
        free(buf); return 0;
    }
    fputs(buf, stdout);
    int rc = !strncmp(buf, "OK ", 3) ? 0 : (!strncmp(buf, "ERR TIMEOUT", 11) ? 124 : 1);
    free(buf); return rc;
}

static int start_daemon(void) {
    pid_t p = fork(); if (p < 0) return 2;
    if (p == 0) {
        if (setsid() < 0) _exit(2);
        int dn = open("/dev/null", O_RDWR);
        if (dn >= 0) { dup2(dn, 0); dup2(dn, 1); dup2(dn, 2); if (dn > 2) close(dn); }
        _exit(daemon_main());
    }
    for (int i = 0; i < 1000; i++) {
        int s = connect_agent();
        if (s >= 0) {
            char reply[64];
            if (write_all(s, "PING\n", 5) == 0) {
                ssize_t n = read(s, reply, sizeof(reply) - 1);
                if (n > 0) { reply[n] = '\0'; close(s); if (!strncmp(reply, "OK PONG ", 8)) return 0; }
                else close(s);
            } else close(s);
        }
        sleep_ms(20);
    }
    return 2;
}

static int barrier_cmd(const char *name, int count, const char *participant, int timeout) {
    if (!safe_name(name) || !safe_name(participant) || count < 1) return 2;
    char barriers[MAX_PATH], dir[MAX_PATH], pname[MAX_ID + 4], mark[MAX_PATH], rel[MAX_PATH];
    if (path_join2(barriers, sizeof(barriers), g_state, "barriers") < 0 || path_join2(dir, sizeof(dir), barriers, name) < 0) return 2;
    if (mkdir_p(dir, 0755) < 0) return 2;
    if (snprintf(pname, sizeof(pname), "p-%s", participant) < 0 || path_join2(mark, sizeof(mark), dir, pname) < 0 || path_join2(rel, sizeof(rel), dir, "RELEASE") < 0) return 2;
    int fd = open(mark, O_WRONLY | O_CREAT, 0644); if (fd >= 0) close(fd);
    long long end = now_ms() + timeout;
    while (now_ms() < end) {
        if (access(rel, F_OK) == 0) return 0;
        int seen = 0; DIR *d = opendir(dir);
        if (d) { struct dirent *de; while ((de = readdir(d))) if (!strncmp(de->d_name, "p-", 2)) seen++; closedir(d); }
        if (seen >= count) { int rf = open(rel, O_WRONLY | O_CREAT, 0644); if (rf >= 0) close(rf); return 0; }
        sleep_ms(10);
    }
    return 124;
}

static int event_cmd(const char *name, const char *value) {
    if (!safe_name(name) || mkdir_p(g_state, 0755) < 0) return 2;
    char path[MAX_PATH]; if (path_join2(path, sizeof(path), g_state, "events.log") < 0) return 2;
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644); if (fd < 0) return 2;
    dprintf(fd, "%lld\t%ld\t%s\t%s\n", now_ms(), (long)getpid(), name, value ? value : ""); close(fd); return 0;
}

static int gate_paths(const char *name, const char *participant, char *dir, size_t dcap, char *mark, size_t mcap, char *rel, size_t rcap) {
    char gates[MAX_PATH], pname[MAX_ID + 4];
    if (!safe_name(name) || (participant && !safe_name(participant))) return -1;
    if (path_join2(gates, sizeof(gates), g_state, "gates") < 0 || path_join2(dir, dcap, gates, name) < 0) return -1;
    if (participant) {
        if (snprintf(pname, sizeof(pname), "p-%s", participant) < 0 || path_join2(mark, mcap, dir, pname) < 0) return -1;
    } else if (mark && mcap) mark[0] = '\0';
    if (path_join2(rel, rcap, dir, "RELEASE") < 0) return -1;
    return 0;
}

static int gate_wait_cmd(const char *name, const char *participant, int timeout) {
    char dir[MAX_PATH], mark[MAX_PATH], rel[MAX_PATH], ev[MAX_ID * 2 + 4];
    if (gate_paths(name, participant, dir, sizeof(dir), mark, sizeof(mark), rel, sizeof(rel)) < 0) return 2;
    if (mkdir_p(dir, 0755) < 0) return 2;
    int fd = open(mark, O_WRONLY | O_CREAT, 0644); if (fd >= 0) close(fd); else return 2;
    snprintf(ev, sizeof(ev), "%s:%s", name, participant); event_cmd("gate_wait", ev);
    long long end = now_ms() + timeout;
    while (now_ms() < end) {
        if (access(rel, F_OK) == 0) { event_cmd("gate_release", ev); return 0; }
        sleep_ms(10);
    }
    event_cmd("gate_timeout", ev); return 124;
}

static int gate_release_cmd(const char *name) {
    char dir[MAX_PATH], mark[MAX_PATH], rel[MAX_PATH];
    if (gate_paths(name, NULL, dir, sizeof(dir), mark, sizeof(mark), rel, sizeof(rel)) < 0) return 2;
    if (mkdir_p(dir, 0755) < 0) return 2;
    int fd = open(rel, O_WRONLY | O_CREAT, 0644); if (fd < 0) return 2; close(fd);
    return event_cmd("gate_host_release", name);
}

static int gate_status_cmd(const char *name, const char *participant) {
    char dir[MAX_PATH], mark[MAX_PATH], rel[MAX_PATH];
    if (gate_paths(name, participant, dir, sizeof(dir), mark, sizeof(mark), rel, sizeof(rel)) < 0) return 2;
    if (access(rel, F_OK) == 0) { puts("RELEASED"); return 0; }
    if (access(mark, F_OK) == 0) { puts("WAITING"); return 0; }
    puts("MISSING"); return 0;
}

static void set_paths_from_args(int *argc, char ***argv) {
    int out = 1;
    for (int i = 1; i < *argc; i++) {
        if (!strcmp((*argv)[i], "--socket") && i + 1 < *argc) { if (copy_checked(g_socket, sizeof(g_socket), (*argv)[++i]) < 0) exit(2); }
        else if (!strcmp((*argv)[i], "--state") && i + 1 < *argc) { if (copy_checked(g_state, sizeof(g_state), (*argv)[++i]) < 0) exit(2); }
        else (*argv)[out++] = (*argv)[i];
    }
    *argc = out;
}

int main(int argc, char **argv) {
    signal(SIGPIPE, SIG_IGN);
    set_paths_from_args(&argc, &argv);
    const char *es = getenv("KLAB_AGENT_SOCKET"), *et = getenv("KLAB_AGENT_STATE");
    if (es && *es && copy_checked(g_socket, sizeof(g_socket), es) < 0) return 2;
    if (et && *et && copy_checked(g_state, sizeof(g_state), et) < 0) return 2;
    if (argc < 2) { fprintf(stderr, "usage: klab-agent <start|daemon|ping|spawn64|status|wait|signal|output|events|barrier|barrier-run64|gate|gate-run64|gate-status|gate-release|event|shutdown|version>\n"); return 2; }
    const char *c = argv[1]; static char line[MAX_LINE];
    if (!strcmp(c, "version")) { puts(AGENT_VERSION); return 0; }
    if (!strcmp(c, "daemon")) return daemon_main();
    if (!strcmp(c, "start")) return start_daemon();
    if (!strcmp(c, "ping")) return client_line("PING", 0);
    if (!strcmp(c, "spawn64") && argc == 4) { snprintf(line, sizeof(line), "SPAWN64 %s %s", argv[2], argv[3]); return client_line(line, 0); }
    if (!strcmp(c, "status") && argc == 3) { snprintf(line, sizeof(line), "STATUS %s", argv[2]); return client_line(line, 0); }
    if (!strcmp(c, "wait") && (argc == 3 || argc == 4)) { snprintf(line, sizeof(line), "WAIT %s %s", argv[2], argc == 4 ? argv[3] : "30000"); return client_line(line, 0); }
    if (!strcmp(c, "signal") && argc == 4) { snprintf(line, sizeof(line), "SIGNAL %s %s", argv[2], argv[3]); return client_line(line, 0); }
    if (!strcmp(c, "output") && argc == 4) { snprintf(line, sizeof(line), "OUTPUT %s %s", argv[2], argv[3]); return client_line(line, 1); }
    if (!strcmp(c, "events")) return client_line("EVENTS", 1);
    if (!strcmp(c, "shutdown")) return client_line("SHUTDOWN", 0);
    if (!strcmp(c, "barrier") && (argc == 5 || argc == 6)) return barrier_cmd(argv[2], atoi(argv[3]), argv[4], argc == 6 ? atoi(argv[5]) : 30000);
    if (!strcmp(c, "barrier-run64") && argc == 7) {
        int rc = barrier_cmd(argv[2], atoi(argv[3]), argv[4], atoi(argv[5]));
        if (rc != 0) return rc;
        size_t clen = 0; unsigned char *dec = b64decode(argv[6], &clen);
        if (!dec || clen > MAX_CMD) { free(dec); return 2; }
        execl("/bin/sh", "sh", "-c", (char *)dec, (char *)NULL);
        free(dec); return 127;
    }
    if (!strcmp(c, "gate") && (argc == 4 || argc == 5)) return gate_wait_cmd(argv[2], argv[3], argc == 5 ? atoi(argv[4]) : 30000);
    if (!strcmp(c, "gate-status") && argc == 4) return gate_status_cmd(argv[2], argv[3]);
    if (!strcmp(c, "gate-release") && argc == 3) return gate_release_cmd(argv[2]);
    if (!strcmp(c, "gate-run64") && argc == 6) {
        int rc = gate_wait_cmd(argv[2], argv[3], atoi(argv[4]));
        if (rc != 0) return rc;
        size_t clen = 0; unsigned char *dec = b64decode(argv[5], &clen);
        if (!dec || clen > MAX_CMD) { free(dec); return 2; }
        execl("/bin/sh", "sh", "-c", (char *)dec, (char *)NULL);
        free(dec); return 127;
    }
    if (!strcmp(c, "event") && (argc == 3 || argc == 4)) return event_cmd(argv[2], argc == 4 ? argv[3] : "");
    fprintf(stderr, "invalid command or arguments\n"); return 2;
}
