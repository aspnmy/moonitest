# moonitest — MoonBit Integration Test Framework

MoonBit 集成测试框架 —— 通过 Docker 容器编排自动化集成测试。

> **v0.1.0** · 仅 Linux native 目标 · 需 Docker daemon

## 安装

```bash
moon add moonitest/moonitest
```

## 快速开始

```mbt
// 启动 PostgreSQL 测试容器
let port = 15432
let pg = postgres_container(port)

match pg.start() {
  Ok(id) => {
    let _ = wait_for_port("localhost", port, 30000)
    println("Connection: " + postgres_connection_string("localhost", port))
    // ... 运行测试逻辑 ...
    let _ = stop(id)
  }
  Err(e) => println("Docker not available: " + e)
}
```

## API

### DockerContainer

| 方法 | 说明 |
|------|------|
| `DockerContainer::new(image)` | 创建容器配置 |
| `.with_port(host, container)` | 端口映射 |
| `.with_env(key, value)` | 环境变量 |
| `.with_cmd(cmd)` | 启动命令 |
| `.start()` | 启动容器 |
| `stop(id)` | 停止并删除容器 |

### 预置容器

| 函数 | 镜像 | 预设 |
|------|------|------|
| `postgres_container(port)` | postgres:16-alpine | test_user/test_pass/test_db |
| `redis_container(port)` | redis:7-alpine | 无认证 |
| `mysql_container(port)` | mysql:8.0 | test_user/test_pass/test_db |

### 等待策略

| 函数 | 说明 |
|------|------|
| `wait_for_port(host, port, timeout_ms)` | 等待端口开放 |
| `wait_for_http(url, timeout_ms)` | 等待 HTTP 200 |

### 网络工具

| 函数 | 说明 |
|------|------|
| `find_free_port()` | 查找可用端口 |
| `http_get(url)` | HTTP GET 请求 |
| `http_post(url, body)` | HTTP POST 请求 |

## 构建

```bash
# 类型检查
moon check

# 构建（native 目标）
moon build --target native

# 运行测试
moon test
```

## 依赖

- Docker daemon（`/var/run/docker.sock`）
- `curl` 命令（用于 HTTP 请求和 Unix socket 通信）
- Linux 系统

## 许可

Apache-2.0
