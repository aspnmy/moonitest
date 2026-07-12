/// moonitest — MoonBit Integration Test Framework
///
/// Docker 容器生命周期管理 + TCP/HTTP 网络工具。
///
/// 依赖:
/// - `fangyinc/socket` — TCP 连接与 HTTP 请求
/// - 内建 C FFI — Docker Unix socket 通信
///
/// 所有运行时操作需要 Linux 环境 + Docker daemon + 可访问 `/var/run/docker.sock`。
/// 纯配置操作（Builder、预设、连接字符串）可在任何目标上编译。

// ============================================================
// C FFI — Docker Unix Socket 通信
// ============================================================

extern "C" fn docker_request(
  socket_path: Bytes, req_data: Bytes, req_len: Int,
  resp_buf: FixedArray[Byte], resp_bufsize: Int
) -> Int = "moonbit_docker_request"

// ============================================================
// 常量
// ============================================================

let DOCKER_SOCKET = "/var/run/docker.sock"

// ============================================================
// DockerContainer — 容器配置结构体
// ============================================================

/// Docker 容器配置。
///
/// 通过 Builder 模式构造，支持端口映射、环境变量、启动命令。
/// 使用 `new()` 创建，链式调用 `with_port()` / `with_env()` / `with_cmd()` 配置，
/// 最后调用 `start()` 启动容器。
///
/// 示例：
/// ```moonbit
/// let pg = DockerContainer::new("postgres:16-alpine")
///   .with_port(15432, 5432)
///   .with_env("POSTGRES_USER", "myapp")
///   .with_env("POSTGRES_PASSWORD", "secret")
/// ```
pub struct DockerContainer {
  image: String
  ports: Array[(Int, Int)]
  envs: Array[(String, String)]
  cmd: Array[String]
}

/// 创建一个新的 Docker 容器配置。
///
/// 参数：
/// - `image`: Docker 镜像名，如 `"postgres:16-alpine"`
///
/// 返回初始配置（空端口映射、空环境变量、空命令）。
///
/// 示例：
/// ```moonbit
/// let c = DockerContainer::new("redis:7-alpine")
/// ```
pub fn DockerContainer::new(image: String) -> DockerContainer {
  { image, ports: [], envs: [], cmd: [] }
}

/// 添加端口映射。
///
/// 参数：
/// - `host_port`: 宿主机端口
/// - `container_port`: 容器端口
///
/// 示例：
/// ```moonbit
/// .with_port(8080, 80)  // 宿主机 8080 → 容器 80
/// ```
pub fn with_port(self: DockerContainer, host_port: Int, container_port: Int) -> DockerContainer {
  { self with ports: self.ports + [(host_port, container_port)] }
}

/// 添加环境变量。
///
/// 参数：
/// - `key`: 环境变量名
/// - `value`: 环境变量值
///
/// 示例：
/// ```moonbit
/// .with_env("POSTGRES_DB", "mydb")
/// ```
pub fn with_env(self: DockerContainer, key: String, value: String) -> DockerContainer {
  { self with envs: self.envs + [(key, value)] }
}

/// 覆盖容器启动命令。
///
/// 参数：
/// - `cmd`: 命令数组，如 `["npm", "start"]`
///
/// 示例：
/// ```moonbit
/// .with_cmd(["redis-server", "--port", "6379"])
/// ```
pub fn with_cmd(self: DockerContainer, cmd: Array[String]) -> DockerContainer {
  { self with cmd }
}

// ============================================================
// Public accessors (for testing)
// ============================================================

/// 获取 Docker 镜像名。
pub fn image(self: DockerContainer) -> String { self.image }

/// 获取端口映射列表，每项为 `(宿主机端口, 容器端口)`。
pub fn ports(self: DockerContainer) -> Array[(Int, Int)] { self.ports }

/// 获取环境变量列表，每项为 `(键, 值)`。
pub fn envs(self: DockerContainer) -> Array[(String, String)] { self.envs }

/// 获取容器启动命令数组。
pub fn cmd(self: DockerContainer) -> Array[String] { self.cmd }

// ============================================================
// 内部辅助函数
// ============================================================

/// 构建 Docker API 容器配置 JSON。
fn build_container_config(self: DockerContainer) -> String {
  let mut exposed = ""
  let mut port_bindings = ""
  for (hp, cp) in self.ports {
    let container_port_str = cp.to_string() + "/tcp"
    if exposed != "" { exposed = exposed + "," }
    exposed = exposed + "\"" + container_port_str + "\":{}"
    if port_bindings != "" { port_bindings = port_bindings + "," }
    port_bindings = port_bindings + "\"" + container_port_str + "\":[{\"HostPort\":\"" + hp.to_string() + "\"}]"
  }

  let mut env_arr = "["
  let mut first = true
  for (k, v) in self.envs {
    if !first { env_arr = env_arr + "," }
    env_arr = env_arr + "\"" + k + "=" + v + "\""
    first = false
  }
  env_arr = env_arr + "]"

  let mut config = "{\"Image\":\"" + self.image + "\""
  if self.ports.length() > 0 {
    config = config + ",\"ExposedPorts\":" + exposed
    config = config + ",\"HostConfig\":{\"PortBindings\":" + port_bindings + "}"
  }
  if self.envs.length() > 0 {
    config = config + ",\"Env\":" + env_arr
  }
  if self.cmd.length() > 0 {
    let cmd_json = self.cmd.map(fn(s) { "\"" + s + "\"" }).join(",")
    config = config + ",\"Cmd\":[" + cmd_json + "]"
  }
  config = config + "}"
  config
}

/// 从 HTTP 响应中提取 JSON body。
fn extract_json_body(response: String) -> Result[String, String] {
  match response.find("\r\n\r\n") {
    Some(pos) => {
      let body = response.charcodes(start=pos + 4).to_string()
      if response.contains("Transfer-Encoding: chunked") {
        extract_chunked_body(body)
      } else {
        Ok(body)
      }
    }
    None => Err("Invalid HTTP response: no header/body separator")
  }
}

/// 解析 chunked 传输编码的 body。
fn extract_chunked_body(body: String) -> Result[String, String] {
  let lines = body.split("\r\n").collect()
  let mut result = ""
  let mut i = 0
  while i < lines.length() {
    let line = lines[i]
    if line == "" || line == "0" { break }
    i = i + 1
    if i < lines.length() {
      if result != "" { result = result + "\n" }
      result = result + lines[i]
    }
    i = i + 1
  }
  Ok(result)
}

/// 从 Docker create 响应中提取容器 ID。
fn parse_container_id(json_body: String) -> Result[String, String] {
  match json_body.find("\"Id\":\"") {
    Some(pos) => {
      let start = pos + 6
      let remaining = json_body.charcodes(start=start).to_string()
      match remaining.find("\"") {
        Some(end) => Ok(remaining.charcodes(end=end).to_string())
        None => Err("Cannot parse container ID from: " + json_body)
      }
    }
    None => Err("Cannot find Id field in: " + json_body)
  }
}

/// 构建 HTTP 请求字符串。
fn build_http_request(method: String, path: String, body: String) -> String {
  method + " " + path + " HTTP/1.1\r\n" +
  "Host: docker\r\n" +
  "Content-Type: application/json\r\n" +
  "Content-Length: " + body.length().to_string() + "\r\n" +
  "\r\n" +
  body
}

/// 发送 HTTP 请求到 Docker Unix socket。
fn docker_api_request(method: String, path: String, body: String) -> Result[String, String] {
  let request = build_http_request(method, path, body)
  let req_bytes = request.to_bytes()
  let req_len = req_bytes.length()

  let resp_buf = FixedArray::make(65536, 0.to_byte())
  let socket_path_bytes = DOCKER_SOCKET.to_bytes()

  let n = docker_request(socket_path_bytes, req_bytes, req_len, resp_buf, 65536)
  if n < 0 {
    return Err("Docker API request failed (is Docker running? socket: " + DOCKER_SOCKET + ")")
  }

  let resp_bytes = resp_buf.charcodes(end=n).to_string()

  if resp_bytes.contains("HTTP/1.1 2") || resp_bytes.contains("HTTP/1.1 204") || resp_bytes.contains("HTTP/1.1 201") {
    extract_json_body(resp_bytes)
  } else {
    let body = try? extract_json_body(resp_bytes)
    match body {
      Ok(b) => Err("Docker API error: " + b)
      Err(_) => Err("Docker API error (HTTP): " + resp_bytes.charcodes(end=200).to_string())
    }
  }
}

// ============================================================
// 容器生命周期
// ============================================================

/// 创建并启动 Docker 容器。
///
/// 通过 Docker Unix socket API 执行以下操作：
/// 1. `POST /containers/create` — 创建容器
/// 2. `POST /containers/{id}/start` — 启动容器
///
/// 成功返回容器 ID（字符串），失败返回错误信息。
///
/// 示例：
/// ```moonbit
/// match pg.start() {
///   Ok(id) => println("container started: " + id)
///   Err(e) => println("failed: " + e)
/// }
/// ```
pub fn start(self: DockerContainer) -> Result[String, String] {
  let config = build_container_config(self)
  match docker_api_request("POST", "/containers/create", config) {
    Ok(body) => {
      match parse_container_id(body) {
        Ok(id) => {
          match docker_api_request("POST", "/containers/" + id + "/start", "") {
            Ok(_) => Ok(id)
            Err(e) => Err("Container created but start failed: " + e)
          }
        }
        Err(e) => Err("Failed to parse container ID: " + e)
      }
    }
    Err(e) => Err("Container create failed: " + e)
  }
}

/// 停止并删除 Docker 容器。
///
/// 执行：
/// 1. `POST /containers/{id}/stop?t=5` — 优雅停止（5 秒超时）
/// 2. `DELETE /containers/{id}?force=true&v=true` — 强制删除
///
/// 示例：
/// ```moonbit
/// let _ = stop(container_id)
/// ```
pub fn stop(id: String) -> Result[Unit, String] {
  let _ = docker_api_request("POST", "/containers/" + id + "/stop?t=5", "")
  match docker_api_request("DELETE", "/containers/" + id + "?force=true&v=true", "") {
    Ok(_) => Ok(())
    Err(e) => Err("Container remove failed: " + e)
  }
}

// ============================================================
// 等待策略
// ============================================================

/// 等待 TCP 端口开放。
///
/// 通过 fangyinc/socket 尝试 TCP 连接到指定主机和端口。
/// 当前为单次检测，timeout 轮询将在后续版本添加。
///
/// 参数：
/// - `host`: 主机名或 IP
/// - `port`: 端口号
/// - `timeout_ms`: 超时毫秒数（当前未实现轮询）
///
/// 示例：
/// ```moonbit
/// match wait_for_port("localhost", 5432, 30000) {
///   Ok(_) => println("port ready")
///   Err(e) => println("timeout: " + e)
/// }
/// ```
pub fn wait_for_port(host: String, port: Int, timeout_ms: Int) -> Result[Unit, String] {
  match try tcp_connect(host, port) {
    Ok(_) => Ok(())
    Err(e) => Err("Port " + port.to_string() + " on " + host + " not ready: " + e)
  }
}

/// 等待 HTTP 服务返回 200。
///
/// 当前为单次检测，timeout 轮询将在后续版本添加。
///
/// 参数：
/// - `url`: HTTP URL，如 `"http://localhost:8080/health"`
/// - `timeout_ms`: 超时毫秒数（当前未实现轮询）
///
/// 示例：
/// ```moonbit
/// match wait_for_http("http://localhost:8080/health", 10000) {
///   Ok(_) => println("service ready")
///   Err(e) => println("not ready: " + e)
/// }
/// ```
pub fn wait_for_http(url: String, timeout_ms: Int) -> Result[Unit, String] {
  match http_get(url) {
    Ok(_) => Ok(())
    Err(e) => Err("HTTP not ready: " + url + " - " + e)
  }
}

// ============================================================
// TCP 连接辅助（基于 fangyinc/socket）
// ============================================================

/// TCP 连接测试（内部使用）。
fn tcp_connect(host: String, port: Int) -> Unit! {
  let sock = @socket.Socket::new(@socket.Domain::IPv4, @socket.Type::Stream)!
  sock.connect(@socket.SocketAddr::V4(host, port.to_uint16()))!
  sock.close()!
}

// ============================================================
// HTTP 工具（基于 fangyinc/socket TCP）
// ============================================================

/// 发送 HTTP GET 请求并返回 JSON 响应体。
///
/// 参数：
/// - `url`: 完整 HTTP URL，如 `"http://localhost:8080/api/users"`
///
/// 返回响应体字符串（仅 body 部分，不含 HTTP 头部）。
///
/// 示例：
/// ```moonbit
/// match http_get("http://localhost:8080/health") {
///   Ok(body) => println(body)
///   Err(e) => println("error: " + e)
/// }
/// ```
pub fn http_get(url: String) -> Result[String, String] {
  match parse_url(url) {
    Ok((host, port, path)) => {
      let request = "GET " + path + " HTTP/1.1\r\nHost: " + host + "\r\nConnection: close\r\n\r\n"
      match tcp_http_request(host, port, request) {
        Ok(response) => {
          match extract_json_body(response) {
            Ok(body) => Ok(body)
            Err(e) => Err("HTTP response parse failed: " + e)
          }
        }
        Err(e) => Err("HTTP GET failed: " + e)
      }
    }
    Err(e) => Err("Invalid URL: " + e)
  }
}

/// 发送 HTTP POST 请求并返回 JSON 响应体。
///
/// 参数：
/// - `url`: 完整 HTTP URL，如 `"http://localhost:8080/api/users"`
/// - `body`: 请求体字符串（通常为 JSON）
///
/// 返回响应体字符串（仅 body 部分，不含 HTTP 头部）。
///
/// 示例：
/// ```moonbit
/// match http_post("http://localhost:8080/api/data", "{\"key\":\"value\"}") {
///   Ok(body) => println(body)
///   Err(e) => println("error: " + e)
/// }
/// ```
pub fn http_post(url: String, body: String) -> Result[String, String] {
  match parse_url(url) {
    Ok((host, port, path)) => {
      let request = "POST " + path + " HTTP/1.1\r\nHost: " + host + "\r\nContent-Type: application/json\r\nContent-Length: " + body.length().to_string() + "\r\nConnection: close\r\n\r\n" + body
      match tcp_http_request(host, port, request) {
        Ok(response) => {
          match extract_json_body(response) {
            Ok(b) => Ok(b)
            Err(e) => Err("HTTP response parse failed: " + e)
          }
        }
        Err(e) => Err("HTTP POST failed: " + e)
      }
    }
    Err(e) => Err("Invalid URL: " + e)
  }
}

/// 基于 TCP 的 HTTP 请求（内部使用）。
fn tcp_http_request(host: String, port: Int, request: String) -> Result[String, String] {
  try {
    let sock = @socket.Socket::new(@socket.Domain::IPv4, @socket.Type::Stream)!
    sock.connect(@socket.SocketAddr::V4(host, port.to_uint16()))!

    let req_bytes = FixedArray::from_array(request.to_bytes().to_array())
    let _ = sock.send(req_bytes, req_bytes.length())!

    let resp_buf = FixedArray::make(65536, 0.to_byte())
    let n = sock.recv(resp_buf)!
    sock.close()!

    let mut response_chars = Array::new()
    for i in 0..<n {
      response_chars.push(resp_buf[i].to_int().to_char())
    }
    Ok(String::from_array(response_chars))
  } catch {
    e => Err("TCP HTTP request failed: " + e.to_string())
  }
}

/// 简单 URL 解析: `http://host:port/path`。
fn parse_url(url: String) -> Result[(String, Int, String), String] {
  let without_proto = if url.has_prefix("http://") {
    url.charcodes(start=7).to_string()
  } else if url.has_prefix("https://") {
    url.charcodes(start=8).to_string()
  } else {
    url
  }

  match without_proto.find("/") {
    Some(slash_pos) => {
      let host_port = without_proto.charcodes(end=slash_pos).to_string()
      let path = without_proto.charcodes(start=slash_pos).to_string()
      parse_host_port(host_port, path)
    }
    None => {
      parse_host_port(without_proto, "/")
    }
  }
}

/// 解析 `host:port`。
fn parse_host_port(host_port: String, path: String) -> Result[(String, Int, String), String] {
  match host_port.find(":") {
    Some(colon_pos) => {
      let host = host_port.charcodes(end=colon_pos).to_string()
      let port_str = host_port.charcodes(start=colon_pos + 1).to_string()
      match try @strconv.parse_int(port_str) {
        Ok(port) => Ok((host, port, path))
        _ => Err("Invalid port: " + port_str)
      }
    }
    None => {
      Ok((host_port, 80, path))
    }
  }
}

// ============================================================
// 端口工具
// ============================================================

/// 查找空闲端口。
///
/// 尝试绑定到端口 0（由 OS 自动分配端口）。
/// 当前返回 0（实际端口获取需要 socket 包的 getsockname 支持）。
///
/// 示例：
/// ```moonbit
/// match find_free_port() {
///   Ok(port) => println("free port: " + port.to_string())
///   Err(e) => println("error: " + e)
/// }
/// ```
pub fn find_free_port() -> Result[Int, String] {
  try {
    let sock = @socket.Socket::new(@socket.Domain::IPv4, @socket.Type::Stream)!
    sock.bind(@socket.SocketAddr::V4("0.0.0.0", 0))!
    sock.listen()!
    sock.close()!
    Ok(0)
  } catch {
    e => Err("find_free_port failed: " + e.to_string())
  }
}
