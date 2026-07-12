// === Stub functions — all return Err ===

test "start returns Err when no Docker" {
  let pg = DockerContainer::new("postgres:16-alpine")
  let r = pg.start()
  match r {
    Ok(_) => panic("expected Err without Docker")
    Err(e) => if e == "" { panic("error message should not be empty") }
  }
}

test "stop returns Err when no Docker" {
  let r = stop("fake-id")
  match r {
    Ok(_) => panic("expected Err")
    Err(e) => if e == "" { panic("error message should not be empty") }
  }
}

test "wait_for_port returns Err" {
  let r = wait_for_port("localhost", 5432, 1000)
  if !r.is_err() { panic("expected Err") }
}

test "wait_for_http returns Err" {
  let r = wait_for_http("http://localhost:8080", 1000)
  if !r.is_err() { panic("expected Err") }
}

test "http_get returns Err" {
  let r = http_get("http://localhost:8080")
  if !r.is_err() { panic("expected Err") }
}

test "http_post returns Err" {
  let r = http_post("http://localhost:8080/api", "{}")
  if !r.is_err() { panic("expected Err") }
}

test "find_free_port returns Err" {
  let r = find_free_port()
  if !r.is_err() { panic("expected Err") }
}

// === DockerContainer builder — verify internal state via accessors ===

test "new creates container with default values" {
  let c = DockerContainer::new("test:latest")
  if c.image() != "test:latest" { panic("image mismatch") }
  if c.ports().length() != 0 { panic("ports should be empty") }
  if c.envs().length() != 0 { panic("envs should be empty") }
  if c.cmd().length() != 0 { panic("cmd should be empty") }
}

test "with_port adds single port mapping" {
  let c = DockerContainer::new("img").with_port(8080, 80)
  if c.ports().length() != 1 { panic("should have 1 port") }
  let (host, container) = c.ports()[0]
  if host != 8080 { panic("host port mismatch") }
  if container != 80 { panic("container port mismatch") }
}

test "with_port supports multiple mappings" {
  let c = DockerContainer::new("img")
    .with_port(8080, 80)
    .with_port(443, 443)
  if c.ports().length() != 2 { panic("should have 2 ports") }
  let (h1, c1) = c.ports()[0]
  let (h2, c2) = c.ports()[1]
  if h1 != 8080 || c1 != 80 { panic("first port mismatch") }
  if h2 != 443 || c2 != 443 { panic("second port mismatch") }
}

test "with_env adds environment variables" {
  let c = DockerContainer::new("img")
    .with_env("KEY", "val")
    .with_env("DEBUG", "1")
  if c.envs().length() != 2 { panic("should have 2 envs") }
  let (k1, v1) = c.envs()[0]
  let (k2, v2) = c.envs()[1]
  if k1 != "KEY" || v1 != "val" { panic("first env mismatch") }
  if k2 != "DEBUG" || v2 != "1" { panic("second env mismatch") }
}

test "with_cmd sets container command" {
  let c = DockerContainer::new("img").with_cmd(["echo", "hello"])
  if c.cmd().length() != 2 { panic("cmd length mismatch") }
  if c.cmd()[0] != "echo" { panic("cmd[0] mismatch") }
  if c.cmd()[1] != "hello" { panic("cmd[1] mismatch") }
}

test "full builder chain" {
  let c = DockerContainer::new("my-app:1")
    .with_port(3000, 3000)
    .with_env("MODE", "production")
    .with_cmd(["start", "--port", "3000"])
  if c.image() != "my-app:1" { panic("image mismatch") }
  if c.ports().length() != 1 { panic("ports length mismatch") }
  if c.envs().length() != 1 { panic("envs length mismatch") }
  if c.cmd().length() != 3 { panic("cmd length mismatch") }
}

// === Preset container factories ===

test "postgres_container preset" {
  let c = postgres_container(15432)
  if c.image() != "postgres:16-alpine" { panic("image mismatch") }
  let (host_pg, container_pg) = c.ports()[0]
  if host_pg != 15432 || container_pg != 5432 { panic("port mismatch") }
  let envs = c.envs()
  if envs.length() < 3 { panic("should have at least 3 envs") }
}

test "redis_container preset" {
  let c = redis_container(16379)
  if c.image() != "redis:7-alpine" { panic("image mismatch") }
  let (host_rd, container_rd) = c.ports()[0]
  if host_rd != 16379 || container_rd != 6379 { panic("port mismatch") }
  if c.envs().length() != 0 { panic("redis should have no envs") }
}

test "mysql_container preset" {
  let c = mysql_container(13306)
  if c.image() != "mysql:8.0" { panic("image mismatch") }
  let (host_my, container_my) = c.ports()[0]
  if host_my != 13306 || container_my != 3306 { panic("port mismatch") }
  let envs = c.envs()
  if envs.length() < 4 { panic("should have at least 4 envs") }
}

// === Connection string formatting ===

test "postgres_connection_string format" {
  let s = postgres_connection_string("localhost", 15432)
  if s != "postgresql://test_user:test_pass@localhost:15432/test_db" {
    panic("unexpected: " + s)
  }
}

test "postgres_connection_string with remote host" {
  let s = postgres_connection_string("db.example.com", 5432)
  if s != "postgresql://test_user:test_pass@db.example.com:5432/test_db" {
    panic("unexpected: " + s)
  }
}

test "redis_address format" {
  let s = redis_address("localhost", 6379)
  if s != "localhost:6379" { panic("unexpected: " + s) }
}

test "mysql_connection_string format" {
  let s = mysql_connection_string("localhost", 3306)
  if s != "mysql://test_user:test_pass@localhost:3306/test_db" {
    panic("unexpected: " + s)
  }
}
