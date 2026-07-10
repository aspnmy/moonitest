test "start returns Err without Docker" {
  let r = DockerContainer::new("redis:7").start()
  if r.is_ok() { fail() }
}

test "builder works" {
  let c = DockerContainer::new("redis:7")
    .with_port(16379, 6379)
    .with_env("KEY", "val")
  if c.ports.length() != 1 { fail() }
}

test "wait_for_port returns Err" {
  let r = wait_for_port("localhost", 1, 1)
  if r.is_ok() { fail() }
}

test "http_get returns Err" {
  let r = http_get("http://x")
  if r.is_ok() { fail() }
}

fn fail() {
  panic("assertion failed")
}
