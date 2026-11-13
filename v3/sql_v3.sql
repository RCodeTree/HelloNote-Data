
-- ==========================================
-- Hello!Note Database Structure — V3
-- Version: V3 (evolution of V2)
-- Database: hello_note
-- MySQL: 8.0+
-- ==========================================
--
-- V3 相对 V2 的唯一结构变更：
--   * 新增 `user_activity` 表（用户每日活跃度记录）
--     按 (user_id, stat_date) 唯一，累计记录每日：
--       - notes_created / notes_updated / notes_deleted：当日笔记 新增/修改/删除 次数（活跃点数）
--       - active_seconds：当日应用内活跃时长（秒，由前端心跳上报累加）
--     用于支撑「面板」新增的：日历、GitHub 风格活跃度热力图、活动时长统计。
--   * V3 不改动 V2 的 users / notes / tags / note_tags / attachments 五张表，
--     因此升级段只有「建表 + 回填」，没有 ALTER TABLE。
--
-- 为什么需要新表：
--   V1/V2 的 `notes` 是硬删除且只保留当前状态，`updated_at` 会被覆盖，
--   无法反推「历史某日的修改/删除次数」，也无法记录「停留时长」。
--   因此活跃度必须在写操作发生时按「业务日」累加落库，而非事后实时聚合。
--
-- 本文件可直接在「已有 V2 库」上整体执行：
--   - 第一部分（V2→V3 更新 SQL）为活动 SQL，幂等安全，重复运行不会报错；
--   - 第二部分（V3 完整建表 SQL）为注释参考，包含 V3 全部 6 张表，执行时不会生效。
--
-- 若需从零初始化 V3 库：请把第二部分注释去掉后执行即可（无需再跑 v1/v2）。
-- ==========================================


-- ==========================================
-- 第一部分：V2 → V3 更新 SQL（在已有 V2 库上执行，幂等）
-- ==========================================

USE hello_note;

-- 1.1 建表：user_activity（每日一行，唯一键保证并发累加落点唯一）
CREATE TABLE IF NOT EXISTS user_activity (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,

    user_id BIGINT UNSIGNED NOT NULL,
    stat_date DATE NOT NULL COMMENT '业务日（Asia/Shanghai），后端统一计算',

    notes_created INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '当日新增笔记次数',
    notes_updated INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '当日修改笔记次数（含置顶切换）',
    notes_deleted INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '当日删除笔记次数',
    active_seconds INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '当日应用内活跃时长（秒）',

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uk_user_activity_user_date (user_id, stat_date),
    KEY idx_user_activity_date (stat_date),

    CONSTRAINT fk_user_activity_users
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE CASCADE
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_0900_ai_ci
  COMMENT='用户每日活跃度（增/改/删点数 + 活跃时长）';


-- 1.2 历史数据回填（一次性、幂等）：把存量笔记按「创建日」聚合点亮热力图。
--     - 仅能反推「新增」；历史「修改/删除/时长」无法还原，保持 0（见 doc.md）。
--     - INSERT IGNORE：若该 (user_id, stat_date) 已有实时埋点记录则跳过，不覆盖真实累计值；
--       重复执行整段脚本也不会重复叠加。
INSERT IGNORE INTO user_activity
    (user_id, stat_date, notes_created, notes_updated, notes_deleted, active_seconds, created_at, updated_at)
SELECT
    n.user_id,
    DATE(n.created_at) AS stat_date,
    COUNT(*)           AS notes_created,
    0, 0, 0,
    NOW(), NOW()
FROM notes n
GROUP BY n.user_id, DATE(n.created_at);


-- ==========================================
-- 第二部分：V3 完整建表 SQL（仅作参考，已注释；从零初始化时去掉注释执行）
-- ==========================================
-- 说明：以下为 V3 最终结构的全部 6 张表（users / notes / tags / note_tags /
--       attachments / user_activity），按外键依赖顺序排列，含 V2 的 notes.format。
--       从零建库时整段去掉行首 `-- ` 执行即可；此时没有存量笔记，无需 1.2 回填。
--
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
-- -- 笔记表（沿用 V2：含 format 列）
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
-- -- 6. user_activity
-- -- 用户每日活跃度（V3 新增：增/改/删点数 + 活跃时长）
-- -- ==========================================
--
-- CREATE TABLE user_activity (
--     id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
--
--     user_id BIGINT UNSIGNED NOT NULL,
--     stat_date DATE NOT NULL COMMENT '业务日（Asia/Shanghai），后端统一计算',
--
--     notes_created INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '当日新增笔记次数',
--     notes_updated INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '当日修改笔记次数（含置顶切换）',
--     notes_deleted INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '当日删除笔记次数',
--     active_seconds INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '当日应用内活跃时长（秒）',
--
--     created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
--     updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
--         ON UPDATE CURRENT_TIMESTAMP,
--
--     UNIQUE KEY uk_user_activity_user_date (user_id, stat_date),
--     KEY idx_user_activity_date (stat_date),
--
--     CONSTRAINT fk_user_activity_users
--         FOREIGN KEY (user_id)
--         REFERENCES users(id)
--         ON DELETE CASCADE
-- ) ENGINE=InnoDB
--   DEFAULT CHARSET=utf8mb4
--   COLLATE=utf8mb4_0900_ai_ci
--   COMMENT='用户每日活跃度（增/改/删点数 + 活跃时长）';
--
--
-- -- ==========================================
-- -- V3 initialization completed
-- -- ==========================================
