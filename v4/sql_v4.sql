
-- ==========================================
-- Hello!Note Database Structure — V4
-- Version: V4 (evolution of V3)
-- Database: hello_note
-- MySQL: 8.0+
-- ==========================================
--
-- V4 相对 V3 的唯一结构变更：
--   * users 表新增 `bio VARCHAR(500) NULL COMMENT '个人简介'`
--     用于支撑「个人中心」的自我介绍展示与编辑（PATCH /api/v1/auth/me）。
--   * V4 不改动 V3 的 notes / tags / note_tags / attachments / user_activity 五张表，
--     因此升级段只有一条针对 users 的 ALTER TABLE（幂等封装）。
--
-- 幂等说明：
--   MySQL 8.0 不支持 `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`，
--   因此用「存储过程 + information_schema.COLUMNS 判断」包装，重复执行不会报错。
--   存储过程的 DELIMITER 是 mysql 客户端指令，请用 `mysql -u root -p < sql_v4.sql`
--   或任意支持 DELIMITER 的 MySQL 客户端整体执行本文件。
--
-- 本文件可直接在「已有 V3 库」上整体执行：
--   - 第一部分（V3→V4 更新 SQL）：幂等加列，重复运行安全；
--   - 第二部分（V4 完整 users 表结构）：仅作注释参考，执行时不会生效。
--
-- 若需从零初始化 V4 库：把第二部分 users 建表注释去掉执行即可（其余表沿用 V3）。
-- ==========================================


-- ==========================================
-- 第一部分：V3 → V4 更新 SQL（在已有 V3 库上执行，幂等）
-- ==========================================

USE hello_note;

-- 1.1 给 users 增加 bio 列（存在则跳过；可反复执行）
DROP PROCEDURE IF EXISTS sp_v4_add_users_bio;

DELIMITER $$
CREATE PROCEDURE sp_v4_add_users_bio()
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'users'
          AND COLUMN_NAME = 'bio'
    ) THEN
        ALTER TABLE users
            ADD COLUMN bio VARCHAR(500) NULL COMMENT '个人简介';
    END IF;
END$$
DELIMITER ;

CALL sp_v4_add_users_bio();

DROP PROCEDURE IF EXISTS sp_v4_add_users_bio;


-- ==========================================
-- 第二部分：V4 完整 users 表结构（仅作参考，已注释；从零初始化时去掉注释执行）
-- ==========================================
-- 说明：以下为 V4 最终 users 表结构，相比 V3 仅多一列 bio。
--       从零建库时去掉行首 `-- ` 执行；其余表（notes / tags / note_tags /
--       attachments / user_activity）沿用 sql/v3/sql_v3.sql 的定义。
--
-- -- ==========================================
-- -- 1. users
-- -- 用户表（V4 新增 bio 个人简介）
-- -- ==========================================
--
-- CREATE TABLE users (
--     id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
--
--     email VARCHAR(255) NOT NULL,
--     password_hash VARCHAR(255) NOT NULL,
--     display_name VARCHAR(100) NOT NULL,
--     username VARCHAR(50) NOT NULL,
--     avatar_url VARCHAR(500) NULL,
--     -- V4 新增：个人简介（最大 500 字符，可为空）
--     bio VARCHAR(500) NULL COMMENT '个人简介',
--
--     is_active BOOLEAN NOT NULL DEFAULT TRUE,
--
--     created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
--     updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
--         ON UPDATE CURRENT_TIMESTAMP,
--
--     UNIQUE KEY uk_users_username (username),
--     UNIQUE KEY uk_users_email (email)
-- ) ENGINE=InnoDB
--   DEFAULT CHARSET=utf8mb4
--   COLLATE=utf8mb4_0900_ai_ci;
--
--
-- -- ==========================================
-- -- V4 initialization completed
-- -- ==========================================
