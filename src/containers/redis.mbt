/// Redis 测试容器

/// 创建 Redis 测试容器
pub fn redis_container(port: Int) -> DockerContainer {
  DockerContainer::new("redis:7-alpine")
    .with_port(port, 6379)
}

/// 获取 Redis 连接地址
pub fn redis_address(host: String, port: Int) -> String {
  host + ":" + port.to_string()
}
