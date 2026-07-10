// moonitest native FFI — 为 MoonBit 提供系统级能力
// 编译：与 MoonBit native 目标链接
// gcc -c moonitest_ffi.c -o moonitest_ffi.o

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <time.h>

// exec_sh: 执行 shell 命令，输出写入 buf
int64_t moonitest_exec_sh(const char* cmd, char* buf, int64_t buf_size) {
    FILE* fp = popen(cmd, "r");
    if (!fp) {
        if (buf_size > 0) buf[0] = '\0';
        return 1;
    }
    size_t n = fread(buf, 1, (size_t)(buf_size - 1), fp);
    buf[n] = '\0';
    int ret = pclose(fp);
    return (int64_t)(ret == 0 ? 0 : 1);
}

// try_connect: 尝试 TCP 连接
int64_t moonitest_try_connect(const char* host, int64_t port) {
    struct addrinfo hints, *res;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    
    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%ld", (long)port);
    
    if (getaddrinfo(host, port_str, &hints, &res) != 0)
        return 0;
    
    int sock = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (sock < 0) {
        freeaddrinfo(res);
        return 0;
    }
    
    struct timeval tv = { .tv_sec = 2, .tv_usec = 0 };
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    
    int ok = (connect(sock, res->ai_addr, res->ai_addrlen) == 0) ? 1 : 0;
    close(sock);
    freeaddrinfo(res);
    return (int64_t)ok;
}

// now_ms: 当前毫秒时间戳
int64_t moonitest_now_ms() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (int64_t)tv.tv_sec * 1000 + (int64_t)(tv.tv_usec / 1000);
}

// sleep_ms: 休眠指定毫秒
void moonitest_sleep_ms(int64_t ms) {
    struct timespec ts = {
        .tv_sec = (time_t)(ms / 1000),
        .tv_nsec = (long)((ms % 1000) * 1000000)
    };
    nanosleep(&ts, NULL);
}
