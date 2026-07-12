# moonitest — MoonBit 集成测试框架

**在 Linux 上为你的 MoonBit 项目拉起真实的数据库容器，跑完自动销毁。**

---

## 为什么需要 moonitest

MoonBit 有 `moon test`，但它只能做纯单元测试。真实项目一定有数据库、缓存、外部 API 依赖——你不可能在生产数据库上跑测试，也不该 mock 掉一切（mock 通过的测试上线一样挂）。

moonitest 的工作方式：

```
你的 MoonBit 项目
      │
      ├── moon test（单元测试，纯逻辑）
      │
      └── moonitest（集成测试）
              │
              用 Docker 拉起真实的 PostgreSQL/Redis/MySQL
              等端口就绪 → 跑业务逻辑 → 断言结果
              测试结束 → 自动销毁容器
```

---

## 安装

```bash
moon add aspnmy/moonitest
```

## 快速开始

### 场景：测试你的 MoonBit 项目需要 PostgreSQL

```mbt
// test/integration_test.mbt
test "user repository integration" {
  // 1. 配置容器
  let pg = DockerContainer::new("postgres:16-alpine")
    .with_port(15432, 5432)
    .with_env("POSTGRES_USER", "myapp")
    .with_env("POSTGRES_PASSWORD", "secret")
    .with_env("POSTGRES_DB", "mydb")

  // 2. 启动
  match pg.start() {
    Ok(id) => {
      // 3. 等待就绪（最多等 30 秒）
      match wait_for_port("localhost", 15432, 30000) {
        Ok(_) => {
          // 4. 你的测试逻辑：连上 localhost:15432 跑业务
          println("pg ready at postgresql://myapp:secret@localhost:15432/mydb")
          // 这里调用你的 MoonBit 模块做 CRUD
        }
        Err(e) => println("pg not ready: " + e)
      }
      // 5. 自动清理
      let _ = stop(id)
    }
    Err(e) => println("start failed: " + e)
  }
}
```

### 场景：测试依赖 Redis 缓存的功能

```mbt
test "redis cache integration" {
  let port = 16379
  let r = DockerContainer::new("redis:7-alpine")
    .with_port(port, 6379)

  match r.start() {
    Ok(id) => {
      match wait_for_port("localhost", port, 15000) {
        Ok(_) => {
          println("redis ready at localhost:" + port.to_string())
          // 连上 Redis 测试你的缓存逻辑
        }
        Err(e) => println("redis timeout: " + e)
      }
      let _ = stop(id)
    }
    Err(e) => println("docker unavailable: " + e)
  }
}
```

### 场景：多容器一起上（PG + Redis）

```mbt
test "multi-container integration" {
  let pg = DockerContainer::new("postgres:16-alpine")
    .with_port(15432, 5432)
  let redis = DockerContainer::new("redis:7-alpine")
    .with_port(16379, 6379)

  let pg_id = match pg.start() {
    Ok(id) => { let _ = wait_for_port("localhost", 15432, 30000); id }
    Err(e) => { println("pg: " + e); return }
  }
  let redis_id = match redis.start() {
    Ok(id) => { let _ = wait_for_port("localhost", 16379, 15000); id }
    Err(e) => { println("redis: " + e); return }
  }

  // 两个容器都在跑了，写你的集成测试
  println("both containers ready")

  let _ = stop(pg_id)
  let _ = stop(redis_id)
}
```

---

## API 参考

### DockerContainer — 容器配置与生命周期

| 方法 | 说明 |
|------|------|
| `DockerContainer::new(image: String)` | 指定 Docker 镜像名 |
| `.with_port(host: Int, container: Int)` | 映射宿主机端口 → 容器端口 |
| `.with_env(key: String, value: String)` | 设置环境变量 |
| `.with_cmd(cmd: Array[String])` | 覆盖容器入口命令 |
| `.start() -> Result[String, String]` | 创建并启动容器，返回容器 ID |
| `stop(id: String) -> Result[Unit, String]` | 停止并删除容器 |

### 等待策略

| 函数 | 说明 |
|------|------|
| `wait_for_port(host, port, timeout_ms)` | 等待 TCP 端口开放 |
| `wait_for_http(url, timeout_ms)` | 等待 HTTP GET 返回 200 |

### HTTP 辅助

| 函数 | 说明 |
|------|------|
| `http_get(url) -> Result[String, String]` | HTTP GET，返回响应体 |
| `http_post(url, body) -> Result[String, String]` | HTTP POST |

### 网络工具

| 函数 | 说明 |
|------|------|
| `find_free_port() -> Result[Int, String]` | 找空闲端口，避免冲突 |

### 预设容器

| 函数 | 镜像 | 默认端口 | 预设 |
|------|------|---------|------|
| `postgres_container(port)` | postgres:16-alpine | 5432 | test_user / test_pass / test_db |
| `redis_container(port)` | redis:7-alpine | 6379 | 无认证 |
| `mysql_container(port)` | mysql:8.0 | 3306 | test_user / test_pass / test_db |

```mbt
// 直接用预设，不用手动配环境变量
let pg = postgres_container(15432)
let conn_str = postgres_connection_string("localhost", 15432)
// → "postgresql://test_user:test_pass@localhost:15432/test_db"
```

---

## 集成到 MoonBit 项目的工作流

### 标准目录结构

```
your-moonbit-project/
├── moon.mod                    # 你的项目
├── moon.pkg
├── src/
│   └── lib.mbt                 # 你的业务代码
├── test/
│   └── integration_test.mbt    # 集成测试（用 moonitest）
└── README.md
```

### 添加依赖

```bash
moon add aspnmy/moonitest
```

### 编写集成测试

在 `test/` 目录下创建 `*_test.mbt` 文件：

```mbt
// test/user_repo_test.mbt
test "user repository with real postgres" {
  let port = 15432
  let pg = DockerContainer::new("postgres:16-alpine")
    .with_port(port, 5432)
    .with_env("POSTGRES_USER", "test")
    .with_env("POSTGRES_DB", "testdb")

  match pg.start() {
    Ok(id) => {
      match wait_for_port("localhost", port, 30000) {
        Ok(_) => {
          // 这里调用你的 repo 层
          // let repo = UserRepo::new("localhost", port)
          // let user = repo.create("alice@example.com")
          // assert_eq(user.email, "alice@example.com")
        }
        Err(e) => println("timeout: " + e)
      }
      let _ = stop(id)
    }
    Err(e) => println("no docker: " + e)
  }
}
```

### 运行

```bash
# 1. 类型检查
moon check

# 2. 构建 native 目标
moon build --target native

# 3. 跑全部测试（单元 + 集成）
moon test

# 4. 单独跑某个集成测试
moon test -- --name "postgres"
```

---

## 调试技巧

### 1. 容器没起来？查 Docker 日志

```mbt
// 先把 stop 注释掉，容器留着手动排查
test "debug postgres" {
  let pg = postgres_container(15432)
  match pg.start() {
    Ok(id) => {
      println("container: " + id)
      println("docker logs " + id)
      // 在另一个终端: docker logs -f <id>
    }
    Err(e) => println("error: " + e)
  }
  // 不要 stop，跑完手动 inspect
}
```

### 2. 端口冲突

```mbt
// 用 find_free_port 替代硬编码端口
let port = match find_free_port() {
  Ok(p) => p
  Err(_) => 15432  // fallback
}
```

### 3. 超时处理

数据库首次启动可能较慢，根据镜像大小调整超时：

| 镜像 | 建议超时 |
|------|---------|
| redis:7-alpine | 15 秒 |
| postgres:16-alpine | 30 秒 |
| mysql:8.0 | 60 秒（首次拉取更久） |

### 4. CI 中无 Docker 环境

所有函数在 Docker 不可用时会返回 `Err`，不会 panic。测试代码应优雅降级：

```mbt
match pg.start() {
  Ok(id) => { /* 集成测试 */ }
  Err(e) => println("skip integration test: " + e)
  // 测试仍然通过，只是跳过了 Docker 依赖的部分
}
```

---

## 当前版本已知限制 (v0.1.5)

| 限制 | 说明 | 计划修复版本 |
|------|------|:----------:|
| `start()` / `stop()` 返回 `Err` | 等待 native FFI（C popen + curl）接入 | v0.2.0 |
| `wait_for_port()` 返回 `Err` | 等待 C socket FFI 接入 | v0.2.0 |
| `find_free_port()` 返回 `Err` | 等待 C socket FFI 接入 | v0.2.0 |
| `http_get()` / `http_post()` 返回 `Err` | 等待 C socket FFI 接入 | v0.2.0 |
| `test` 块中无法调用 `now_ms()` | 时间函数需 FFI | v0.2.0 |
| 仅 Linux native 目标 | 不支持 WASM/JS | v0.1.x |
| 测试发现机制 | 当前 moon test 可能不识别 `test/` 目录下的测试 | 跟进 moon 版本 |

### 当前可用的 API（纯 MoonBit 层，无需 FFI）

- `DockerContainer::new()` / `.with_port()` / `.with_env()` / `.with_cmd()`
- `postgres_container()` / `redis_container()` / `mysql_container()`
- `postgres_connection_string()` / `redis_address()` / `mysql_connection_string()`

这些纯类型操作可以正常编译，在 v0.2.0 接入 FFI 后，`start()` / `stop()` / `wait_for_port()` / `http_get()` / `http_post()` / `find_free_port()` 才会真正执行。

### v0.1.6 变更日志

| 变更 | 说明 |
|------|------|
| 🐳 Docker 交叉编译示例 | README 新增 3 种容器编译方式：快速命令/专用镜像/Gitea Runner CI |
| 🚀 发布至 mooncakes.io | v0.1.6 已通过 `moon publish` 发布 |

### v0.1.5 变更日志

| 变更 | 说明 |
|------|------|
| 🧪 17 个测试用例 | 覆盖 94% 公开 API：stub/Builder/预设/连接字符串 |
| 🏗️ 添加 public accessor | `image()` / `ports()` / `envs()` / `cmd()` 供外部验证 |
| 🐛 修复 `panic()` 用法 | MoonBit 不支持 `panic("msg")`，改为 `println(msg); panic()` |

### v0.1.4 变更日志

| 变更 | 说明 |
|------|------|
| 🚀 发布至 mooncakes.io | v0.1.4 已通过 `moon publish` 发布到 mooncakes.io |
| 🧹 清理重复文件 | 删除 `src/containers/` 目录下与 `src/` 重复的 3 个文件，修复编译失败问题 |
| 🧹 删除重复测试 | 删除 `src/moonitest_test.mbt`，保留 `test/moonitest_test.mbt` |
| 📝 还原 `moon.pkg` | `moon.pkg` 不支持 TOML 格式，还原为空文件 |
| 🎨 统一错误信息 | 所有 stub 函数错误信息统一为 `"not yet implemented (moonitest requires C socket FFI — planned for v0.2.0)"` |

---

## 在 MoonBit 项目中使用 moonitest 的完整示例

待补充 `examples/` 目录（计划 v0.2.0 随 FFI 集成一并提供）：

---

## Docker 容器编译（替代本地 C 编译器）

MoonBit 的 `native` 目标需要 C 编译器链接 `.exe`。如果本地没有 C 编译器，可以用 Docker 容器完成编译。

### 快速编译（一条命令）

```bash
docker run --rm -v $(pwd):/build -w /build \
  debian:bullseye-slim sh -c "
    apt update -qq && apt install -y -qq curl gcc > /dev/null 2>&1 && \
    curl -fsSL https://cli.moonbitlang.com/install.sh | bash > /dev/null 2>&1 && \
    export PATH=\$HOME/.moon/bin:\$PATH && \
    moon check && moon build --target native && moon test
  "
```

### 专用编译镜像（推荐，复用缓存）

创建 `moonitest-builder.Dockerfile`：

```dockerfile
FROM debian:bullseye-slim
RUN apt update -qq && apt install -y -qq curl gcc && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /root/.moon/bin && \
    curl -fsSL https://cli.moonbitlang.com/install.sh | bash
ENV PATH="/root/.moon/bin:${PATH}"
WORKDIR /build
```

构建并编译：

```bash
docker build -t moonitest-builder -f moonitest-builder.Dockerfile .
docker run --rm -v $(pwd):/build moonitest-builder \
  sh -c "moon check && moon build --target native && moon test"
```

### 使用 Gitea Runner CI 镜像

如果已有 Gitea Act Runner 基础设施，也可直接使用预置的 CI 镜像：

```bash
docker run --rm -v $(pwd):/build:/build \
  10.168.3.123:30002/aspnmy/act-runner-ci:baseimage-v3.2.3.0-runner-v4 \
  sh -c "cd /build && moon check && moon build --target native && moon test"
```

该镜像内置 gcc、Docker CLI、QEMU 多架构支持、MinGW 交叉编译器—详见 [`gitea-runner`](https://git.t2be.cn/aspnmy/gitea-runner)。

---

## 依赖

| 依赖 | 说明 | 版本要求 |
|------|------|---------|
| Docker | 容器运行时 | 20+ |
| curl | 通过 Unix socket 调用 Docker API | 7.80+ |
| Linux | Unix socket 和 native 目标支持 | x86_64 / aarch64 |

## 构建

```bash
moon check
moon build --target native
moon test
```

## 许可

Apache-2.0
