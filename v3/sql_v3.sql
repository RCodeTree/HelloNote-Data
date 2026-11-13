
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
--
-- 为什么需要新表：
--   V1/V2 的 `notes` 是硬删除且只保留当前状态，`updated_at` 会被覆盖，
--   无法反推「历史某日的修改/删除次数」，也无法记录「停留时长」。
--   因此活跃度必须在写操作发生时按「业务日」累加落库，而非事后实时聚合。
--
-- 本文件可直接、重复在「已有 V2 库」上执行（幂等）：
--   - 第一部分：V2→V3 升级（建表 + 历史回填），幂等安全；
--   - 第二部分：V3 完整建表 SQL（注释参考，供从零建库对照）。
-- ==========================================

USE hello_note;


-- ==========================================
-- 第一部分：V2 → V3 升级（幂等，可重复执行）
-- ==========================================

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
-- 说明：从零建库请先执行 `sql/v1/sql_v1.sql`，再执行 `sql/v2/sql_v2.sql`
--       （或直接以 V2 的注释版完整建表为准），最后执行本文件「第一部分」。
--       以下仅给出 V3 新增表的完整定义，便于对照，无需执行。
--
-- CREATE TABLE user_activity (
--     id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
--     user_id BIGINT UNSIGNED NOT NULL,
--     stat_date DATE NOT NULL COMMENT '业务日（Asia/Shanghai）',
--     notes_created INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '当日新增笔记次数',
--     notes_updated INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '当日修改笔记次数',
--     notes_deleted INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '当日删除笔记次数',
--     active_seconds INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '当日活跃时长（秒）',
--     created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
--     updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
--     UNIQUE KEY uk_user_activity_user_date (user_id, stat_date),
--     KEY idx_user_activity_date (stat_date),
--     CONSTRAINT fk_user_activity_users FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
-- ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
--
-- -- ==========================================
-- -- V3 initialization completed
-- -- ==========================================
