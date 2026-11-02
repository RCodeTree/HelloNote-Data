
-- ==========================================
-- Hello!Note Database Structure — V2
-- Version: V2 (evolution of V1)
-- Database: hello_note
-- MySQL: 8.0+
-- ==========================================
--
-- V2 相对 V1 的唯一结构变更：
--   * notes 表新增 `format` 列（VARCHAR(16)，NOT NULL，默认 'markdown'）
--     用于区分笔记内容格式：markdown（需解析、可预览）/ text（纯文本）。
--
-- 本文件可直接在「已有 V1 库」上整体执行：
--   - 第一段（V1→V2 升级）为活动 SQL，幂等安全，重复运行不会报错；
--   - 第二段（V2 完整建表 SQL）为注释参考，仅供从零建库时对照，执行时不会生效。
--
-- 若需从零初始化 V2 库：请把第二段注释去掉后执行即可。
-- ==========================================


-- ==========================================
-- 第一部分：V1 → V2 升级（在已有 V1 库上执行，幂等）
-- ==========================================

USE hello_note;

-- 仅当列不存在时添加，避免重复执行报错（存量数据由 DEFAULT 'markdown' 自动回填）
SET @has_format = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = 'hello_note'
      AND TABLE_NAME   = 'notes'
      AND COLUMN_NAME  = 'format'
);
SET @sql = IF(
    @has_format = 0,
    "ALTER TABLE notes ADD COLUMN format VARCHAR(16) NOT NULL DEFAULT 'markdown' COMMENT '内容格式：markdown 需解析可预览 / text 纯文本'",
    "SELECT 'notes.format already exists, skip.' AS result"
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ==========================================
-- 第二部分：V2 完整建表 SQL（仅作参考，已注释；从零初始化时去掉注释执行）
-- ==========================================

-- CREATE DATABASE IF NOT EXISTS hello_note
--     CHARACTER SET utf8mb4
--     COLLATE utf8mb4_0900_ai_ci;
--
-- USE hello_note;


-- -- ==========================================
-- -- 1. users
-- -- 用户表
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
-- -- 2. notes
-- -- 笔记表（V2：新增 format 列）
-- -- ==========================================
--
-- CREATE TABLE notes (
--     id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
--
--     user_id BIGINT UNSIGNED NOT NULL,
--
--     title VARCHAR(255) NOT NULL,
--     content LONGTEXT NOT NULL,
--     -- V2 新增：内容格式，markdown 需解析可预览 / text 纯文本
--     format VARCHAR(16) NOT NULL DEFAULT 'markdown',
--
--     is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
--
--     created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
--     updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
--         ON UPDATE CURRENT_TIMESTAMP,
--
--     KEY idx_notes_user_id (user_id),
--     KEY idx_notes_created_at (created_at),
--
--     CONSTRAINT fk_notes_users
--         FOREIGN KEY (user_id)
--         REFERENCES users(id)
--         ON DELETE CASCADE
-- ) ENGINE=InnoDB
--   DEFAULT CHARSET=utf8mb4
--   COLLATE=utf8mb4_0900_ai_ci;
--
--
-- -- ==========================================
-- -- 3. tags
-- -- 标签表
-- -- ==========================================
--
-- CREATE TABLE tags (
--     id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
--
--     user_id BIGINT UNSIGNED NOT NULL,
--
--     name VARCHAR(50) NOT NULL,
--     color VARCHAR(20) NULL,
--
--     created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
--
--     UNIQUE KEY uk_tags_user_name (user_id, name),
--     KEY idx_tags_user_id (user_id),
--
--     CONSTRAINT fk_tags_users
--         FOREIGN KEY (user_id)
--         REFERENCES users(id)
--         ON DELETE CASCADE
-- ) ENGINE=InnoDB
--   DEFAULT CHARSET=utf8mb4
--   COLLATE=utf8mb4_0900_ai_ci;
--
--
-- -- ==========================================
-- -- 4. note_tags
-- -- 笔记标签关联表
-- -- ==========================================
--
-- CREATE TABLE note_tags (
--     note_id BIGINT UNSIGNED NOT NULL,
--     tag_id BIGINT UNSIGNED NOT NULL,
--
--     PRIMARY KEY (note_id, tag_id),
--
--     KEY idx_note_tags_tag_id (tag_id),
--
--     CONSTRAINT fk_note_tags_notes
--         FOREIGN KEY (note_id)
--         REFERENCES notes(id)
--         ON DELETE CASCADE,
--
--     CONSTRAINT fk_note_tags_tags
--         FOREIGN KEY (tag_id)
--         REFERENCES tags(id)
--         ON DELETE CASCADE
-- ) ENGINE=InnoDB
--   DEFAULT CHARSET=utf8mb4
--   COLLATE=utf8mb4_0900_ai_ci;
--
--
-- -- ==========================================
-- -- 5. attachments
-- -- 附件表
-- -- ==========================================
--
-- CREATE TABLE attachments (
--     id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
--
--     note_id BIGINT UNSIGNED NOT NULL,
--
--     original_filename VARCHAR(255) NOT NULL,
--     storage_key VARCHAR(500) NOT NULL,
--     storage_provider VARCHAR(30) NOT NULL DEFAULT 'local',
--
--     mime_type VARCHAR(100) NULL,
--     size_bytes BIGINT UNSIGNED NOT NULL,
--
--     created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
--
--     UNIQUE KEY uk_attachments_storage_key (storage_key),
--     KEY idx_attachments_note_id (note_id),
--
--     CONSTRAINT fk_attachments_notes
--         FOREIGN KEY (note_id)
--         REFERENCES notes(id)
--         ON DELETE CASCADE
-- ) ENGINE=InnoDB
--   DEFAULT CHARSET=utf8mb4
--   COLLATE=utf8mb4_0900_ai_ci;
--
--
-- -- ==========================================
-- -- V2 initialization completed
-- -- ==========================================
