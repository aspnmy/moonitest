# Docker 容器内多目标交叉编译

> moonitest 框架自身在 HK 沙盒上使用 Gitea Runner CI 镜像完成 native + wasm-gc 双目标编译验证。

---

## 环境

| 项目 | 值 |
|:-----|:----|
| 沙盒 | HK `` |
| 用户 | `agentuser1`（已授权 `sudo docker` 免密） |
| 代码路径 | `/home/agentuser1/moonitest` |
| 镜像 | `ghcr.io/aspnmy/act-runner-ci:baseimage-v3.2.3.0-runner-v4` |
| 容器入口 | `--entrypoint /bin/bash`（s6-overlay 镜像需绕过 `/init`） |

## 前置条件

### 1. 修复 CRLF 换行符

从 Windows/git clone 的 `moon.mod` 可能携带 CRLF 换行符，MoonBit 编译器无法识别：

```bash
perl -pi -e 's/\r//g' /home/agentuser1/moonitest/moon.mod
```

### 2. 确认代码存在

```bash
ls -la /home/agentuser1/moonitest/
# 应包含: .git LICENSE README.md moon.mod moon.pkg src/
```

## 编译命令

### 全量构建（类型检查 + native + wasm-gc + 测试）

```bash
sudo docker run --rm --entrypoint /bin/bash \
  -v /home/agentuser1/moonitest:/build \
  git.t2be.cn/aspnmy/gitea-runner:baseimage-v3.2.3.0-runner-v4 \
  -c "
curl -fsSL https://cli.moonbitlang.com/install.sh | bash \
  && /home/agentuser1/.moon/bin/moon version --all \
  && /home/agentuser1/.moon/bin/moon check /build \
  && /home/agentuser1/.moon/bin/moon build --target native /build \
  && /home/agentuser1/.moon/bin/moon build --target wasm-gc /build \
  && /home/agentuser1/.moon/bin/moon test /build
"
```

### 分步构建

```bash
# 类型检查
sudo docker run --rm --entrypoint /bin/bash \
  -v /home/agentuser1/moonitest:/build \
  git.t2be.cn/aspnmy/gitea-runner:baseimage-v3.2.3.0-runner-v4 \
  -c "curl -fsSL https://cli.moonbitlang.com/install.sh | bash \
    && /home/agentuser1/.moon/bin/moon check /build"

# Native 编译
sudo docker run --rm --entrypoint /bin/bash \
  -v /home/agentuser1/moonitest:/build \
  git.t2be.cn/aspnmy/gitea-runner:baseimage-v3.2.3.0-runner-v4 \
  -c "curl -fsSL https://cli.moonbitlang.com/install.sh | bash \
    && /home/agentuser1/.moon/bin/moon build --target native /build"

# WASM-GC 编译
sudo docker run --rm --entrypoint /bin/bash \
  -v /home/agentuser1/moonitest:/build \
  git.t2be.cn/aspnmy/gitea-runner:baseimage-v3.2.3.0-runner-v4 \
  -c "curl -fsSL https://cli.moonbitlang.com/install.sh | bash \
    && /home/agentuser1/.moon/bin/moon build --target wasm-gc /build"

# 测试编译验证
sudo docker run --rm --entrypoint /bin/bash \
  -v /home/agentuser1/moonitest:/build \
  git.t2be.cn/aspnmy/gitea-runner:baseimage-v3.2.3.0-runner-v4 \
  -c "curl -fsSL https://cli.moonbitlang.com/install.sh | bash \
    && /home/agentuser1/.moon/bin/moon test /build"
```

## 编译结果

| 步骤 | 命令 | 状态 | 说明 |
|:-----|:-----|:----:|:-----|
| 类型检查 | `moon check` | ✅ | 0 errors |
| Native 编译 | `moon build --target native` | ✅ | x86_64 Linux native |
| WASM-GC 编译 | `moon build --target wasm-gc` | ✅ | WebAssembly GC 目标 |
| 测试编译 | `moon test` | ✅ | 测试代码编译通过（不执行——测试运行时未自举） |

## Docker 卷挂载说明

Gitea Runner CI 镜像内部存在 `/build` 目录（s6-overlay 遗留），`-v` 卷挂载的宿主机目录可能与容器内 `/build` 冲突。解决方法：

- **✅ 推荐：** 使用绝对路径作为项目参数传递给 `moon`，如 `moon build --target native /build`
- **⚠️ 不推荐：** `cd /build && moon build`（当卷挂载因目录冲突失效时，`cd` 会进入镜像自带的 `/build` 目录而非宿主机代码目录）

容器内 MoonBit CLI 安装在 `/home/agentuser1/.moon/bin/`（基于容器的 `$HOME`）。

## 工具链版本

```
moon   0.1.20260703 (6fbf8c3 2026-07-03)
moonc  v0.10.3+16975d007 (2026-07-03)
moonrun 0.1.20260703 (6fbf8c3 2026-07-03)

Feature flags: rr_moon_mod, rr_moon_pkg
```

## 已知限制

| 限制 | 说明 |
|:-----|:------|
| 测试运行时未自举 | `moon test` 编译测试代码但不会执行测试用例 |
| CRLF 换行符 | 从 Windows git clone 后需要修复 `moon.mod` 换行符 |
| `/build` 目录冲突 | Gitea Runner CI 镜像自带 `/build` 目录，卷挂载可能不生效 |
| `&&` / `;` 分割 | Windows cmd.exe 中通过 ssh-client 远程执行时，`&&` 和 `;` 会被 cmd.exe 解释为命令分隔符，需使用单个 `-c` 参数内的完整链 |
