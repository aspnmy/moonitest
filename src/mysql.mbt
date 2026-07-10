/// MySQL 测试容器
/// 预设：用户 test_user，密码 test_pass，数据库 test_db

/// 创建 MySQL 测试容器
pub fn mysql_container(port: Int) -> DockerContainer {
  DockerContainer::new("mysql:8.0")
    .with_port(port, 3306)
    .with_env("MYSQL_USER", "test_user")
    .with_env("MYSQL_PASSWORD", "test_pass")
    .with_env("MYSQL_DATABASE", "test_db")
    .with_env("MYSQL_ROOT_PASSWORD", "root_pass")
}

/// 获取 MySQL 连接字符串
pub fn mysql_connection_string(host: String, port: Int) -> String {
  "mysql://test_user:test_pass@" + host + ":" + port.to_string() + "/test_db"
}
