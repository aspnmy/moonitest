/// moonitest --- MoonBit Integration Test Framework
///
/// Docker 容器生命周期管理 + TCP/HTTP 网络工具。
/// 依赖: aspnmy/moodtcpcli (TCP/HTTP), 内建 C FFI (Docker Unix socket)

// ============================================================
// C FFI --- Docker Unix Socket 通信
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
// DockerContainer --- 容器配置结构体
// ============================================================

/// Docker 容器配置。
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

pub fn image(self: DockerContainer) -> String { self.image }
pub fn ports(self: DockerContainer) -> Array[(Int, Int)] { self.ports }
pub fn envs(self: DockerContainer) -> Array[(String, String)] { self.envs }
pub fn cmd(self: DockerContainer) -> Array[String] { self.cmd }

// ============================================================
// 内部辅助函数
// ============================================================

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

fn extract_json_body(response: String) -> Result[String, String] {
  match response.find("\r\n\r\n") {
    Some(pos) => {
      let body = response[pos+4:].to_owned()
      if response.contains("Transfer-Encoding: chunked") {
        extract_chunked_body(body)
      } else {
        Ok(body)
      }
    }
    None => Err("Invalid HTTP response: no header/body separator")
  }
}

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

fn parse_container_id(json_body: String) -> Result[String, String] {
  match json_body.find("\"Id\":\"") {
    Some(pos) => {
      let start = pos + 6
      let remaining = json_body[start:].to_owned()
      match remaining.find("\"") {
        Some(end) => Ok(remaining[:end].to_owned())
        None => Err("Cannot parse container ID from: " + json_body)
      }
    }
    None => Err("Cannot find Id field in: " + json_body)
  }
}

fn build_http_request(method: String, path: String, body: String) -> String {
  method + " " + path + " HTTP/1.1\r\n" +
  "Host: docker\r\n" +
  "Content-Type: application/json\r\n" +
  "Content-Length: " + body.length().to_string() + "\r\n" +
  "\r\n" +
  body
}

fn docker_api_request(method: String, path: String, body: String) -> Result[String, String] {
  let request = build_http_request(method, path, body)
  let req_bytes = request.to_bytes()
  let req_len = req_bytes.length()
  let resp_buf = FixedArray::make(65536, 0)
  let socket_path_bytes = DOCKER_SOCKET.to_bytes()
  let n = docker_request(socket_path_bytes, req_bytes, req_len, resp_buf, 65536)
  if n < 0 {
    return Err("Docker API request failed (is Docker running? socket: " + DOCKER_SOCKET + ")")
  }
  let resp_bytes = String::from_array(resp_buf[:n].map(fn(b) { (b: Byte).to_int().to_char() }))
  if resp_bytes.contains("HTTP/1.1 2") || resp_bytes.contains("HTTP/1.1 201") || resp_bytes.contains("HTTP/1.1 204") {
    extract_json_body(resp_bytes)
  } else {
    let body = try? extract_json_body(resp_bytes)
    match body {
      Ok(b) => Err("Docker API error: " + b)
      Err(_) => Err("Docker API error (HTTP): " + resp_bytes[:100].to_owned())
    }
  }
}

// ============================================================
// 容器生命周期
// ============================================================

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

pub fn stop(id: String) -> Result[Unit, String] {
  let _ = docker_api_request("POST", "/containers/" + id + "/stop?t=5", "")
  match docker_api_request("DELETE", "/containers/" + id + "?force=true&v=true", "") {
    Ok(_) => Ok(())
    Err(e) => Err("Container remove failed: " + e)
  }
}

// ============================================================
// 等待策略 --- 基于 moodtcpcli
// ============================================================

pub fn wait_for_port(host: String, port: Int, timeout_ms: Int) -> Result[Unit, String] {
  match @moodtcpcli.tcp_ping(host, port) {
    Ok(_) => Ok(())
    Err(e) => Err("Port " + port.to_string() + " on " + host + " not ready: " + e)
  }
}

pub fn wait_for_http(url: String, timeout_ms: Int) -> Result[Unit, String] {
  match @moodtcpcli.http_get(url) {
    Ok(_) => Ok(())
    Err(e) => Err("HTTP not ready: " + url + " - " + e)
  }
}

// ============================================================
// HTTP 工具 --- 委托给 moodtcpcli
// ============================================================

pub fn http_get(url: String) -> Result[String, String] {
  @moodtcpcli.http_get(url)
}

pub fn http_post(url: String, body: String) -> Result[String, String] {
  @moodtcpcli.http_post(url, body)
}

// ============================================================
// 端口工具 --- 委托给 moodtcpcli
// ============================================================

pub fn find_free_port() -> Result[Int, String] {
  @moodtcpcli.listen_port(0)
}
