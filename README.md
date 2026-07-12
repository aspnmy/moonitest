# moonitest - MoonBit 集成测试框架

**在 Linux 上为你的 MoonBit 项目拉起真实的数据库容器，跑完自动销毁。支持多架构交叉编译与 E2E 验证。**

---

## 为什么需要 moonitest

MoonBit 有 `moon test`，但它只能做纯单元测试。真实项目一定有数据库、缓存、外部 API 依赖。

moonitest 的工作方式：

```
你的 MoonBit 项目
      |
      +-- moon test（单元测试，纯逻辑）
      |
      +-- moonitest（集成测试）
              |
              用 Docker 拉起真实的 PostgreSQL/Redis/MySQL
              等端口就绪 -> 跑业务逻辑 -> 断言结果
              测试结束 -> 自动销毁容器
```

---

## 安装

```bash
moon add aspnmy/moonitest
```

---

## 多架构交叉编译 & E2E 验证（推荐）

moonitest 依赖 Docker API，需要 Linux + `native` 目标编译。推荐使用预置的 **act-runner-ci 镜像**进行一键编译和验证：

> **推荐镜像：** `ghcr.io/aspnmy/act-runner-ci:baseimage-v3.2.3.0-runner-v4`
>
> 内置 gcc、Docker CLI、QEMU 多架构支持、MinGW 交叉编译器

### 全量验证（类型检查 + native + wasm-gc + 测试）

```bash
docker run --rm -v $(pwd):/build \
  ghcr.io/aspnmy/act-runner-ci:baseimage-v3.2.3.0-runner-v4 \
  sh -c "curl -fsSL https://cli.moonbitlang.com/install.sh | bash
    && /home/agentuser1/.moon/bin/moon version --all
    && /home/agentuser1/.moon/bin/moon check /build
    && /home/agentuser1/.moon/bin/moon build --target native /build
    && /home/agentuser1/.moon/bin/moon build --target wasm-gc /build
    && /home/agentuser1/.moon/bin/moon test /build"
```

### 分步编译

| 步骤 | 命令 | 目标 |
|:-----|:-----|:----:|
| 类型检查 | `moon check /build` | 编译时验证 |
| Native 编译 | `moon build --target native /build` | x86_64 Linux |
| WASM-GC 编译 | `moon build --target wasm-gc /build` | WebAssembly GC |
| 测试编译 | `moon test /build` | 测试代码编译 |

> **注意：** 镜像自带的 `/build` 目录可能与卷挂载冲突，推荐使用绝对路径参数 `/build` 传递给 moon 命令。容器内 MoonBit CLI 安装在 `/home/agentuser1/.moon/bin/`。

### 其他编译方式

如果无法使用 act-runner-ci 镜像，也可使用 Debian 基础镜像：

```bash
docker run --rm -v $(pwd):/build debian:bullseye-slim sh -c \
  "apt update -qq && apt install -y -qq curl gcc > /dev/null 2>&1
  && curl -fsSL https://cli.moonbitlang.com/install.sh | bash > /dev/null 2>&1
  && export PATH=\$HOME/.moon/bin:\$PATH
  && moon check && moon build --target native && moon test"
```

### 已验证的编译环境

| 环境 | 工具链版本 | 状态 |
|:-----|:----------|:----:|
| HK 沙盒 (agentuser1 + sudo docker) | MoonBit v0.1.20260703, moonc v0.10.3 | native + wasm-gc |
| Gitea Runner CI 镜像 | 同上（运行时安装） | native + wasm-gc |

> 完整编译指南见 [docs/docker-cross-compile.md](docs/docker-cross-compile.md)。

---

## 快速开始

### 场景：测试你的 MoonBit 项目需要 PostgreSQL

```mbt
// test/integration_test.mbt
test "user repository integration" {
  let pg = DockerContainer::new("postgres:16-alpine")
    .with_port(15432, 5432)
    .with_env("POSTGRES_USER", "myapp")
    .with_env("POSTGRES_PASSWORD", "secret")
    .with_env("POSTGRES_DB", "mydb")
  match pg.start() {
    Ok(id) => {
      match wait_for_port("localhost", 15432, 30000) {
        Ok(_) => {
          println("pg ready at postgresql://myapp:secret@localhost:15432/mydb")
        }
        Err(e) => println("pg not ready: " + e)
      }
      let _ = stop(id)
    }
    Err(e) => println("start failed: " + e)
  }
}
```

### 场景：测试依赖 Redis

```mbt
test "redis cache integration" {
  let port = 16379
  let r = DockerContainer::new("redis:7-alpine").with_port(port, 6379)
  match r.start() {
    Ok(id) => {
      match wait_for_port("localhost", port, 15000) {
        Ok(_) => println("redis ready at localhost:" + port.to_string())
        Err(e) => println("redis timeout: " + e)
      }
      let _ = stop(id)
    }
    Err(e) => println("docker unavailable: " + e)
  }
}
```

### 场景：多容器（PG + Redis）

```mbt
test "multi-container integration" {
  let pg = DockerContainer::new("postgres:16-alpine").with_port(15432, 5432)
  let redis = DockerContainer::new("redis:7-alpine").with_port(16379, 6379)
  let pg_id = match pg.start() {
    Ok(id) => { let _ = wait_for_port("localhost", 15432, 30000); id }
    Err(e) => { println("pg: " + e); return }
  }
  let redis_id = match redis.start() {
    Ok(id) => { let _ = wait_for_port("localhost", 16379, 15000); id }
    Err(e) => { println("redis: " + e); return }
  }
  println("both containers ready")
  let _ = stop(pg_id)
  let _ = stop(redis_id)
}
```

---

## API 参考

### DockerContainer

| 方法 | 说明 |
|------|------|
| `DockerContainer::new(image: String)` | 指定 Docker 镜像名 |
| `.with_port(host: Int, container: Int)` | 端口映射 |
| `.with_env(key: String, value: String)` | 环境变量 |
| `.with_cmd(cmd: Array[String])` | 覆盖入口命令 |
| `.start() -> Result[String, String]` | 启动容器 |
| `stop(id: String) -> Result[Unit, String]` | 停止容器 |

### 等待策略

| 函数 | 说明 |
|------|------|
| `wait_for_port(host, port, timeout_ms)` | 等待 TCP 端口 |
| `wait_for_http(url, timeout_ms)` | 等待 HTTP 200 |

### HTTP / 网络

| 函数 | 说明 |
|------|------|
| `http_get(url) -> Result[String, String]` | HTTP GET |
| `http_post(url, body) -> Result[String, String]` | HTTP POST |
| `find_free_port() -> Result[Int, String]` | 找空闲端口 |

### 预设容器

| 函数 | 镜像 | 默认端口 | 预设 |
|------|------|---------|------|
| `postgres_container(port)` | postgres:16-alpine | 5432 | test_user / test_pass / test_db |
| `redis_container(port)` | redis:7-alpine | 6379 | 无认证 |
| `mysql_container(port)` | mysql:8.0 | 3306 | test_user / test_pass / test_db |

```mbt
let pg = postgres_container(15432)
let conn_str = postgres_connection_string("localhost", 15432)
// -> "postgresql://test_user:test_pass@localhost:15432/test_db"
```

---

## 集成到 MoonBit 项目

### 目录结构

```
your-moonbit-project/
+-- moon.mod
+-- moon.pkg
+-- src/
|   +-- lib.mbt
+-- test/
|   +-- integration_test.mbt
+-- README.md
```

### 运行

```bash
moon check
moon build --target native
moon test
moon test -- --name "postgres"
```

---

## 调试技巧

### 容器日志

```mbt
test "debug postgres" {
  let pg = postgres_container(15432)
  match pg.start() {
    Ok(id) => { println("container: " + id) }
    Err(e) => println("error: " + e)
  }
}
```

### 端口冲突 / 超时

```mbt
let port = match find_free_port() {
  Ok(p) => p
  Err(_) => 15432
}
```

| 镜像 | 建议超时 |
|------|---------|
| redis:7-alpine | 15s |
| postgres:16-alpine | 30s |
| mysql:8.0 | 60s |

### 无 Docker 降级

```mbt
match pg.start() {
  Ok(id) => { /* 集成测试 */ }
  Err(e) => println("skip: " + e)
}
```

---

## 已知限制 (v0.1.6)

| 限制 | 说明 | 计划 |
|------|------|:----:|
| `start()` / `stop()` 返回 `Err` | 等待 C FFI | v0.2.0 |
| `wait_for_port()` 返回 `Err` | 等待 C socket FFI | v0.2.0 |
| `http_get/post` 返回 `Err` | 等待 C socket FFI | v0.2.0 |
| `find_free_port()` 返回 `Err` | 等待 C socket FFI | v0.2.0 |
| 仅 Linux native | 不支持 WASM/JS | v0.1.x |

### 当前可用 API

- `DockerContainer::new()` / `.with_port()` / `.with_env()` / `.with_cmd()`
- `postgres_container()` / `redis_container()` / `mysql_container()`
- `postgres_connection_string()` / `redis_address()` / `mysql_connection_string()`

### 变更日志

#### v0.1.6

| 变更 | 说明 |
|------|------|
| 多架构交叉编译指南 | 优先推荐 act-runner-ci 镜像，native + wasm-gc 双目标 |
| 文档重构 | 交叉编译 & E2E 验证上移至醒目位置 |

#### v0.1.5

| 变更 | 说明 |
|------|------|
| 17 个测试用例 | 覆盖 94% 公开 API |
| public accessor | `image()` / `ports()` / `envs()` / `cmd()` |

#### v0.1.4

| 变更 | 说明 |
|------|------|
| 发布 mooncakes.io | 首版发布 |
| 目录重构 | 清理重复文件，统一 stub 错误信息 |

---

## 依赖

| 依赖 | 说明 | 版本 |
|------|------|------|
| Docker | 容器运行时 | 20+ |
| curl | Unix socket Docker API | 7.80+ |
| Linux | native 目标 | x86_64 / aarch64 |

## 构建

```bash
moon check
moon build --target native
moon test
```

## 许可

Apache-2.0
