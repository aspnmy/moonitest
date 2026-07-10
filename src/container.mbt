/// moonitest — MoonBit Integration Test Framework
///
/// 纯 MoonBit 实现，通过 Docker Unix socket 管理测试容器。
/// 仅 Linux native 目标，依赖 curl 命令作为系统桥接。

/// Docker 容器配置
pub struct DockerContainer {
  image: String
  ports: Array[(Int, Int)]
  envs: Array[(String, String)]
  cmd: Array[String]
  id: String
}

pub fn DockerContainer::new(image: String) -> DockerContainer {
  { image, ports: [], envs: [], cmd: [], id: "" }
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

/// 启动容器 → 返回容器 ID
pub fn start(self: DockerContainer) -> Result[String, String] {
  let body = build_json(self)
  let resp = sh("curl -s --unix-socket /var/run/docker.sock -X POST http://localhost/v1.45/containers/create -d " + q(body))?
  let id = parse_id(resp)?
  let _ = sh("curl -s --unix-socket /var/run/docker.sock -X POST http://localhost/v1.45/containers/" + id + "/start")?
  Ok(id)
}

/// 停止并删除容器
pub fn stop(id: String) -> Result[Unit, String] {
  let _ = sh("curl -s --unix-socket /var/run/docker.sock -X POST http://localhost/v1.45/containers/" + id + "/stop?t=5")?
  let _ = sh("curl -s --unix-socket /var/run/docker.sock -X DELETE http://localhost/v1.45/containers/" + id + "?force=true")?
  Ok(())
}

/// 等待端口开放（通过 bash /dev/tcp）
pub fn wait_for_port(host: String, port: Int, timeout_ms: Int) -> Result[Unit, String] {
  let deadline = now_ms() + timeout_ms
  loop {
    if try_connect(host, port) { return Ok(()) }
    if now_ms() > deadline { return Err("timeout: " + host + ":" + port.to_string()) }
    sleep(200)
  }
}

/// 等待 HTTP 200
pub fn wait_for_http(url: String, timeout_ms: Int) -> Result[Unit, String] {
  let deadline = now_ms() + timeout_ms
  loop {
    let resp = http_get(url)
    if resp.is_ok() { return Ok(()) }
    if now_ms() > deadline { return Err("timeout: " + url) }
    sleep(500)
  }
}

/// HTTP GET
pub fn http_get(url: String) -> Result[String, String] {
  sh("curl -s --max-time 5 " + q(url))
}

/// HTTP POST
pub fn http_post(url: String, body: String) -> Result[String, String] {
  sh("curl -s --max-time 5 -X POST -d " + q(body) + " " + q(url))
}

/// 查找空闲端口
pub fn find_free_port() -> Result[Int, String] {
  let out = sh("python3 -c \"import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()\"")?
  out.trim().to_int()
}

// --- FFI: shell 执行 ---

fn sh(cmd: String) -> Result[String, String] {
  let buf = Bytes::make(65536)
  let code = exec_sh(cmd, buf)
  let out = buf.to_string().trim()
  if code == 0 { Ok(out) } else { Err(out) }
}

fn exec_sh(cmd: String, out: Bytes) -> Int {
  // 通过 C FFI 调用 popen
  // 由 build.rs / moon.pkg.json link 提供 native 实现
  _exec_sh(cmd, out)
}

fn _exec_sh(cmd: String, out: Bytes) = "moonitest" "exec_sh"

// --- FFI: TCP 连接检测 ---

fn try_connect(host: String, port: Int) -> Bool {
  _try_connect(host, port)
}

fn _try_connect(host: String, port: Int) = "moonitest" "try_connect"

// --- FFI: 系统时间与睡眠 ---

fn now_ms() -> Int {
  _now_ms()
}

fn _now_ms() = "moonitest" "now_ms"

fn sleep(ms: Int) {
  _sleep(ms)
}

fn _sleep(ms: Int) = "moonitest" "sleep_ms"

// --- JSON 构建与解析 ---

fn build_json(cfg: DockerContainer) -> String {
  let pairs = cfg.ports.map(fn(p) {
    let (h, c) = p
    "\"" + c.to_string() + "/tcp\":{\"HostPort\":\"" + h.to_string() + "\"}"
  })
  let exposed = cfg.ports.map(fn(p) {
    let (_, c) = p
    "\"" + c.to_string() + "/tcp\":{}"
  })
  let envs = cfg.envs.map(fn(e) {
    let (k, v) = e
    "\"" + k + "=" + v + "\""
  })
  let cmds = cfg.cmd.map(fn(c) { "\"" + c + "\"" })

  "{"
  + "\"Image\":\"" + cfg.image + "\","
  + "\"HostConfig\":{\"PortBindings\":{" + pairs.join(",") + "}},"
  + "\"ExposedPorts\":{" + exposed.join(",") + "},"
  + "\"Env\":[" + envs.join(",") + "],"
  + "\"Cmd\":[" + cmds.join(",") + "]"
  + "}"
}

fn parse_id(resp: String) -> Result[String, String] {
  let parts = resp.split("\"Id\":\"")
  if parts.length() < 2 { return Err("no id: " + resp) }
  Ok(parts[1].split("\"")[0])
}

fn q(s: String) -> String {
  "'" + s.replace("'", "'\\''") + "'"
}
