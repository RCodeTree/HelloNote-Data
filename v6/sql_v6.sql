-- ==========================================
-- Hello!Note Database Structure — V6
-- Version: V6 (evolution of V5)
-- Database: hello_note
-- MySQL: 8.0+
-- Charset: utf8mb4 / utf8mb4_0900_ai_ci
-- Engine: InnoDB
-- ==========================================
--
-- 【版本演进总览】
--   V1 (sql/v1/sql_v1.sql)
--     初始建库，5 张表：users / notes / tags / note_tags / attachments。
--   V2 (sql/v2/sql_v2.sql)
--     notes 新增 format VARCHAR(16) NOT NULL DEFAULT 'markdown'
--     （markdown 需解析可预览 / text 纯文本），其余 4 张表不变。
--   V3 (sql/v3/sql_v3.sql)
--     新增 user_activity 表（用户每日活跃度：增/改/删点数 + 活跃时长），
--     支撑「面板」的日历 / 热力图 / 活动时长统计；其余 5 张表不变。
--   V4 (sql/v4/sql_v4.sql)
--     users 新增 bio VARCHAR(500) NULL COMMENT '个人简介'，
--     支撑「个人中心」的自我介绍展示与编辑（PATCH /api/v1/auth/me）；
--     其余 5 张表不变。
--   V5 (sql/v5/sql_v5.sql)
--     新增 5 张表，支撑「笔记评论/点赞、笔友、聊天」三大社交功能：
--       1. note_comments   笔记评论（支持 parent_id 自关联，楼中楼回复）
--       2. note_likes      笔记点赞（(note_id,user_id) 唯一，一人一赞）
--       3. friendships     笔友关系（requester→addressee，pending/accepted）
--       4. conversations   聊天会话（user_low_id/user_high_id 归一化，A-B 唯一）
--       5. messages        聊天消息（归属会话，含已读标记）
--     至此共 11 张表；V5 不改动 V1~V4 的 6 张表结构。
--   V6 (本文件)
--     在「好友/笔友」与「社交互动」上做结构增强，共两类变更：
--       1. 给 V5 已有的 friendships 表新增 4 列，丰富好友档案维度：
--            note          好友备注
--            privacy       隐私设置（all/friends/hidden）
--            relation_type 关系类别
--            closeness     关系程度（acquaintance/friend/close/intimate）
--       2. 新建 notifications 表，统一承载系统 / 评论 / 点赞 /
--          好友申请 / 好友接受等消息通知（含已读标记与触发者）。
--     至此共 12 张表；V6 不改动其它既有表结构。
--
-- 【V6 变更说明】
--   * 4 条 ALTER TABLE ... ADD COLUMN 全部带 DEFAULT / NULL 约束，
--     存量数据由默认值自动回填，无需人工刷数：
--       - note          VARCHAR(100) NULL                     → 存量行值为 NULL
--       - privacy       VARCHAR(16)  NOT NULL DEFAULT 'all'   → 存量行回填 'all'
--       - relation_type VARCHAR(32) NOT NULL DEFAULT 'friend' → 存量行回填 'friend'
--       - closeness     VARCHAR(16) NOT NULL DEFAULT 'friend' → 存量行回填 'friend'
--   * notifications 为全新建表，初始为空表，无需回填；旧的登录 / 笔记 /
--     面板 / 个人中心 / 评论 / 点赞 / 笔友 / 聊天功能均不受影响。
--   * notifications 的 user_id 是被通知人（ON DELETE CASCADE），
--     actor_id 是触发人（ON DELETE SET NULL），二者都指向 users(id)。
--
-- 【幂等说明】
--   本文件第一部分可反复执行，天然幂等：
--     1. 加列：MySQL 8.0 不支持 ADD COLUMN IF NOT EXISTS。
--        采用 information_schema.COLUMNS 判断列是否存在，配合
--        SET @has_xxx + SET @sql + PREPARE/EXECUTE/DEALLOCATE 动态 SQL：
--        列不存在才 ALTER，已存在则执行一条无害的 SELECT 跳过。
--     2. 建表：notifications 使用 CREATE TABLE IF NOT EXISTS，
--        表已存在则整条语句被 MySQL 跳过，不重复建索引 / 外键。
--   因此第一部分无需 DELIMITER / 存储过程，任何 MySQL 客户端均可整体执行。
--
-- 【文件结构】
--   第一部分：V5 → V6 升级 SQL（活动 SQL，直接在已有 V5 库上执行，幂等）。
--   第二部分：V6 从零初始化「全部 12 张表」的完整语句（已注释，
--             新库使用时整段去掉行首 `-- ` 执行即可，无需再跑 v1~v5）。
--   第三部分：升级后的验证查询（注释，可选执行）。
--
-- 【执行方式】
--   升级已有库：  mysql -u root -p < sql_v6.sql
--   从零初始化：  复制第二部分、去掉每行行首的 `-- ` 后执行；
--                 或按顺序执行 v1 → v2 → v3 → v4 → v5 → v6（v6 只需第一部分）。
--   说明：本文件第一部分不含 DELIMITER / 存储过程，任何 MySQL 客户端均可整体执行。
-- ==========================================


-- ==========================================
-- 第一部分：V5 → V6 升级 SQL（在已有 V5 库上执行，幂等）
-- ==========================================

USE hello_note;

-- ------------------------------------------
-- 1.1 friendships 新增 4 列（逐列判断，存在则跳过）
--     采用 @has_xxx + PREPARE 动态 SQL 封装，可重复执行。
-- ------------------------------------------

-- 1.1.1 note 好友备注（VARCHAR(100) NULL）
SET @has_friend_note = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = 'hello_note'
      AND TABLE_NAME   = 'friendships'
      AND COLUMN_NAME  = 'note'
);
SET @sql = IF(
    @has_friend_note = 0,
    "ALTER TABLE friendships ADD COLUMN note VARCHAR(100) NULL COMMENT '好友备注'",
    "SELECT 'friendships.note already exists, skip.' AS result"
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 1.1.2 privacy 隐私设置（all/friends/hidden）
SET @has_friend_privacy = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = 'hello_note'
      AND TABLE_NAME   = 'friendships'
      AND COLUMN_NAME  = 'privacy'
);
SET @sql = IF(
    @has_friend_privacy = 0,
    "ALTER TABLE friendships ADD COLUMN privacy VARCHAR(16) NOT NULL DEFAULT 'all' COMMENT '隐私设置：all/friends/hidden'",
    "SELECT 'friendships.privacy already exists, skip.' AS result"
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 1.1.3 relation_type 关系类别
SET @has_friend_relation_type = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = 'hello_note'
      AND TABLE_NAME   = 'friendships'
      AND COLUMN_NAME  = 'relation_type'
);
SET @sql = IF(
    @has_friend_relation_type = 0,
    "ALTER TABLE friendships ADD COLUMN relation_type VARCHAR(32) NOT NULL DEFAULT 'friend' COMMENT '关系类别'",
    "SELECT 'friendships.relation_type already exists, skip.' AS result"
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 1.1.4 closeness 关系程度（acquaintance/friend/close/intimate）
SET @has_friend_closeness = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = 'hello_note'
      AND TABLE_NAME   = 'friendships'
      AND COLUMN_NAME  = 'closeness'
);
SET @sql = IF(
    @has_friend_closeness = 0,
    "ALTER TABLE friendships ADD COLUMN closeness VARCHAR(16) NOT NULL DEFAULT 'friend' COMMENT '关系程度：acquaintance/friend/close/intimate'",
    "SELECT 'friendships.closeness already exists, skip.' AS result"
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ------------------------------------------
-- 1.2 建表：notifications 通知表（依赖 users 已存在）
--     使用 CREATE TABLE IF NOT EXISTS，天然幂等。
-- ------------------------------------------
CREATE TABLE IF NOT EXISTS notifications (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT '通知 ID（自增主键）',

    -- 被通知人（通知的接收方）
    user_id BIGINT UNSIGNED NOT NULL COMMENT '接收通知的用户 ID',
    -- 通知类型：system/comment/like/friend_request/friend_accept
    type VARCHAR(24) NOT NULL COMMENT '通知类型：system/comment/like/friend_request/friend_accept',
    -- 触发人（可为 NULL：system 通知无触发人；用户被删时置 NULL）
    actor_id BIGINT UNSIGNED NULL COMMENT '触发通知的用户 ID（NULL 表示系统）',
    content VARCHAR(500) NOT NULL COMMENT '通知内容（最大 500 字符）',
    -- 关联业务对象 ID（评论 / 点赞 / 好友申请等），可为 NULL
    related_id BIGINT UNSIGNED NULL COMMENT '关联业务对象 ID',
    is_read BOOLEAN NOT NULL DEFAULT FALSE COMMENT '是否已读',

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',

    KEY idx_notif_user_read (user_id, is_read),
    KEY idx_notif_created (created_at),

    CONSTRAINT fk_notif_user
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_notif_actor
        FOREIGN KEY (actor_id)
        REFERENCES users(id)
        ON DELETE SET NULL
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_0900_ai_ci
  COMMENT='通知表（系统/评论/点赞/好友申请/好友接受）';


-- ==========================================
-- 第一部分结束：V5 → V6 升级完成（4 新列 + 1 新表全部就绪）
-- ==========================================


-- ==========================================
-- 第二部分：V6 从零初始化全部表（仅作参考，已注释）
-- ==========================================
-- 说明：以下是 V6 最终结构的全部 12 张表，按外键依赖顺序排列：
--        1. users          用户（V4 最终结构，含 bio）
--        2. notes          笔记（V2 最终结构，含 format）
--        3. tags           标签
--        4. note_tags      笔记-标签关联
--        5. attachments    附件
--        6. user_activity  每日活跃度（V3 新增）
--        7. note_comments  笔记评论（V5 新增）
--        8. note_likes     笔记点赞（V5 新增）
--        9. friendships    笔友关系（V5 新增；V6 增加 4 列）
--       10. conversations  聊天会话（V5 新增）
--       11. messages       聊天消息（V5 新增，依赖 conversations）
--       12. notifications  通知（V6 新增，依赖 users）
--       依赖层级：users → notes/tags/friendships/conversations/notifications
--                 → note_tags/attachments/user_activity/note_comments/note_likes/messages。
--       从零建库时整段去掉行首 `-- ` 执行即可；此时无存量数据，无需任何回填。
--       各字段的 COMMENT 与 ORM 模型 / API schema 一一对应。
--
-- CREATE DATABASE IF NOT EXISTS hello_note
--     CHARACTER SET utf8mb4
--     COLLATE utf8mb4_0900_ai_ci;
--
-- USE hello_note;
--
--
-- -- ==========================================
-- -- 1. users  用户表
-- --    V1 建表；V4 新增 bio 列（此处为 V4 最终结构）。
-- --    密码只存 hash，永不存明文。
-- -- ==========================================
--
-- CREATE TABLE users (
--     id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT '用户 ID（自增主键）',
--
--     email VARCHAR(255) NOT NULL COMMENT '邮箱，唯一，可用于登录',
--     password_hash VARCHAR(255) NOT NULL COMMENT '密码哈希（bcrypt / passlib），不存明文',
--     display_name VARCHAR(100) NOT NULL COMMENT '昵称，个人中心可修改',
--     username VARCHAR(50) NOT NULL COMMENT '用户名，唯一，注册后不可修改',
--     avatar_url VARCHAR(500) NULL COMMENT '头像地址：emoji / 外链 / 本地 /uploads/avatars/*',
--     -- V4 新增：个人简介（最大 500 字符，NULL 表示未填写）
--     bio VARCHAR(500) NULL COMMENT '个人简介',
--
--     is_active BOOLEAN NOT NULL DEFAULT TRUE COMMENT '账号启用状态',
--
--     created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
--     updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
--         ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
--
--     UNIQUE KEY uk_users_username (username),
--     UNIQUE KEY uk_users_email (email)
-- ) ENGINE=InnoDB
--   DEFAULT CHARSET=utf8mb4
--   COLLATE=utf8mb4_0900_ai_ci
--   COMMENT='用户表';
--
--
-- -- ==========================================
-- -- 2. notes  笔记表（V2 最终结构，含 format）
-- --    V1 建表；V2 新增 format 列。
-- --    硬删除：删除后不保留记录，历史活跃度由 user_activity 独立累计。
-- -- ==========================================
--
-- CREATE TABLE notes (
--     id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT '笔记 ID',
--
--     user_id BIGINT UNSIGNED NOT NULL COMMENT '所属用户 ID',
--
--     title VARCHAR(255) NOT NULL COMMENT '标题',
--     content LONGTEXT NOT NULL COMMENT '正文（markdown 或纯文本）',
--     -- V2 新增：内容格式，markdown 需解析可预览 / text 纯文本
--     format VARCHAR(16) NOT NULL DEFAULT 'markdown' COMMENT '内容格式：markdown / text',
--
--     is_pinned BOOLEAN NOT NULL DEFAULT FALSE COMMENT '是否置顶',
--
--     created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
--     updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
--         ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
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
--   COLLATE=utf8mb4_0900_ai_ci
--   COMMENT='笔记表';
--
--
-- -- ==========================================
-- -- 3. tags  标签表
-- --    V1 建表，沿用至今；每个用户自己的标签名唯一。
-- -- ==========================================
--
-- CREATE TABLE tags (
--     id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT '标签 ID',
--
--     user_id BIGINT UNSIGNED NOT NULL COMMENT '所属用户 ID',
--
--     name VARCHAR(50) NOT NULL COMMENT '标签名（同用户内唯一）',
--     color VARCHAR(20) NULL COMMENT '标签颜色（如 #9A8052）',
--
--     created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
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
--   COLLATE=utf8mb4_0900_ai_ci
--   COMMENT='标签表';
--
--
-- -- ==========================================
-- -- 4. note_tags  笔记-标签关联表（多对多）
-- --    V1 建表，沿用至今；联合主键防止重复关联。
-- -- ==========================================
--
-- CREATE TABLE note_tags (
--     note_id BIGINT UNSIGNED NOT NULL COMMENT '笔记 ID',
--     tag_id BIGINT UNSIGNED NOT NULL COMMENT '标签 ID',
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
--   COLLATE=utf8mb4_0900_ai_ci
--   COMMENT='笔记-标签关联表';
--
--
-- -- ==========================================
-- -- 5. attachments  附件表
-- --    V1 建表，沿用至今；storage_key 全局唯一。
-- -- ==========================================
--
-- CREATE TABLE attachments (
--     id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT '附件 ID',
--
--     note_id BIGINT UNSIGNED NOT NULL COMMENT '所属笔记 ID',
--
--     original_filename VARCHAR(255) NOT NULL COMMENT '原始文件名',
--     storage_key VARCHAR(500) NOT NULL COMMENT '存储键（全局唯一）',
--     storage_provider VARCHAR(30) NOT NULL DEFAULT 'local' COMMENT '存储提供方：local 等',
--
--     mime_type VARCHAR(100) NULL COMMENT 'MIME 类型',
--     size_bytes BIGINT UNSIGNED NOT NULL COMMENT '文件字节数',
--
--     created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
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
--   COLLATE=utf8mb4_0900_ai_ci
--   COMMENT='附件表';
--
--
-- -- ==========================================
-- -- 6. user_activity  用户每日活跃度（V3 新增）
-- --    按 (user_id, stat_date) 唯一，写操作时按「业务日」累加，
-- --    支撑面板的日历 / GitHub 风格热力图 / 活动时长统计。
-- --    业务日由后端按固定 UTC+8 偏移计算（不依赖系统 tzdata）。
-- -- ==========================================
--
-- CREATE TABLE user_activity (
--     id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT '记录 ID',
--
--     user_id BIGINT UNSIGNED NOT NULL COMMENT '用户 ID',
--     stat_date DATE NOT NULL COMMENT '业务日（Asia/Shanghai），后端统一计算',
--
--     notes_created INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '当日新增笔记次数',
--     notes_updated INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '当日修改笔记次数（含置顶切换）',
--     notes_deleted INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '当日删除笔记次数',
--     active_seconds INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '当日应用内活跃时长（秒）',
--
--     created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
--     updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
--         ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
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
-- -- 7. note_comments  笔记评论表（V5 新增）
-- --    parent_id 自关联实现楼中楼；NULL 表示顶层评论。
-- -- ==========================================
--
-- CREATE TABLE note_comments (
--     id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT '评论 ID（自增主键）',
--
--     note_id BIGINT UNSIGNED NOT NULL COMMENT '所属笔记 ID',
--     user_id BIGINT UNSIGNED NOT NULL COMMENT '评论用户 ID',
--     -- NULL 表示顶层评论；非 NULL 指向父评论，实现楼中楼回复
--     parent_id BIGINT UNSIGNED NULL COMMENT '父评论 ID（NULL 表示顶层评论）',
--     content VARCHAR(1000) NOT NULL COMMENT '评论内容（最大 1000 字符）',
--
--     created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
--     updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
--         ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
--
--     KEY idx_nc_note (note_id),
--     KEY idx_nc_user (user_id),
--     KEY idx_nc_parent (parent_id),
--
--     CONSTRAINT fk_nc_notes
--         FOREIGN KEY (note_id)
--         REFERENCES notes(id)
--         ON DELETE CASCADE,
--
--     CONSTRAINT fk_nc_users
--         FOREIGN KEY (user_id)
--         REFERENCES users(id)
--         ON DELETE CASCADE,
--
--     CONSTRAINT fk_nc_parent
--         FOREIGN KEY (parent_id)
--         REFERENCES note_comments(id)
--         ON DELETE CASCADE
-- ) ENGINE=InnoDB
--   DEFAULT CHARSET=utf8mb4
--   COLLATE=utf8mb4_0900_ai_ci
--   COMMENT='笔记评论表（支持自关联回复）';
--
--
-- -- ==========================================
-- -- 8. note_likes  笔记点赞表（V5 新增）
-- --    (note_id,user_id) 联合唯一，保证一人一赞。
-- -- ==========================================
--
-- CREATE TABLE note_likes (
--     id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT '点赞 ID（自增主键）',
--
--     note_id BIGINT UNSIGNED NOT NULL COMMENT '被点赞笔记 ID',
--     user_id BIGINT UNSIGNED NOT NULL COMMENT '点赞用户 ID',
--
--     created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
--
--     UNIQUE KEY uk_note_like (note_id, user_id),
--     KEY idx_nl_user (user_id),
--
--     CONSTRAINT fk_nl_notes
--         FOREIGN KEY (note_id)
--         REFERENCES notes(id)
--         ON DELETE CASCADE,
--
--     CONSTRAINT fk_nl_users
--         FOREIGN KEY (user_id)
--         REFERENCES users(id)
--         ON DELETE CASCADE
-- ) ENGINE=InnoDB
--   DEFAULT CHARSET=utf8mb4
--   COLLATE=utf8mb4_0900_ai_ci
--   COMMENT='笔记点赞表（一人一赞）';
--
--
-- -- ==========================================
-- -- 9. friendships  笔友关系表（V5 新增；V6 增加 4 列）
-- --    requester → addressee；status: pending/accepted。
-- --    联合唯一键保证同一方向的好友请求只有一条。
-- --    V6 新增：note / privacy / relation_type / closeness 四个好友档案字段，
-- --    均由默认值回填存量数据，不改动既有列。
-- -- ==========================================
--
-- CREATE TABLE friendships (
--     id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT '关系 ID（自增主键）',
--
--     requester_id BIGINT UNSIGNED NOT NULL COMMENT '发起方用户 ID',
--     addressee_id BIGINT UNSIGNED NOT NULL COMMENT '接收方用户 ID',
--     status VARCHAR(16) NOT NULL DEFAULT 'pending' COMMENT 'pending/accepted',
--
--     -- V6 新增 4 列
--     note VARCHAR(100) NULL COMMENT '好友备注',
--     privacy VARCHAR(16) NOT NULL DEFAULT 'all' COMMENT '隐私设置：all/friends/hidden',
--     relation_type VARCHAR(32) NOT NULL DEFAULT 'friend' COMMENT '关系类别',
--     closeness VARCHAR(16) NOT NULL DEFAULT 'friend' COMMENT '关系程度：acquaintance/friend/close/intimate',
--
--     created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
--     updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
--         ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
--
--     UNIQUE KEY uk_friendship (requester_id, addressee_id),
--     KEY idx_friend_addressee (addressee_id, status),
--
--     CONSTRAINT fk_friend_requester
--         FOREIGN KEY (requester_id)
--         REFERENCES users(id)
--         ON DELETE CASCADE,
--
--     CONSTRAINT fk_friend_addressee
--         FOREIGN KEY (addressee_id)
--         REFERENCES users(id)
--         ON DELETE CASCADE
-- ) ENGINE=InnoDB
--   DEFAULT CHARSET=utf8mb4
--   COLLATE=utf8mb4_0900_ai_ci
--   COMMENT='笔友关系表（pending/accepted；含好友档案）';
--
--
-- -- ==========================================
-- -- 10. conversations  聊天会话表（V5 新增）
-- --     user_low_id < user_high_id（后端归一化排序），保证 A-B 唯一。
-- -- ==========================================
--
-- CREATE TABLE conversations (
--     id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT '会话 ID（自增主键）',
--
--     -- 归一化排序后的两个用户 id（较小者 / 较大者），由后端排序写入
--     user_low_id BIGINT UNSIGNED NOT NULL COMMENT '较小用户 ID（归一化排序后）',
--     user_high_id BIGINT UNSIGNED NOT NULL COMMENT '较大用户 ID（归一化排序后）',
--
--     created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
--     updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
--         ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
--
--     UNIQUE KEY uk_conversation_pair (user_low_id, user_high_id),
--     KEY idx_conv_low (user_low_id),
--     KEY idx_conv_high (user_high_id),
--
--     CONSTRAINT fk_conv_low
--         FOREIGN KEY (user_low_id)
--         REFERENCES users(id)
--         ON DELETE CASCADE,
--
--     CONSTRAINT fk_conv_high
--         FOREIGN KEY (user_high_id)
--         REFERENCES users(id)
--         ON DELETE CASCADE
-- ) ENGINE=InnoDB
--   DEFAULT CHARSET=utf8mb4
--   COLLATE=utf8mb4_0900_ai_ci
--   COMMENT='聊天会话表（归一化用户对唯一）';
--
--
-- -- ==========================================
-- -- 11. messages  聊天消息表（V5 新增，依赖 conversations）
-- --     归属会话，含已读标记；按 (conversation_id, created_at) 索引便于翻页。
-- -- ==========================================
--
-- CREATE TABLE messages (
--     id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT '消息 ID（自增主键）',
--
--     conversation_id BIGINT UNSIGNED NOT NULL COMMENT '所属会话 ID',
--     sender_id BIGINT UNSIGNED NOT NULL COMMENT '发送者用户 ID',
--     content VARCHAR(2000) NOT NULL COMMENT '消息内容（最大 2000 字符）',
--     is_read BOOLEAN NOT NULL DEFAULT FALSE COMMENT '是否已读',
--
--     created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
--
--     KEY idx_msg_conversation (conversation_id, created_at),
--     KEY idx_msg_sender (sender_id),
--
--     CONSTRAINT fk_msg_conversation
--         FOREIGN KEY (conversation_id)
--         REFERENCES conversations(id)
--         ON DELETE CASCADE,
--
--     CONSTRAINT fk_msg_sender
--         FOREIGN KEY (sender_id)
--         REFERENCES users(id)
--         ON DELETE CASCADE
-- ) ENGINE=InnoDB
--   DEFAULT CHARSET=utf8mb4
--   COLLATE=utf8mb4_0900_ai_ci
--   COMMENT='聊天消息表';
--
--
-- -- ==========================================
-- -- 12. notifications  通知表（V6 新增，依赖 users）
-- --     统一承载 system/comment/like/friend_request/friend_accept 通知。
-- --     user_id 为被通知人（CASCADE），actor_id 为触发人（SET NULL）。
-- -- ==========================================
--
-- CREATE TABLE notifications (
--     id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY COMMENT '通知 ID（自增主键）',
--
--     -- 被通知人（通知的接收方）
--     user_id BIGINT UNSIGNED NOT NULL COMMENT '接收通知的用户 ID',
--     -- 通知类型：system/comment/like/friend_request/friend_accept
--     type VARCHAR(24) NOT NULL COMMENT '通知类型：system/comment/like/friend_request/friend_accept',
--     -- 触发人（可为 NULL：system 通知无触发人；用户被删时置 NULL）
--     actor_id BIGINT UNSIGNED NULL COMMENT '触发通知的用户 ID（NULL 表示系统）',
--     content VARCHAR(500) NOT NULL COMMENT '通知内容（最大 500 字符）',
--     -- 关联业务对象 ID（评论 / 点赞 / 好友申请等），可为 NULL
--     related_id BIGINT UNSIGNED NULL COMMENT '关联业务对象 ID',
--     is_read BOOLEAN NOT NULL DEFAULT FALSE COMMENT '是否已读',
--
--     created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
--
--     KEY idx_notif_user_read (user_id, is_read),
--     KEY idx_notif_created (created_at),
--
--     CONSTRAINT fk_notif_user
--         FOREIGN KEY (user_id)
--         REFERENCES users(id)
--         ON DELETE CASCADE,
--
--     CONSTRAINT fk_notif_actor
--         FOREIGN KEY (actor_id)
--         REFERENCES users(id)
--         ON DELETE SET NULL
-- ) ENGINE=InnoDB
--   DEFAULT CHARSET=utf8mb4
--   COLLATE=utf8mb4_0900_ai_ci
--   COMMENT='通知表（系统/评论/点赞/好友申请/好友接受）';
--
--
-- -- ==========================================
-- -- V6 initialization completed（12 张表全部就绪）
-- -- ==========================================


-- ==========================================
-- 第三部分：升级后验证查询（注释，可选执行）
-- ==========================================
-- -- 3.1 确认 12 张表齐全（应返回 12 行）
-- SELECT TABLE_NAME, TABLE_COMMENT
-- FROM information_schema.TABLES
-- WHERE TABLE_SCHEMA = DATABASE()
-- ORDER BY TABLE_NAME;
--
-- -- 3.2 确认 friendships 的 4 个新列（类型 / 可空 / 默认值 / 注释）
-- SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT, COLUMN_COMMENT
-- FROM information_schema.COLUMNS
-- WHERE TABLE_SCHEMA = DATABASE()
--   AND TABLE_NAME = 'friendships'
--   AND COLUMN_NAME IN ('note', 'privacy', 'relation_type', 'closeness')
-- ORDER BY ORDINAL_POSITION;
--
-- -- 3.3 确认 notifications 关键列（类型 / 可空 / 默认值 / 注释）
-- SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT, COLUMN_COMMENT
-- FROM information_schema.COLUMNS
-- WHERE TABLE_SCHEMA = DATABASE()
--   AND TABLE_NAME = 'notifications'
-- ORDER BY ORDINAL_POSITION;
--
-- -- 3.4 确认 notifications 索引（idx_notif_user_read / idx_notif_created）
-- SELECT INDEX_NAME, NON_UNIQUE, GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS COLS
-- FROM information_schema.STATISTICS
-- WHERE TABLE_SCHEMA = DATABASE()
--   AND TABLE_NAME = 'notifications'
-- GROUP BY INDEX_NAME, NON_UNIQUE
-- ORDER BY INDEX_NAME;
--
-- -- 3.5 确认 notifications 外键（user_id → CASCADE；actor_id → SET NULL）
-- SELECT CONSTRAINT_NAME, COLUMN_NAME,
--        REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME, DELETE_RULE
-- FROM information_schema.KEY_COLUMN_USAGE
-- WHERE TABLE_SCHEMA = DATABASE()
--   AND REFERENCED_TABLE_SCHEMA = DATABASE()
--   AND TABLE_NAME = 'notifications'
-- ORDER BY CONSTRAINT_NAME, ORDINAL_POSITION;
