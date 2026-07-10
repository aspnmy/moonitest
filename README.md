# moonitest — MoonBit Integration Test Framework

纯 MoonBit 实现，零外部依赖（除 Docker + curl 运行时）。

通过 C FFI 调用 Linux 系统 API（TCP 连接、进程执行、时间），
无需 Python、Node.js 等外部运行时。

## 安装

```bash
moon add moonitest/moonitest
```

## 快速使用

```mbt
// 启动 PostgreSQL 测试容器
let pg = DockerContainer::new("postgres:16-alpine")
  .with_port(15432, 5432)
  .with_env("POSTGRES_USER", "test")

match pg.start() {
  Ok(id) => {
    let _ = wait_for_port("localhost", 15432, 30000)
    // ... run tests against localhost:15432 ...
    let _ = stop(id)
  }
  Err(e) => println("docker unavailable: " + e)
}
```

## API

| 函数 | 说明 |
|------|------|
| `DockerContainer::new(image)` | 创建容器配置 |
| `.with_port(host, container)` | 端口映射 |
| `.with_env(key, value)` | 环境变量 |
| `.start()` / `stop(id)` | 容器启停 |
| `wait_for_port(host, port, ms)` | TCP 端口等待 |
| `wait_for_http(url, ms)` | HTTP 健康检查 |
| `find_free_port()` | 找空闲端口 |
| `http_get(url)` / `http_post(url, body)` | HTTP 辅助 |

## 构建

```bash
moon check
moon build --target native
moon test
```

## 架构

```
MoonBit .mbt         ← 纯类型编排
    ↓
C FFI (native)       ← 系统调用层
  ├── popen()        → shell 命令执行
  ├── socket()       → TCP 端口检测
  ├── gettimeofday() → 毫秒时间戳
  └── nanosleep()    → 精确休眠
    ↓
curl                 → Docker Unix socket API + HTTP
```

## 依赖

- Linux x86_64 / aarch64
- Docker daemon (监听 /var/run/docker.sock)
- curl（Docker API 通信）
- GCC（编译 C FFI，通常系统自带）

## 许可

Apache-2.0
