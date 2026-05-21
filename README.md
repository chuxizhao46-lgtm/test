# maimaibot 多专项 Bot 项目记忆

> **这是什么文件**:开新对话时,把这份内容贴给 Claude 作为第一条消息,避免 Claude 不了解项目背景。
> 
> **最后验证**:2026-04-24 (所有状态与 VPS 实际核对一致)
> 
> **用法**:本文件是"活文件",每次重大变更后更新末尾的"变更日志",保持和 VPS 状态同步。

---

## 📌 项目速览

- **用户**:麦麦,广告投放公司 CEO
- **项目目标**:基于同一份 bot.py 代码,通过多实例隔离,运行多个专项 Telegram Bot
- **当前状态**:主 bot + ads bot 在跑,finance/schedule 待搭
- **VPS**:65.49.198.172 (Ubuntu 22.04.5 LTS, UTC 时区)
- **运行用户**:maimaibot(非 root,无 sudo)

---

## 🎯 用户基本信息(所有 bot 都需要知道)

- 身份:广告投放公司 CEO
- 主要平台:Facebook/Instagram、Google Ads、TikTok Ads
- 关注指标:ROAS(核心)、CPM、CPC、CTR、CPA、LTV
- 决策风格:数据驱动、高效、不喜欢冗长讨论
- 工作原则(严格遵守):
  - **先验证,再动手**:所有操作前必须 grep/ls/cat 看现状,不要猜
  - **一次只改一个点**,立刻验证
  - **改代码必备份**(`.bak.日期时间` 格式)
  - **承认不确定**:不确定就说"不确定",不编造解释
  - **成本意识**:瞎猜导致的返工 = 浪费钱

---

## 🏗️ 架构核心(理解这个,后面都简单)

**一份代码 + 多实例隔离**。通过 systemd 跑多个 bot 服务,每个独立:
- 独立 Telegram Bot Token(独立 env 文件)
- 独立 WORK_DIR(环境变量控制 Claude Code 子进程的 cwd)
- 独立 CLAUDE.md 人设(放在各自 WORK_DIR 下)
- **共享同一份 Python 代码**

**关键机制**:`claude_runner.py` 用 `cwd=WORK_DIR` 启动 Claude Code 子进程。Claude Code 启动后,会自动从 cwd 向上递归查找并加载所有 `CLAUDE.md`,实现:
- `~/CLAUDE.md`:通用规则(所有 bot 继承)
- `~/projects/ads/CLAUDE.md`:ads 专项人设(覆盖/扩展通用规则)

---

## 📁 VPS 完整文件布局(已验证,2026-04-24)

/home/maimaibot/                              # 运行用户家目录
├── CLAUDE.md                   (3706 B)     # ★ 通用规则,精简版
├── CLAUDE.md.bak.20260421_190913 (4828 B)   # 更早的备份
├── CLAUDE.md.bak.20260422_064818 (6662 B)   # 精简前最后一版备份
├── .claude/                                  # Claude Code 自己的运行状态,不要动
│   ├── sessions/ plans/ projects/ ...
│   └── settings.json                         # 权限 deny 列表
├── .config/claude-bot/                       # env 密钥目录(权限 700)
│   ├── env                      (1323 B)    # ★ 主 bot 密钥
│   └── env.ads                  (1423 B)    # ★ ads bot 密钥
├── maimaibot/                                # ★ 共享代码目录
│   ├── bot.py                  (28339 B)    # TG 入口,不改
│   ├── claude_runner.py        (12640 B)    # Claude Code 封装,不改
│   ├── config.py                (2817 B)    # 配置常量,WORK_DIR 从环境变量读
│   ├── cost_tracker.py          (7629 B)    # 成本熔断
│   ├── task_analyzer.py         (4698 B)    # ★ 已改造(原 4329 B)
│   ├── task_analyzer.py.bak.20260423_074641 (4329 B)  # 改造前备份
│   └── requirements.txt
└── projects/                                 # 所有 bot 的工作目录
    ├── main/                                # 主 bot 工作目录
    ├── ads/                                 # ★ ads bot 工作目录
    │   └── CLAUDE.md            (3388 B)    # 麦麦广告参谋人设
    └── _staging/ads/
        └── maimai_identity_draft.md (1258 B) # 最早的麦麦身份草稿,可复用

/etc/systemd/system/
├── maimaibot.service           (1188 B)     # 主 bot
└── maimaibot-ads.service       (1333 B)     # ★ ads bot

★ 标记的文件是"我们建立/修改过的"。

---

## ⚙️ 共享代码的关键改造(task_analyzer.py)

**目的**:让专项 bot 的默认任务类型可配置,避免数据咨询类消息被误判为 code 走昂贵的 Plan Mode。

**改造点**(已完成):

1. 第 15 行:import os

2. PREFIX_MAP 第 26 行附近,字典内新增一行:
   "#report": TASK_TYPE_ASK,

3. analyze() 函数兜底逻辑前(第 111-115 行)加入:
   default_type = os.environ.get("DEFAULT_TASK_TYPE", "").strip().lower()
   if default_type in (TASK_TYPE_ASK, TASK_TYPE_QUICK, TASK_TYPE_CODE):
       return default_type, text, False

**验证命令**(以后怀疑改造有没有丢失时用):
- grep -n "^import os\|#report\|DEFAULT_TASK_TYPE" /home/maimaibot/maimaibot/task_analyzer.py
- wc -c /home/maimaibot/maimaibot/task_analyzer.py   # 应该是 4698

**主 bot 零影响**:主 bot 的 env 没有 DEFAULT_TASK_TYPE 变量,os.environ.get 返回空串,走原逻辑。

---

## 📋 env.<botname> 模板(从主 env 复制后改 4 处)

当前 env.ads 的关键字段(已验证):

WORK_DIR=/home/maimaibot/projects/ads
DAILY_BUDGET=1.0
MONTHLY_BUDGET=30.0
DEFAULT_TASK_TYPE=ask

**搭新 bot 时**:把 4 个字段的值改成对应的 bot。其他字段(ANTHROPIC_API_KEY / TELEGRAM_ALLOWED_USER_IDS / BRAVE_API_KEY / GITHUB_TOKEN)从主 env 复制,TELEGRAM_BOT_TOKEN 换成新 bot 的 token。

**权限必须**:chmod 600 + chown maimaibot:maimaibot

---

## 📋 maimaibot-<botname>.service 模板

当前 maimaibot-ads.service 的差异字段(已验证):

Description=maimaibot-ads - Telegram Bot for Ads (广告参谋)
EnvironmentFile=/home/maimaibot/.config/claude-bot/env.ads
SyslogIdentifier=maimaibot-ads

**不改**(所有 bot 共享):
WorkingDirectory=/home/maimaibot/maimaibot      # 这是代码目录,不是 Claude 工作目录!
ExecStart=/usr/bin/python3 /home/maimaibot/maimaibot/bot.py
User=maimaibot
Group=maimaibot

---

## 🚀 搭新专项 Bot 的 6 阶段流程

### 阶段 1:@BotFather 建 TG Bot(5 分钟)
发 /newbot → 起显示名 + username → 拿 token。

### 阶段 2:建工作目录(1 分钟)
mkdir -p /home/maimaibot/projects/<botname>
chown -R maimaibot:maimaibot /home/maimaibot/projects/<botname>

### 阶段 3:写 <botname> 专项 CLAUDE.md(10-15 分钟)
参考 ads 的结构(见"ads bot 参考"章节)。
新建到 /home/maimaibot/projects/<botname>/CLAUDE.md,别忘 chown。

### 阶段 4:建 env.<botname>(3 分钟)
cp /home/maimaibot/.config/claude-bot/env /home/maimaibot/.config/claude-bot/env.<botname>
chown maimaibot:maimaibot /home/maimaibot/.config/claude-bot/env.<botname>
chmod 600 /home/maimaibot/.config/claude-bot/env.<botname>
nano /home/maimaibot/.config/claude-bot/env.<botname>

改 4 处:
- TELEGRAM_BOT_TOKEN= → 新 token
- 解注释并改 WORK_DIR=/home/maimaibot/projects/<botname>
- 解注释 DAILY_BUDGET=1.0 和 MONTHLY_BUDGET=30.0
- 末尾追加 DEFAULT_TASK_TYPE=ask

**易错点**:改 WORK_DIR 时别把注释行和值粘在一起。用 Ctrl+K 整行删,再打新行。

### 阶段 5:建 maimaibot-<botname>.service(3 分钟)
cp /etc/systemd/system/maimaibot-ads.service /etc/systemd/system/maimaibot-<botname>.service
nano /etc/systemd/system/maimaibot-<botname>.service

改 3 处:Description / EnvironmentFile / SyslogIdentifier

验证语法:
systemd-analyze verify /etc/systemd/system/maimaibot-<botname>.service

### 阶段 6:启动 + 验证(5 分钟)
systemctl daemon-reload
systemctl enable maimaibot-<botname>
systemctl start maimaibot-<botname>
systemctl status maimaibot-<botname> --no-pager
journalctl -u maimaibot-<botname> -n 20 --no-pager -l

日志必须看到:
- Active: active (running)
- 工作目录: /home/maimaibot/projects/<botname> (值对!)
- 日预算: $1.00  月预算: $30.00

---

## 🎭 ads bot 参考(后续 bot 照这个结构设计 CLAUDE.md)

ads bot 的 CLAUDE.md 包含这些段落:

1. **身份**(一句话 + 和用户的关系)——"首席投放分析师,不是执行者"
2. **用户专业背景**——FB/Google/TikTok 广告,关注 ROAS 等
3. **专业边界**(✅做什么 / ❌不做什么)
4. **沟通规范**
   - 术语:中文为主,重要术语加英文缩写
   - 回复结构:**默认极简**(一句话能说清就一句话),深入只在用户要求时
   - 数据输入规范:不全先问,异常要反问,不猜不编
5. **双模式切换**
   - 默认:私下分析模式(可直白、可吐槽)
   - #report 前缀:客户报告模式(专业克制、带免责声明)
6. **工作目录约定**(明确边界:禁止读其他 bot 目录)
7. **越界处理**(非广告问题礼貌回避,建议问主 bot)

**原始素材**:/home/maimaibot/projects/_staging/ads/maimai_identity_draft.md 是最早的麦麦身份草稿,finance/schedule 设计时可以参考"身份 / 平台 / 术语 / 回复风格"这些维度。

---

## 💰 成本参考(基于已验证的真实数据)

| 任务类型 | 模型 | 单次消耗 |
|---------|------|---------|
| #ask 问答 | Haiku | $0.005-0.015 |
| #quick 查询 | Haiku | $0.005-0.010 |
| #code 改动 | Sonnet + Plan Mode | $0.04-0.08 |

**专项 bot 改造后(DEFAULT_TASK_TYPE=ask),典型使用成本**:
- 日均 10 条消息:约 $0.10-0.15/天
- 月均:$3-8/bot

**触发 code/plan 的情况**:
- 消息含"修改/改/写一个/创建/删除"等关键词
- 使用 #code 前缀
- 兜底(但已被 DEFAULT_TASK_TYPE=ask 覆盖)

---

## 🛠️ 日常运维速查

# 查看所有 bot 状态
systemctl is-active maimaibot maimaibot-ads
systemctl status maimaibot-ads --no-pager

# 看实时日志
journalctl -u maimaibot-ads -f

# 重启(改了代码或 env 后必须重启)
systemctl restart maimaibot-ads

# 改密钥
nano /home/maimaibot/.config/claude-bot/env.ads
systemctl restart maimaibot-ads

# 改 CLAUDE.md(不需要重启!下次对话自动生效)
nano /home/maimaibot/projects/ads/CLAUDE.md

---

## 🔄 开新对话使用本文件的方法

1. **第一条消息**:完整粘贴本文件内容
2. **第二条消息**:说明你要做什么,例如:
   - "帮我搭 finance bot,按阶段 1-6 走"
   - "我要升级 ads bot 的能力,接入一个真实数据源"
   - "某个字段报错了,帮我排查"

Claude 读完本文件后,应该能:
- 知道项目架构和现状
- 知道关键路径和文件
- 知道工作原则(先验证再动手)
- 不重复问已经解决过的问题

---

## 📝 变更日志(每次重大改动后追加)

### 2026-04-22
- 通用 ~/CLAUDE.md 精简:6662 → 3706 字节(-44%)
- 归档原始麦麦身份草稿到 _staging/ads/maimai_identity_draft.md
- 部署 ads bot:建目录、写 CLAUDE.md(3388 B)、建 env.ads、建 systemd service
- ads bot 首次启动成功

### 2026-04-23
- 识别问题:task_analyzer 兜底策略让数据咨询被误判为 code + Plan Mode,成本上涨 5-8 倍
- 改造 task_analyzer.py(4329 → 4698 字节):
  - 加 import os
  - PREFIX_MAP 加 #report 前缀
  - analyze() 加 DEFAULT_TASK_TYPE 环境变量兜底
- env.ads 末尾加 DEFAULT_TASK_TYPE=ask
- 重启两个 bot,验证主 bot 零影响,ads bot 成本降 60%
- ads bot 能力验证通过(身份/边界/极简/#report 全部正确)

### 2026-04-24
- 全面核对 VPS 状态,生成本文件作为"项目记忆"

### <下次更新填这里>
---
### 2026-04-29
- 部署 coach bot(启动力教练):
  - BotFather 注册 @maimai_coach_bot,显示名"麦麦的计划师"
  - 工作目录 /home/maimaibot/projects/coach
  - CLAUDE.md(3978 B,3 模式:默认 / #brain / #plan)
  - env.coach(末尾追加 DEFAULT_TASK_TYPE=ask)
  - systemd service(参考 ads,改 3 处:Description / EnvironmentFile / SyslogIdentifier)
- 启动一次成功,4 项实测全部通过(默认拆解 / 精力匹配 / #brain 不给建议 / 越界引导)
- 5 条测试消耗 $0.0353,全部走 Haiku,符合预期
- 已知:首次启动有 "Chat not found" warning,因为 bot 还没和用户建立过对话——
  下次重启前先在 TG 跟 bot 发一句话即可

---

*本文件的设计原则:所有声明都经过 VPS 实际验证,所有改动都有时间线,所有命令都可以直接执行。*
