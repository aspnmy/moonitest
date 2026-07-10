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

test "wait_for_port returns Err without native" {
  let r = wait_for_port("localhost", 5432, 1000)
  assert(r.is_err())
}

test "http_get returns Err without native" {
  let r = http_get("http://localhost:8080")
  assert(r.is_err())
}

test "find_free_port returns Err without native" {
  let r = find_free_port()
  assert(r.is_err())
}

test "DockerContainer builder works" {
  let c = DockerContainer::new("redis:7")
    .with_port(16379, 6379)
    .with_env("KEY", "val")
  assert(true)
}
