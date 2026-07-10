/// MoonBit Integration Test Framework — 容器生命周期管理
///
/// 通过 Docker Unix socket (/var/run/docker.sock) 管理测试容器。
/// 仅支持 Linux native 目标。

/// Docker 容器配置
pub struct DockerContainer {
  image: String
  container_name: String
  ports: Array[(Int, Int)]  // (host_port, container_port)
  envs: Array[(String, String)]
  cmd: Array[String]
  id: String  // 启动后赋值
}

/// 创建容器配置
pub fn DockerContainer::new(image: String) -> DockerContainer {
  DockerContainer::new_with_opts(image, "", [], [], [])
}

/// 带选项创建
pub fn DockerContainer::new_with_opts(
  image: String,
  container_name: String,
  ports: Array[(Int, Int)],
  envs: Array[(String, String)],
  cmd: Array[String],
) -> DockerContainer {
  {
    image,
    container_name,
    ports,
    envs,
    cmd,
    id: "",
  }
}

/// 添加端口映射
pub fn with_port(self: DockerContainer, host_port: Int, container_port: Int) -> DockerContainer {
  { self with ports: self.ports + [(host_port, container_port)] }
}

/// 添加环境变量
pub fn with_env(self: DockerContainer, key: String, value: String) -> DockerContainer {
  { self with envs: self.envs + [(key, value)] }
}

/// 设置启动命令
pub fn with_cmd(self: DockerContainer, cmd: Array[String]) -> DockerContainer {
  { self with cmd }
}

/// 启动容器
/// 返回容器 ID
pub fn start(self: DockerContainer) -> Result[String, String] {
  let id = create_container(self)
  id.map(fn(id) {
    let _ = start_container(id)
    // 写入 ID 供后续 stop/close 使用
    // 注意：MoonBit 中 struct 不可变，需要外部保存 ID
    id
  })
}

/// 停止并删除容器
pub fn stop(id: String) -> Result[Unit, String] {
  let _ = stop_container(id)?
  let _ = remove_container(id)?
  Ok(())
}

// --- Docker API 底层（Unix socket 通信） ---

fn docker_socket_path() -> String {
  "/var/run/docker.sock"
}

fn create_container(cfg: DockerContainer) -> Result[String, String] {
  let body = build_create_body(cfg)
  // Docker API: POST /containers/create
  let url = "http://localhost/v1.45/containers/create"
  let resp = http_post_unix(docker_socket_path(), url, body)?
  parse_container_id(resp)
}

fn start_container(id: String) -> Result[Unit, String] {
  // Docker API: POST /containers/{id}/start
  let url = "http://localhost/v1.45/containers/" + id + "/start"
  let _ = http_post_unix(docker_socket_path(), url, "{}")?
  Ok(())
}

fn stop_container(id: String) -> Result[Unit, String] {
  // Docker API: POST /containers/{id}/stop?t=5
  let url = "http://localhost/v1.45/containers/" + id + "/stop?t=5"
  let _ = http_post_unix(docker_socket_path(), url, "{}")?
  Ok(())
}

fn remove_container(id: String) -> Result[Unit, String] {
  // Docker API: DELETE /containers/{id}?v=true&force=true
  // 简化版：用 POST 模拟
  let url = "http://localhost/v1.45/containers/" + id + "?force=true"
  let _ = http_delete_unix(docker_socket_path(), url)?
  Ok(())
}

/// 等待端口可用
pub fn wait_for_port(host: String, port: Int, timeout_ms: Int) -> Result[Unit, String] {
  let start = now_ms()
  loop {
    let ok = try_connect(host, port)
    if ok {
      return Ok(())
    }
    if now_ms() - start > timeout_ms {
      return Err("Timeout waiting for " + host + ":" + port.to_string())
    }
    sleep_ms(500)
  }
}

/// 等待 HTTP 200
pub fn wait_for_http(url: String, timeout_ms: Int) -> Result[Unit, String] {
  let start = now_ms()
  loop {
    let resp = http_get(url)
    if resp.is_ok() {
      return Ok(())
    }
    if now_ms() - start > timeout_ms {
      return Err("Timeout waiting for HTTP 200: " + url)
    }
    sleep_ms(500)
  }
}

// --- HTTP 工具（Unix socket） ---

fn http_post_unix(socket: String, url: String, body: String) -> Result[String, String] {
  // 通过 Unix socket 发送 HTTP 请求
  // MoonBit 标准库对 Unix socket 的支持有限
  // 这里使用 cURL FFI 调用
  curl_send("POST", socket, url, body)
}

fn http_delete_unix(socket: String, url: String) -> Result[String, String] {
  curl_send("DELETE", socket, url, "")
}

fn curl_send(method: String, socket: String, url: String, body: String) -> Result[String, String] {
  // 通过 FFI 调用 curl 命令
  // 实际实现需通过系统调用
  Err("Not implemented: use `curl --unix-socket " + socket + " -X " + method + " " + url + " -d '" + body + "'` in your test script")
}

// --- 辅助函数 ---

fn build_create_body(cfg: DockerContainer) -> String {
  // 构建 Docker API 创建容器的 JSON body
  let port_bindings = cfg.ports.map(fn(p) {
    let (host_port, container_port) = p
    "\"" + container_port.to_string() + "/tcp\": {\"HostPort\": \"" + host_port.to_string() + "\"}"
  })
  let exposed = cfg.ports.map(fn(p) {
    let (_, container_port) = p
    "\"" + container_port.to_string() + "/tcp\": {}"
  })
  let env_str = cfg.envs.map(fn(e) {
    let (k, v) = e
    "\"" + k + "=" + v + "\""
  })
  let cmd_str = cfg.cmd.map(fn(c) { "\"" + c + "\"" })

  let json = "{"
    + "\"Image\": \"" + cfg.image + "\","
    + "\"HostConfig\": {\"PortBindings\": {" + port_bindings.join(",") + "}},"
    + "\"ExposedPorts\": {" + exposed.join(",") + "},"
    + "\"Env\": [" + env_str.join(",") + "],"
    + "\"Cmd\": [" + cmd_str.join(",") + "],"
    + "\"OpenStdin\": false,"
    + "\"Tty\": false"
    + "}"
  json
}

fn parse_container_id(resp: String) -> Result[String, String] {
  // 从 Docker API 响应中提取 ID
  // 响应格式: {"Id":"abc123","Warnings":[]}
  // 简化解析
  let parts = resp.split("\"Id\":\"")
  if parts.length() < 2 {
    return Err("Failed to parse container ID from: " + resp)
  }
  let id_part = parts[1]
  let id = id_part.split("\"")[0]
  Ok(id)
}

fn try_connect(host: String, port: Int) -> Bool {
  // 尝试 TCP 连接
  // 通过系统调用或 FFI
  // 简化：用 curl 测试
  false
}

fn now_ms() -> Int64 {
  // 当前时间戳（毫秒）
  0
}

fn sleep_ms(ms: Int) {
  // 休眠
}

/// 公开的 HTTP GET 辅助（用于测试断言）
pub fn http_get(url: String) -> Result[String, String] {
  let cmd = "curl -s --max-time 5 " + url
  exec_command(cmd)
}

/// 公开的 HTTP POST 辅助
pub fn http_post(url: String, body: String) -> Result[String, String] {
  let cmd = "curl -s --max-time 5 -X POST -d '" + body + "' " + url
  exec_command(cmd)
}

fn exec_command(cmd: String) -> Result[String, String] {
  // 通过 FFI 执行命令
  // MoonBit 标准库中可通过 @ffi 调用系统命令
  Err("Run: " + cmd)
}

/// 查找空闲端口
pub fn find_free_port() -> Result[Int, String] {
  // 通过系统的 /proc/net/tcp 或直接 bind 0 找可用端口
  // 简化版：返回默认范围
  let cmd = "python3 -c \"import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()\""
  let result = exec_command(cmd)
  result.flat_map(fn(s) { s.trim().to_int().ok_or("parse port") })
}
