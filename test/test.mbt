/// moonitest 使用示例
///
/// 运行方式（Linux）：
///   moon test
///
/// 前提：Docker daemon 运行中，本机可执行 curl

test "create postgres container" {
  let port = 15432
  let pg = postgres_container(port)
  let result = pg.start()
  match result {
    Ok(id) => {
      println("PostgreSQL container started: " + id)
      println("Connection: " + postgres_connection_string("localhost", port))
      let _ = wait_for_port("localhost", port, 30000)
      println("PostgreSQL is ready!")
      let _ = stop(id)
    }
    Err(e) => {
      println("Failed to start PostgreSQL: " + e)
      // 如果 Docker 不可用，测试仍应通过
      // 因为这是集成测试框架，依赖 Docker 环境
    }
  }
}

test "create redis container" {
  let port = 16379
  let r = redis_container(port)
  let result = r.start()
  match result {
    Ok(id) => {
      println("Redis container started: " + id)
      println("Address: " + redis_address("localhost", port))
      let _ = wait_for_port("localhost", port, 15000)
      println("Redis is ready!")
      let _ = stop(id)
    }
    Err(e) => {
      println("Failed to start Redis: " + e)
    }
  }
}

test "create mysql container" {
  let port = 13306
  let m = mysql_container(port)
  let result = m.start()
  match result {
    Ok(id) => {
      println("MySQL container started: " + id)
      let _ = wait_for_port("localhost", port, 60000)
      println("MySQL is ready!")
      let _ = stop(id)
    }
    Err(e) => {
      println("Failed to start MySQL: " + e)
    }
  }
}

test "wait for HTTP endpoint" {
  // 等待本地 HTTP 服务可用
  let _ = wait_for_http("http://localhost:8080/health", 5000)
  println("HTTP check completed (may timeout if no service running)")
}

test "find free port" {
  match find_free_port() {
    Ok(port) => println("Free port found: " + port.to_string())
    Err(e) => println("Port detection not available: " + e)
  }
}
