// === Docker 运行时函数 — 不依赖 Docker，验证不崩溃即可 ===

test "start returns Ok or Err" {
  let pg = DockerContainer::new("postgres:16-alpine")
  let r = pg.start()
  match r {
    Ok(_) => println("Docker available, container created")
    Err(e) => println("Docker not available: " + e)
  }
}

test "stop returns Ok or Err" {
  let r = stop("fake-id")
  match r {
    Ok(_) => println("stop OK (should not happen with fake id)")
    Err(e) => println("stop returns Err: " + e)
  }
}

// === TCP/HTTP 函数 — 用不可达地址触发连接拒绝 ===

test "wait_for_port returns Err on unreachable port" {
  let r = wait_for_port("localhost", 65432, 1000)
  if !r.is_err() { println("expected Err on unreachable port"); panic() }
}

test "wait_for_http returns Err on unreachable URL" {
  let r = wait_for_http("http://localhost:16543", 1000)
  if !r.is_err() { println("expected Err on unreachable URL"); panic() }
}

test "http_get returns Err on unreachable host" {
  let r = http_get("http://localhost:16543")
  if !r.is_err() { println("expected Err on unreachable host"); panic() }
}

test "http_post returns Err on unreachable host" {
  let r = http_post("http://localhost:16543/api", "{}")
  if !r.is_err() { println("expected Err on unreachable host"); panic() }
}

test "find_free_port returns Ok or Err" {
  let r = find_free_port()
  match r {
    Ok(port) => println("free port: " + port.to_string())
    Err(e) => println("port not available: " + e)
  }
}

// === DockerContainer builder — verify via public accessors ===

test "new creates container with default values" {
  let c = DockerContainer::new("test:latest")
  if c.image() != "test:latest" { println("image mismatch"); panic() }
  if c.ports().length() != 0 { println("ports should be empty"); panic() }
  if c.envs().length() != 0 { println("envs should be empty"); panic() }
  if c.cmd().length() != 0 { println("cmd should be empty"); panic() }
}

test "with_port adds single port mapping" {
  let c = DockerContainer::new("img").with_port(8080, 80)
  if c.ports().length() != 1 { println("should have 1 port"); panic() }
  let (host, container) = c.ports()[0]
  if host != 8080 { println("host port mismatch"); panic() }
  if container != 80 { println("container port mismatch"); panic() }
}

test "with_port supports multiple mappings" {
  let c = DockerContainer::new("img")
    .with_port(8080, 80)
    .with_port(443, 443)
  if c.ports().length() != 2 { println("should have 2 ports"); panic() }
  let (h1, c1) = c.ports()[0]
  let (h2, c2) = c.ports()[1]
  if h1 != 8080 || c1 != 80 { println("first port mismatch"); panic() }
  if h2 != 443 || c2 != 443 { println("second port mismatch"); panic() }
}

test "with_env adds environment variables" {
  let c = DockerContainer::new("img")
    .with_env("KEY", "val")
    .with_env("DEBUG", "1")
  if c.envs().length() != 2 { println("should have 2 envs"); panic() }
  let (k1, v1) = c.envs()[0]
  let (k2, v2) = c.envs()[1]
  if k1 != "KEY" || v1 != "val" { println("first env mismatch"); panic() }
  if k2 != "DEBUG" || v2 != "1" { println("second env mismatch"); panic() }
}

test "with_cmd sets container command" {
  let c = DockerContainer::new("img").with_cmd(["echo", "hello"])
  if c.cmd().length() != 2 { println("cmd length mismatch"); panic() }
  if c.cmd()[0] != "echo" { println("cmd[0] mismatch"); panic() }
  if c.cmd()[1] != "hello" { println("cmd[1] mismatch"); panic() }
}

test "full builder chain" {
  let c = DockerContainer::new("my-app:1")
    .with_port(3000, 3000)
    .with_env("MODE", "production")
    .with_cmd(["start", "--port", "3000"])
  if c.image() != "my-app:1" { println("image mismatch"); panic() }
  if c.ports().length() != 1 { println("ports length mismatch"); panic() }
  if c.envs().length() != 1 { println("envs length mismatch"); panic() }
  if c.cmd().length() != 3 { println("cmd length mismatch"); panic() }
}

// === Preset container factories ===

test "postgres_container preset" {
  let c = postgres_container(15432)
  if c.image() != "postgres:16-alpine" { println("image mismatch"); panic() }
  let (host_pg, container_pg) = c.ports()[0]
  if host_pg != 15432 || container_pg != 5432 { println("port mismatch"); panic() }
  let envs = c.envs()
  if envs.length() < 3 { println("should have at least 3 envs"); panic() }
}

test "redis_container preset" {
  let c = redis_container(16379)
  if c.image() != "redis:7-alpine" { println("image mismatch"); panic() }
  let (host_rd, container_rd) = c.ports()[0]
  if host_rd != 16379 || container_rd != 6379 { println("port mismatch"); panic() }
  if c.envs().length() != 0 { println("redis should have no envs"); panic() }
}

test "mysql_container preset" {
  let c = mysql_container(13306)
  if c.image() != "mysql:8.0" { println("image mismatch"); panic() }
  let (host_my, container_my) = c.ports()[0]
  if host_my != 13306 || container_my != 3306 { println("port mismatch"); panic() }
  let envs = c.envs()
  if envs.length() < 4 { println("should have at least 4 envs"); panic() }
}

// === Connection string formatting ===

test "postgres_connection_string format" {
  let s = postgres_connection_string("localhost", 15432)
  if s != "postgresql://test_user:test_pass@localhost:15432/test_db" {
    println(s); panic()
  }
}

test "postgres_connection_string with remote host" {
  let s = postgres_connection_string("db.example.com", 5432)
  if s != "postgresql://test_user:test_pass@db.example.com:5432/test_db" {
    println(s); panic()
  }
}

test "redis_address format" {
  let s = redis_address("localhost", 6379)
  if s != "localhost:6379" { println(s); panic() }
}

test "mysql_connection_string format" {
  let s = mysql_connection_string("localhost", 3306)
  if s != "mysql://test_user:test_pass@localhost:3306/test_db" {
    println(s); panic()
  }
}
