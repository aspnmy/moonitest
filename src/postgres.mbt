/// PostgreSQL 测试容器
/// 预设：用户 test_user，密码 test_pass，数据库 test_db

/// 创建 PostgreSQL 测试容器
pub fn postgres_container(port: Int) -> DockerContainer {
  DockerContainer::new("postgres:16-alpine")
    .with_port(port, 5432)
    .with_env("POSTGRES_USER", "test_user")
    .with_env("POSTGRES_PASSWORD", "test_pass")
    .with_env("POSTGRES_DB", "test_db")
}

/// 获取 PostgreSQL 连接字符串
pub fn postgres_connection_string(host: String, port: Int) -> String {
  "postgresql://test_user:test_pass@" + host + ":" + port.to_string() + "/test_db"
}
