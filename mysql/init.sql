-- 创建应用数据库和用户权限设置
CREATE DATABASE IF NOT EXISTS app_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 创建应用用户并授权
GRANT ALL PRIVILEGES ON app_db.* TO 'app_user'@'%' IDENTIFIED BY 'userpassword';

-- 刷新权限
FLUSH PRIVILEGES;