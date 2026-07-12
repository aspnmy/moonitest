// moonitest — Docker Unix socket C FFI
// 通过 Unix socket 与 Docker daemon 通信

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

// 完整的 Docker API 请求: connect -> send -> recv -> close
// socket_path: Unix socket 路径 (null-terminated)
// req_data: HTTP 请求数据 (null-terminated)
// req_len: 请求数据长度
// resp_buf: 响应缓冲区
// resp_bufsize: 缓冲区大小
// 返回: 响应数据长度 (不含 null)，失败返回 -1
int moonbit_docker_request(const char* socket_path,
                           const char* req_data, int req_len,
                           char* resp_buf, int resp_bufsize) {
    struct sockaddr_un addr;
    int fd, n, total = 0;

    // 创建 Unix socket
    fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    // 连接
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, socket_path, sizeof(addr.sun_path) - 1);
    if (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(fd);
        return -1;
    }

    // 发送 HTTP 请求
    if (write(fd, req_data, (size_t)req_len) < 0) {
        close(fd);
        return -1;
    }

    // 读取响应
    while (total < resp_bufsize - 1) {
        n = (int)read(fd, resp_buf + total, (size_t)(resp_bufsize - total - 1));
        if (n < 0) {
            close(fd);
            return -1;
        }
        if (n == 0) break;  // 连接关闭
        total += n;
    }
    resp_buf[total] = '\0';

    close(fd);
    return total;
}
