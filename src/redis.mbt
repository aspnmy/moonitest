/// Redis 测试容器预设。
///
/// - 镜像: `redis:7-alpine`
/// - 无认证（预设环境变量为空）

/// 创建一个 Redis 测试容器。
///
/// 参数：
/// - `port`: 宿主机映射端口（映射到容器 6379）
///
/// 示例：
/// ```moonbit
/// let redis = redis_container(16379)
/// ```
pub fn redis_container(port: Int) -> DockerContainer {
  DockerContainer::new("redis:7-alpine")
    .with_port(port, 6379)
}

/// 获取 Redis 连接地址。
///
/// 返回格式：`{host}:{port}`
///
/// 示例：
/// ```moonbit
/// let addr = redis_address("localhost", 6379)
/// // → "localhost:6379"
/// ```
pub fn redis_address(host: String, port: Int) -> String {
  host + ":" + port.to_string()
}
