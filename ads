# maimaibot 项目记忆 - 更新片段(2026-05-21)

> **使用方法**:这份文件不是替换你的项目记忆,而是给你**4 个独立片段**,你自己用文本编辑器贴到原文件对应位置。
> 
> 每个片段顶部标了**"贴到哪里"**。

---

## 片段 1:更新「📁 VPS 完整文件布局」章节

**贴到哪里**:在你原文件 `└── projects/` 那一段之后(也就是整个 `/home/maimaibot/` 目录列表的末尾),追加下面这一段。

同时,在 `/etc/systemd/system/` 那一段(主 bot 三个 service 列表)末尾追加 ad-logger.service 这一行。

### 1.1 在 /home/maimaibot/ 目录列表追加:

```
└── ad-logger/                                # ★ 户商消息登记 bot,完全独立项目
    ├── bot.py                  (~22 KB)     # TG 入口,支持多账户+LLM+按钮编辑
    ├── parser.py                (~9 KB)     # 正则备胎(LLM 挂了走这个)
    ├── parser_llm.py           (~11 KB)     # ★ 主力解析,调 Claude Haiku 4.5
    └── sheets.py                (~6 KB)     # gspread 封装,支持 append_row/append_rows
└── .config/ad-logger/                        # ★ ad-logger 的密钥目录(权限 700)
    ├── env                                    # token + 白名单 + Sheets ID + credentials 路径 + ANTHROPIC_API_KEY
    └── credentials.json                       # Google 服务账号密钥(权限 600)
```

### 1.2 在 /etc/systemd/system/ 列表追加:

```
└── ad-logger.service           (~1.2 KB)    # ★ 户商消息登记 bot
```

---

## 片段 2:新增「🎭 ad-logger 参考」章节

**贴到哪里**:在原文件「🎭 coach bot 参考」章节**之后**,「💰 成本参考」章节**之前**,插入下面整段。

```markdown
## 🎭 ad-logger bot 参考

ad-logger 是和 maimaibot 完全独立的项目,跑在同一台 VPS 但代码、配置、systemd 都独立。

### 核心定位
不是 LLM 聊天 bot,是**手动转发 + 几步点击 → 自动登记数据进 Google Sheets** 的工具。
解决的真实需求:CEO 在多个户商群每天收下户/充值/异常消息,以前手动抄表格,现在转发给 bot 自动登记。

### 技术栈
- python-telegram-bot 21.6(系统装的版本,我们的代码在 21.x 和 22.x 都兼容)
- gspread 6.2.1(装在 maimaibot 用户的 ~/.local,用 pip install --user)
- Claude Haiku 4.5(直接 curl/urllib 调 Anthropic API,**没用 anthropic SDK**)

### 核心机制
1. **LLM 优先,正则备胎**:bot.py 调 parser_llm.py 的 parse_with_llm,失败回退 parser.py 正则
2. **多账户支持**:LLM 返回字典列表,bot 展示"账户 1 / 账户 2 / ..."清单,批量写入
3. **token / 白名单 / credentials 路径全部从 env 读**(代码里有默认值兜底,Mac 本地开发也能跑)
4. **白名单只有 1 个用户 ID**(7862382612),陌生人发消息会被礼貌拒绝并记录 warning 日志

### Google Sheets 结构
表格 ID:`14bbOAZ3jZ8dZyMMlg_RCl-1VW0MWhP476zy8Qo5OSQo`,名字 `ad-logger-data`,3 个 sheet:
- **下户表** A-I 列:日期 / 平台 / 户型 / 账户ID / 自带余额 / 邮箱 / 成本 / 手续费 / 备注
- **充值表** A-G 列:日期 / 平台 / 户型 / 账户ID / 充值金额 / 手续费 / 备注
- **异常账户表** A-H 列:日期 / 平台 / 户型 / 账户ID / 异常类型 / 异常时余额 / 处理方式 / 备注

服务账号邮箱:`ad-logger-bot@ad-logger-496909.iam.gserviceaccount.com`(已是 Editor 权限)

### TG 流程(用户视角)
```
转发消息 → 选[下户/充值/异常] → ⏳LLM 解析 → 选[FB/Google/TikTok/其他]
→ 看多账户清单(单账户体验和单账户一致)
→ [✏️ 编辑] / [✅ 全部写入] / [❌ 取消]
→ 写入完成,显示"已写入 X 表 第 N-M 行"
```

### 关键文件路径速记
- bot 代码:`/home/maimaibot/ad-logger/`
- bot 密钥:`/home/maimaibot/.config/ad-logger/env` 和 `credentials.json`
- systemd:`/etc/systemd/system/ad-logger.service`

### env 关键字段
```
TELEGRAM_BOT_TOKEN=<BotFather token>
ALLOWED_USER_IDS=7862382612
SPREADSHEET_ID=14bbOAZ3jZ8dZyMMlg_RCl-1VW0MWhP476zy8Qo5OSQo
CREDENTIALS_FILE=/home/maimaibot/.config/ad-logger/credentials.json
ANTHROPIC_API_KEY=<和 maimaibot 共用同一个 key,直接 grep 追加来的>
```

### 调试和运维
```
# 实时看日志
journalctl -u ad-logger -f

# 看最近 N 分钟的日志(消息原文 + LLM 解析结果都在里面)
journalctl -u ad-logger --since "5 minutes ago" --no-pager

# 改了 prompt(parser_llm.py)之后必须重启
systemctl restart ad-logger

# 改了 CLAUDE.md 之类的不存在 - ad-logger 没有 CLAUDE.md(不调 Claude Code 子进程)

# 看是不是新版代码到位(怀疑没传上去时)
grep -c "消息原文" /home/maimaibot/ad-logger/bot.py    # 应该 > 0
grep -c "PROMPT_RECHARGE" /home/maimaibot/ad-logger/parser_llm.py    # 应该是 1
```

### Bot 实例
`@maimai_ad_logger_bot`,显示名"麦麦的户商登记"

### 待办(阶段 8)
**Sheets 汇总公式 + 数据透视表**——给 3 个表加汇总维度(按账户 ID / 按时段 / 按户商)。
**没做的原因**:数据还少(各表几十行内),设计汇总等于猜需求,实际用 1-2 周再做。
```

---

## 片段 3:在「💰 成本参考」章节追加

**贴到哪里**:在原文件「💰 成本参考」章节末尾追加。

```markdown

### ad-logger 成本(独立账单结构,但和 maimaibot 复用同一个 ANTHROPIC_API_KEY)

| 项 | 单次成本 | 月成本估算 |
|---|---|---|
| 1 条消息 LLM 解析(Haiku 4.5) | ~$0.0015 | - |
| 1 条消息 ≈ 600 input + 100 output tokens | - | - |
| 日均 30 条消息 | - | ~$1.5/月 |
| 日均 100 条消息 | - | ~$5/月 |

**LLM 调用频率**:每条消息**只调 1 次**(选完类型那一步),编辑/写入步骤不调 LLM。
```

---

## 片段 4:在「📝 变更日志」追加新条目

**贴到哪里**:在原文件「📝 变更日志」末尾(在 `### <下次更新填这里>` 之前),追加下面整段。

```markdown
### 2026-05-20 ~ 2026-05-21:新建 ad-logger bot(独立项目)

**项目目标**:CEO 在户商群转发消息给 bot,bot 自动解析后写入 Google Sheets。和 maimaibot 完全独立,不是新加专项 bot。

**完整工程(分 9 个阶段,~12 小时)**:
- **阶段 1**:写 parser.py 正则解析,3 条样本 40 个字段断言全过
- **阶段 2**:Google Cloud 注册项目 / 开启 Sheets API + Drive API / 创建服务账号 / 共享 Sheets / gspread 写入测试通过
- **阶段 3**:BotFather 注册 @maimai_ad_logger_bot,Mac 本地 echo bot 跑通
- **阶段 4**:7 个小步骤,完整功能(类型选择 → 平台选择 → 确认 → Sheets 写入 → 白名单 → 编辑字段 → 异常的处理方式)
- **阶段 5**:VPS 部署 - 建独立目录 ad-logger / 装 gspread / 配 env / 写 systemd service / 验证开机自启 + 崩溃重启
- **阶段 6**:用户反馈"识别有很多问题",诊断发现真实消息**超过 50% 是多账户**,正则做不到智能。**架构变更:接入 Claude Haiku 4.5 LLM 解析**,多账户支持,正则降为备胎
- **阶段 7**:LLM 扩展到充值 + 异常消息(每种类型一个 prompt)

**关键设计决策**:
1. **独立 vs 塑进 maimaibot**:选独立——这个 bot 完全不用 LLM 对话,塞进 maimaibot 等于强行套壳
2. **本地 vs VPS 开发**:选 Mac 本地开发,跑通后 scp 上 VPS,体验快很多
3. **零 LLM vs 启用 LLM**:最初选零 LLM(纯正则),阶段 6 改为启用——因为真实消息格式多样性远超预期,纯正则会"打补丁打到永远"
4. **token 硬编码 vs env**:阶段 5 拆出 env(parser_llm.py / bot.py / sheets.py 都从 env 读配置,有默认值兜底)
5. **平台选择**:多账户消息只选一次平台,应用到所有账户

**踩过的坑**:
1. **VPS 上有孤儿 bot 进程**:5.3 测试时 Ctrl+C 没清干净,导致 systemd 服务一直报 Conflict。**教训**:`ps aux | grep bot.py` 才是确认进程退出的依据,Ctrl+C 后必须 ps 一次
2. **deleteWebhook 清不掉 polling 冲突**:别人在 polling,你这边调 deleteWebhook 只清自己,对方立刻重连。**必须 kill 那个进程**
3. **scp 路径有空格**:Mac 默认 zsh,反斜杠转义 (`Google\ auto`) 在不同上下文行为不一样。**最稳:用双引号包整段路径**,不要再加反斜杠
4. **heredoc 在终端粘贴会乱码**:实际写入的内容可能正确,但终端回显错乱。**永远以 `cat 文件` 输出为准**,不要看粘贴时屏幕显示
5. **Python str.format 在 prompt 含 JSON 时炸**:prompt 里有 `{"accounts": ...}`,被 .format() 当成占位符报 KeyError。**改用 replace 替代 format**
6. **Mac → 新 Mac 换机**:旧 Mac 上的文件不会自动到新 Mac,新 Mac 上的 Google auto 文件夹是空的,要重新下载所有文件

**重要日志增强**:
bot.py 第一次提到"识别有问题"时,没有日志能复盘。**加了"消息原文 + 9 个字段解析结果"详细日志**,以后任何识别错误都能从 journalctl 还原原文,精准改 prompt。

**意外的收获**:
- LLM 主动把消息里的"时区:-8"放进备注,合理超出预期
- LLM 主动把样本里的"RQ"识别为备注(以前正则直接丢)
- LLM 主动忽略 facebook 主页链接里的 id(没把它误认为账户 ID)

**待办(放到阶段 8)**:
Sheets 加汇总公式 + 数据透视表,实现"按账户 / 按时段 / 按户商"3 种汇总视图。**先不做的原因**:数据还少,先漫用 1-2 周积累 100+ 行数据再设计汇总更准确。

### <下次更新填这里>
- 
```

---

## 4 个片段贴完,你的项目记忆就同步到 2026-05-21 了。

明天或者下次开新对话,**第一条消息只需要贴这份更新后的项目记忆**,Claude 就能立刻接上 ad-logger 项目的所有上下文。
