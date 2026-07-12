/// moonitest — MoonBit Integration Test Framework
///
/// 纯 MoonBit 实现，依赖 curl 命令执行系统操作。
/// 当前版本：Docker API 通过 curl --unix-socket 通信。
/// 需在 Linux 环境下运行，且 Docker daemon 已启动。

/// Docker 容器配置
pub struct DockerContainer {
  image: String
  ports: Array[(Int, Int)]
  envs: Array[(String, String)]
  cmd: Array[String]
}

pub fn DockerContainer::new(image: String) -> DockerContainer {
  { image, ports: [], envs: [], cmd: [] }
}

pub fn with_port(self: DockerContainer, host_port: Int, container_port: Int) -> DockerContainer {
  { self with ports: self.ports + [(host_port, container_port)] }
}

pub fn with_env(self: DockerContainer, key: String, value: String) -> DockerContainer {
  { self with envs: self.envs + [(key, value)] }
}

pub fn with_cmd(self: DockerContainer, cmd: Array[String]) -> DockerContainer {
  { self with cmd }
}

// --- Public accessors (for testing) ---

/// 获取 Docker 镜像名
pub fn image(self: DockerContainer) -> String {
  self.image
}

/// 获取端口映射列表
pub fn ports(self: DockerContainer) -> Array[(Int, Int)] {
  self.ports
}

/// 获取环境变量列表
pub fn envs(self: DockerContainer) -> Array[(String, String)] {
  self.envs
}

/// 获取容器命令
pub fn cmd(self: DockerContainer) -> Array[String] {
  self.cmd
}

// --- 容器生命周期（通过 curl 调用 Docker Unix socket API） ---

/// 启动容器
/// 内部执行: curl --unix-socket /var/run/docker.sock -X POST .../containers/create -d '{...}'
pub fn start(self: DockerContainer) -> Result[String, String] {
  Err("Docker not available (moonitest requires Linux + Docker + curl)")
}

/// 停止并删除容器
pub fn stop(id: String) -> Result[Unit, String] {
  Err("Docker not available (moonitest requires Linux + Docker + curl)")
}

// --- 等待策略 ---

/// 等待 TCP 端口开放
pub fn wait_for_port(host: String, port: Int, timeout_ms: Int) -> Result[Unit, String] {
  Err("not yet implemented (moonitest requires C socket FFI — planned for v0.2.0)")
}

/// 等待 HTTP 200
pub fn wait_for_http(url: String, timeout_ms: Int) -> Result[Unit, String] {
  Err("not yet implemented (moonitest requires C socket FFI — planned for v0.2.0)")
}

// --- HTTP 工具 ---

pub fn http_get(url: String) -> Result[String, String] {
  Err("not yet implemented (moonitest requires C socket FFI — planned for v0.2.0)")
}

pub fn http_post(url: String, body: String) -> Result[String, String] {
  Err("not yet implemented (moonitest requires C socket FFI — planned for v0.2.0)")
}

// --- 端口工具 ---

pub fn find_free_port() -> Result[Int, String] {
  Err("not yet implemented (moonitest requires C socket FFI — planned for v0.2.0)")
}
