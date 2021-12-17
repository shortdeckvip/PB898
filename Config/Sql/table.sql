DROP TABLE IF EXISTS `rank_most_win_today`;
CREATE TABLE `rank_most_win_today`(
	`uid` BIGINT NOT NULL COMMENT '用户ID',
	`gameid` INT NOT NULL COMMENT '游戏ID',
	`profit` BIGINT NOT NULL DEFAULT 0 COMMENT '盈利值',
	`create_time` BIGINT NOT NULL COMMENT '创建记录时间戳(毫秒)',
	`zero_uptime` BIGINT NOT NULL COMMENT '零点记录时间戳(毫秒)',
	`update_time` BIGINT NOT NULL COMMENT '最近更新时间戳(毫秒)',
	`nickname` VARCHAR(64) NOT NULL COMMENT '用户昵称',
	`nickurl` VARCHAR(128) NOT NULL COMMENT '用户头像URL',
	PRIMARY KEY (`uid`, `gameid`),
	KEY (`gameid`, `zero_uptime`),
	KEY (`profit`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `rank_history_mostwin_today`;
CREATE TABLE `rank_history_mostwin_today`(
	`uid` BIGINT NOT NULL COMMENT '用户ID',
	`gameid` INT NOT NULL COMMENT '游戏ID',
	`profit` BIGINT NOT NULL DEFAULT 0 COMMENT '盈利值',
	`create_time` BIGINT NOT NULL COMMENT '创建记录时间戳(毫秒)',
	`zero_uptime` BIGINT NOT NULL COMMENT '零点记录时间戳(毫秒)',
	`update_time` BIGINT NOT NULL COMMENT '最近更新时间戳(毫秒)',
	`nickname` VARCHAR(64) NOT NULL COMMENT '用户昵称',
	`nickurl` VARCHAR(128) NOT NULL COMMENT '用户头像URL',
	PRIMARY KEY (`uid`, `gameid`),
	KEY (`gameid`, `profit`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `rank_most_win_round`;
CREATE TABLE `rank_most_win_round`(
	`uid` BIGINT NOT NULL COMMENT '用户ID',
	`gameid` INT NOT NULL COMMENT '游戏ID',
	`profit` BIGINT NOT NULL DEFAULT 0 COMMENT '盈利值',
	`create_time` BIGINT NOT NULL COMMENT '创建记录时间戳(毫秒)',
	`zero_uptime` BIGINT NOT NULL COMMENT '零点记录时间戳(毫秒)',
	`update_time` BIGINT NOT NULL COMMENT '最近更新时间戳(毫秒)',
	`nickname` VARCHAR(64) NOT NULL COMMENT '用户昵称',
	`nickurl` VARCHAR(128) NOT NULL COMMENT '用户头像URL',
	PRIMARY KEY (`uid`, `gameid`),
	KEY (`gameid`, `zero_uptime`),
	KEY (`profit`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `rank_history_mostwin_round`;
CREATE TABLE `rank_history_mostwin_round`(
	`uid` BIGINT NOT NULL COMMENT '用户ID',
	`gameid` INT NOT NULL COMMENT '游戏ID',
	`profit` BIGINT NOT NULL DEFAULT 0 COMMENT '盈利值',
	`create_time` BIGINT NOT NULL COMMENT '创建记录时间戳(毫秒)',
	`zero_uptime` BIGINT NOT NULL COMMENT '零点记录时间戳(毫秒)',
	`update_time` BIGINT NOT NULL COMMENT '最近更新时间戳(毫秒)',
	`nickname` VARCHAR(64) NOT NULL COMMENT '用户昵称',
	`nickurl` VARCHAR(128) NOT NULL COMMENT '用户头像URL',
	PRIMARY KEY (`uid`, `gameid`),
	KEY (`gameid`, `profit`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

