/// PostgreSQL 测试容器预设。
///
/// 预设凭证：
/// - 用户: `test_user`
/// - 密码: `test_pass`
/// - 数据库: `test_db`
/// - 镜像: `postgres:16-alpine`

/// 创建一个 PostgreSQL 测试容器。
///
/// 参数：
/// - `port`: 宿主机映射端口（映射到容器 5432）
///
/// 示例：
/// ```moonbit
/// let pg = postgres_container(15432)
/// ```
pub fn postgres_container(port: Int) -> DockerContainer {
  DockerContainer::new("postgres:16-alpine")
    .with_port(port, 5432)
    .with_env("POSTGRES_USER", "test_user")
    .with_env("POSTGRES_PASSWORD", "test_pass")
    .with_env("POSTGRES_DB", "test_db")
}

/// 获取 PostgreSQL 连接字符串。
///
/// 返回格式：`postgresql://test_user:test_pass@{host}:{port}/test_db`
///
/// 示例：
/// ```moonbit
/// let conn = postgres_connection_string("localhost", 15432)
/// // → "postgresql://test_user:test_pass@localhost:15432/test_db"
/// ```
pub fn postgres_connection_string(host: String, port: Int) -> String {
  "postgresql://test_user:test_pass@" + host + ":" + port.to_string() + "/test_db"
}
