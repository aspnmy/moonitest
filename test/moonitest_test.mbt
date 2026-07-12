// === Stub functions — all unimplemented in v0.1.x, expect Err ===

test "start returns Err when no Docker" {
  let pg = DockerContainer::new("postgres:16-alpine")
  let r = pg.start()
  match r {
    Ok(_) => fail("expected Err without Docker")
    Err(e) => assert(e != "")
  }
}

test "stop returns Err when no Docker" {
  let r = stop("fake-id")
  match r {
    Ok(_) => fail("expected Err")
    Err(e) => assert(e != "")
  }
}

test "wait_for_port returns Err" {
  let r = wait_for_port("localhost", 5432, 1000)
  assert(r.is_err())
}

test "wait_for_http returns Err" {
  let r = wait_for_http("http://localhost:8080", 1000)
  assert(r.is_err())
}

test "http_get returns Err" {
  let r = http_get("http://localhost:8080")
  assert(r.is_err())
}

test "http_post returns Err" {
  let r = http_post("http://localhost:8080/api", "{}")
  assert(r.is_err())
}

test "find_free_port returns Err" {
  let r = find_free_port()
  assert(r.is_err())
}

// === DockerContainer builder — verify internal state via public accessors ===

test "new creates container with default values" {
  let c = DockerContainer::new("test:latest")
  assert(c.image() == "test:latest")
  assert(c.ports().length() == 0)
  assert(c.envs().length() == 0)
  assert(c.cmd().length() == 0)
}

test "with_port adds single port mapping" {
  let c = DockerContainer::new("img")
    .with_port(8080, 80)
  assert(c.ports().length() == 1)
  let (host, container) = c.ports()[0]
  assert(host == 8080)
  assert(container == 80)
}

test "with_port supports multiple mappings" {
  let c = DockerContainer::new("img")
    .with_port(8080, 80)
    .with_port(443, 443)
  assert(c.ports().length() == 2)
  let (h1, c1) = c.ports()[0]
  let (h2, c2) = c.ports()[1]
  assert(h1 == 8080 && c1 == 80)
  assert(h2 == 443 && c2 == 443)
}

test "with_env adds environment variables" {
  let c = DockerContainer::new("img")
    .with_env("KEY", "val")
    .with_env("DEBUG", "1")
  assert(c.envs().length() == 2)
  let (k1, v1) = c.envs()[0]
  let (k2, v2) = c.envs()[1]
  assert(k1 == "KEY" && v1 == "val")
  assert(k2 == "DEBUG" && v2 == "1")
}

test "with_cmd sets container command" {
  let c = DockerContainer::new("img")
    .with_cmd(["echo", "hello"])
  assert(c.cmd().length() == 2)
  assert(c.cmd()[0] == "echo")
  assert(c.cmd()[1] == "hello")
}

test "full builder chain" {
  let c = DockerContainer::new("my-app:1")
    .with_port(3000, 3000)
    .with_env("MODE", "production")
    .with_cmd(["start", "--port", "3000"])
  assert(c.image() == "my-app:1")
  assert(c.ports().length() == 1)
  assert(c.envs().length() == 1)
  assert(c.cmd().length() == 3)
}

// === Preset container factories ===

test "postgres_container preset" {
  let c = postgres_container(15432)
  assert(c.image() == "postgres:16-alpine")
  let (host_pg, container_pg) = c.ports()[0]
  assert(host_pg == 15432 && container_pg == 5432)
  let has_user = c.envs().any(fn((k, _)) { k == "POSTGRES_USER" })
  let has_pass = c.envs().any(fn((k, _)) { k == "POSTGRES_PASSWORD" })
  let has_db = c.envs().any(fn((k, _)) { k == "POSTGRES_DB" })
  assert(has_user && has_pass && has_db)
}

test "redis_container preset" {
  let c = redis_container(16379)
  assert(c.image() == "redis:7-alpine")
  let (host_rd, container_rd) = c.ports()[0]
  assert(host_rd == 16379 && container_rd == 6379)
  assert(c.envs().length() == 0)
}

test "mysql_container preset" {
  let c = mysql_container(13306)
  assert(c.image() == "mysql:8.0")
  let (host_my, container_my) = c.ports()[0]
  assert(host_my == 13306 && container_my == 3306)
  let has_user = c.envs().any(fn((k, _)) { k == "MYSQL_USER" })
  let has_pass = c.envs().any(fn((k, _)) { k == "MYSQL_PASSWORD" })
  let has_db = c.envs().any(fn((k, _)) { k == "MYSQL_DATABASE" })
  let has_root = c.envs().any(fn((k, _)) { k == "MYSQL_ROOT_PASSWORD" })
  assert(has_user && has_pass && has_db && has_root)
}

// === Connection string formatting ===

test "postgres_connection_string format" {
  let s = postgres_connection_string("localhost", 15432)
  assert(s == "postgresql://test_user:test_pass@localhost:15432/test_db")
}

test "postgres_connection_string with remote host" {
  let s = postgres_connection_string("db.example.com", 5432)
  assert(s == "postgresql://test_user:test_pass@db.example.com:5432/test_db")
}

test "redis_address format" {
  let s = redis_address("localhost", 6379)
  assert(s == "localhost:6379")
}

test "mysql_connection_string format" {
  let s = mysql_connection_string("localhost", 3306)
  assert(s == "mysql://test_user:test_pass@localhost:3306/test_db")
}
