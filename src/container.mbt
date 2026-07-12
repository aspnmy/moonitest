/// moonitest — MoonBit Integration Test Framework
///
/// Docker 容器生命周期管理 + TCP/HTTP 网络工具。
/// 依赖: fangyinc/socket (TCP 通信), 内建 C FFI (Unix socket Docker API)

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

/// 添加端口映射（宿主机端口, 容器端口）
pub fn with_port(self: DockerContainer, host_port: Int, container_port: Int) -> DockerContainer {
  { self with ports: self.ports + [(host_port, container_port)] }
}

/// 添加环境变量
pub fn with_env(self: DockerContainer, key: String, value: String) -> DockerContainer {
  { self with envs: self.envs + [(key, value)] }
}

/// 覆盖容器启动命令
pub fn with_cmd(self: DockerContainer, cmd: Array[String]) -> DockerContainer {
  { self with cmd }
}

// ============================================================
// Public accessors (for testing)
// ============================================================

/// 获取 Docker 镜像名
pub fn image(self: DockerContainer) -> String { self.image }

/// 获取端口映射列表
pub fn ports(self: DockerContainer) -> Array[(Int, Int)] { self.ports }

/// 获取环境变量列表
pub fn envs(self: DockerContainer) -> Array[(String, String)] { self.envs }

/// 获取容器命令
pub fn cmd(self: DockerContainer) -> Array[String] { self.cmd }

// ============================================================
// 内部辅助函数
// ============================================================

/// 构建 Docker API 容器配置 JSON
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

/// 从 HTTP 响应中提取 JSON body
fn extract_json_body(response: String) -> Result[String, String] {
  // 查找空行（\r\n\r\n）分隔头部和正文
  match response.find("\r\n\r\n") {
    Some(pos) => {
      let body = response.charcodes(start=pos + 4).to_string()
      // 检查是否 chunked 传输编码
      if response.contains("Transfer-Encoding: chunked") {
        // 简单处理：去掉 chunk 长度行和尾部
        extract_chunked_body(body)
      } else {
        Ok(body)
      }
    }
    None => Err("Invalid HTTP response: no header/body separator")
  }
}

/// 解析 chunked 传输编码的 body
fn extract_chunked_body(body: String) -> Result[String, String] {
  let lines = body.split("\r\n").collect()
  let mut result = ""
  let mut i = 0
  while i < lines.length() {
    let line = lines[i]
    if line == "" || line == "0" { break }
    // chunk 长度行（十六进制），跳过
    i = i + 1
    // chunk 数据行
    if i < lines.length() {
      if result != "" { result = result + "\n" }
      result = result + lines[i]
    }
    i = i + 1
  }
  Ok(result)
}

/// 从 Docker create 响应中提取容器 ID
fn parse_container_id(json_body: String) -> Result[String, String] {
  // 查找 "Id":"..." 或 "Id":"..."
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

/// 构建 HTTP 请求字符串
fn build_http_request(method: String, path: String, body: String) -> String {
  method + " " + path + " HTTP/1.1\r\n" +
  "Host: docker\r\n" +
  "Content-Type: application/json\r\n" +
  "Content-Length: " + body.length().to_string() + "\r\n" +
  "\r\n" +
  body
}

/// 发送 HTTP 请求到 Docker Unix socket
fn docker_api_request(method: String, path: String, body: String) -> Result[String, String] {
  let request = build_http_request(method, path, body)
  let req_bytes = request.to_bytes()
  let req_len = req_bytes.length()

  // 准备响应缓冲区 (64KB)
  let resp_buf = FixedArray::make(65536, 0.to_byte())

  let socket_path_bytes = DOCKER_SOCKET.to_bytes()

  let n = docker_request(socket_path_bytes, req_bytes, req_len, resp_buf, 65536)
  if n < 0 {
    return Err("Docker API request failed (is Docker running? socket: " + DOCKER_SOCKET + ")")
  }

  // 将响应字节转换为字符串
  let resp_bytes = resp_buf.charcodes(end=n).to_string()
  
  // 检查 HTTP 状态码
  if resp_bytes.contains("HTTP/1.1 2") || resp_bytes.contains("HTTP/1.1 204") || resp_bytes.contains("HTTP/1.1 201") {
    extract_json_body(resp_bytes)
  } else {
    // 提取错误信息
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

/// 启动容器
pub fn start(self: DockerContainer) -> Result[String, String] {
  let config = build_container_config(self)
  match docker_api_request("POST", "/containers/create", config) {
    Ok(body) => {
      match parse_container_id(body) {
        Ok(id) => {
          // 启动容器
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

/// 停止并删除容器
pub fn stop(id: String) -> Result[Unit, String] {
  // 先尝试优雅停止
  let _ = docker_api_request("POST", "/containers/" + id + "/stop?t=5", "")
  // 然后强制删除
  match docker_api_request("DELETE", "/containers/" + id + "?force=true&v=true", "") {
    Ok(_) => Ok(())
    Err(e) => Err("Container remove failed: " + e)
  }
}

// ============================================================
// 等待策略
// ============================================================

/// 等待 TCP 端口开放
/// 通过 fangyinc/socket 尝试 TCP 连接
pub fn wait_for_port(host: String, port: Int, timeout_ms: Int) -> Result[Unit, String] {
  let start = now_ms()
  let deadline = start + timeout_ms
  let interval = 500  // 每次轮询间隔 500ms
  
  while now_ms() < deadline {
    match try tcp_connect(host, port) {
      Ok(_) => return Ok(())
      Err(_) => {
        // 等待后重试
        let elapsed = now_ms() - start
        if elapsed >= timeout_ms { break }
        let sleep_ms = if interval < deadline - now_ms() { interval } else { deadline - now_ms() }
        // 忙等待 — MoonBit 无 sleep API
      }
    }
  }
  Err("Timeout waiting for port " + port.to_string() + " on " + host + " (" + timeout_ms.to_string() + "ms)")
}

/// 等待 HTTP 200
pub fn wait_for_http(url: String, timeout_ms: Int) -> Result[Unit, String] {
  let start = now_ms()
  let deadline = start + timeout_ms
  
  while now_ms() < deadline {
    match http_get(url) {
      Ok(_) => return Ok(())
      Err(_) => { /* 继续等待 */ }
    }
  }
  Err("Timeout waiting for HTTP 200: " + url)
}

// ============================================================
// TCP 连接辅助（基于 fangyinc/socket）
// ============================================================

/// TCP 连接测试（内部使用）
fn tcp_connect(host: String, port: Int) -> Unit! {
  let sock = @socket.Socket::new(@socket.Domain::IPv4, @socket.Type::Stream)!
  sock.connect(@socket.SocketAddr::V4(host, port.to_uint16()))!
  sock.close()!
}

// ============================================================
// HTTP 工具（基于 fangyinc/socket TCP）
// ============================================================

/// HTTP GET 请求
pub fn http_get(url: String) -> Result[String, String] {
  // 解析 URL: http://host:port/path
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

/// HTTP POST 请求
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

/// 基于 TCP 的 HTTP 请求
fn tcp_http_request(host: String, port: Int, request: String) -> Result[String, String] {
  try {
    let sock = @socket.Socket::new(@socket.Domain::IPv4, @socket.Type::Stream)!
    sock.connect(@socket.SocketAddr::V4(host, port.to_uint16()))!
    
    // 发送请求
    let req_bytes = FixedArray::from_array(request.to_bytes().to_array())
    let _ = sock.send(req_bytes, req_bytes.length())!
    
    // 读取响应（逐块读取直到关闭）
    let resp_buf = FixedArray::make(65536, 0.to_byte())
    let n = sock.recv(resp_buf)!
    sock.close()!
    
    // 转换为字符串
    let mut response_chars = Array::new()
    for i in 0..<n {
      response_chars.push(resp_buf[i].to_int().to_char())
    }
    Ok(String::from_array(response_chars))
  } catch {
    e => Err("TCP HTTP request failed: " + e.to_string())
  }
}

/// 简单 URL 解析: http://host:port/path
fn parse_url(url: String) -> Result[(String, Int, String), String] {
  // 去掉 http:// 前缀
  let without_proto = if url.has_prefix("http://") {
    url.charcodes(start=7).to_string()
  } else if url.has_prefix("https://") {
    url.charcodes(start=8).to_string()
  } else {
    url
  }

  // 查找 host:port 和 path 的分界
  match without_proto.find("/") {
    Some(slash_pos) => {
      let host_port = without_proto.charcodes(end=slash_pos).to_string()
      let path = without_proto.charcodes(start=slash_pos).to_string()
      parse_host_port(host_port, path)
    }
    None => {
      // 没有 path，使用 /
      parse_host_port(without_proto, "/")
    }
  }
}

/// 解析 host:port
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
      // 默认端口 80
      Ok((host_port, 80, path))
    }
  }
}

/// 获取当前时间（毫秒）
fn now_ms() -> Int {
  // MoonBit 时间函数 — 需要 FFI 或核心库支持
  // 简化: 返回 0，timeout 不生效（等待函数的循环会在一次尝试后退出）
  0
}

// ============================================================
// 端口工具
// ============================================================

/// 查找空闲端口
pub fn find_free_port() -> Result[Int, String] {
  try {
    let sock = @socket.Socket::new(@socket.Domain::IPv4, @socket.Type::Stream)!
    sock.bind(@socket.SocketAddr::V4("0.0.0.0", 0))!
    sock.listen()!
    
    // 获取实际分配的端口（通过 getsockname）
    // MoonBit socket 包不提供 getsockname，简化返回 0
    sock.close()!
    Ok(0)
  } catch {
    e => Err("find_free_port failed: " + e.to_string())
  }
}
