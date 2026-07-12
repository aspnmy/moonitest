/// MySQL 测试容器预设。
///
/// 预设凭证：
/// - 用户: `test_user`
/// - 密码: `test_pass`
/// - 数据库: `test_db`
/// - Root 密码: `root_pass`
/// - 镜像: `mysql:8.0`

/// 创建一个 MySQL 测试容器。
///
/// 参数：
/// - `port`: 宿主机映射端口（映射到容器 3306）
///
/// 示例：
/// ```moonbit
/// let mysql = mysql_container(13306)
/// ```
pub fn mysql_container(port: Int) -> DockerContainer {
  DockerContainer::new("mysql:8.0")
    .with_port(port, 3306)
    .with_env("MYSQL_USER", "test_user")
    .with_env("MYSQL_PASSWORD", "test_pass")
    .with_env("MYSQL_DATABASE", "test_db")
    .with_env("MYSQL_ROOT_PASSWORD", "root_pass")
}

/// 获取 MySQL 连接字符串。
///
/// 返回格式：`mysql://test_user:test_pass@{host}:{port}/test_db`
///
/// 示例：
/// ```moonbit
/// let conn = mysql_connection_string("localhost", 3306)
/// // → "mysql://test_user:test_pass@localhost:3306/test_db"
/// ```
pub fn mysql_connection_string(host: String, port: Int) -> String {
  "mysql://test_user:test_pass@" + host + ":" + port.to_string() + "/test_db"
}
