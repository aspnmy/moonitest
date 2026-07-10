/// moonitest 使用示例
/// 运行前提：Linux + Docker daemon + curl

test "postgres container lifecycle" {
  let pg = DockerContainer::new("postgres:16-alpine")
    .with_port(15432, 5432)
    .with_env("POSTGRES_USER", "test")
    .with_env("POSTGRES_PASSWORD", "test")
    .with_env("POSTGRES_DB", "testdb")

  match pg.start() {
    Ok(id) => {
      println("started: " + id)
      match wait_for_port("localhost", 15432, 30000) {
        Ok(_) => println("postgres ready at localhost:15432")
        Err(e) => println("wait error: " + e)
      }
      let _ = stop(id)
      println("stopped: " + id)
    }
    Err(e) => println("docker not available: " + e)
  }
}

test "redis container lifecycle" {
  let r = DockerContainer::new("redis:7-alpine")
    .with_port(16379, 6379)

  match r.start() {
    Ok(id) => {
      println("redis started: " + id)
      let _ = wait_for_port("localhost", 16379, 15000)
      let _ = stop(id)
      println("redis stopped")
    }
    Err(e) => println("docker not available: " + e)
  }
}

test "wait for port timeout" {
  // 等待一个不存在的端口 → 应超时
  let start = now_ms()
  let r = wait_for_port("localhost", 19999, 1000)
  match r {
    Ok(_) => println("unexpected ok")
    Err(e) => println("expected timeout: " + e)
  }
}

test "http get" {
  match http_get("https://httpbin.org/get") {
    Ok(body) => println("got " + body.length().to_string() + " bytes")
    Err(e) => println("http error: " + e)
  }
}
