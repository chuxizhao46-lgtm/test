# ad-logger 项目记忆

> **这是什么文件**:开新对话谈 ad-logger 时,把这份完整内容贴给 Claude 作为第一条消息,
> 避免 Claude 不了解项目背景。
>
> **和 maimaibot 项目记忆的关系**:两份独立。这份只讲 ad-logger,maimaibot 的事去看那一份。
> 它们跑在同一台 VPS 上,共用基础设施,但**代码、配置、systemd 完全独立**。
>
> **最后验证**:2026-05-22(LLM 解析全功能,bug fix 完成)
>
> **用法**:本文件是"活文件",每次重大变更后更新末尾的"变更日志",保持和 VPS 状态同步。

---

## 📌 项目速览

- **用户**:麦麦,广告投放公司 CEO
- **项目目标**:CEO 在户商群转发消息给 bot,bot 自动解析后写入 Google Sheets。
  替代以前的"手抄表格"。
- **bot 实例**:`@maimai_ad_logger_bot`(显示名"麦麦的户商登记")
- **当前状态**:已上线,24/7 运行在 VPS。LLM 全功能 + 多账户支持 + 编辑/取消/白名单都通过
- **VPS**:65.49.198.172(和 maimaibot 同一台,Ubuntu 22.04.5 LTS,UTC 时区)
- **运行用户**:maimaibot(和 maimaibot 共用同一个 Linux 用户)
- **systemd 服务**:`ad-logger.service`(独立,和 maimaibot-* 平级)

---

## 🎯 业务核心

### 户商消息有 3 种类型

1. **下户**:户商给麦麦"配"了新广告账户
2. **充值**:户商给麦麦的账户充了钱
3. **异常**:账户出问题(死户/封禁/封停/限流/风控 等)

### Google Sheets 表头(3 个 sheet,固定结构)

- **下户表** A-I 列:日期 / 平台 / 户型 / 账户ID / 自带余额 / 邮箱 / 成本 / 手续费 / 备注
- **充值表** A-G 列:日期 / 平台 / 户型 / 账户ID / 充值金额 / 手续费 / 备注
- **异常账户表** A-H 列:日期 / 平台 / 户型 / 账户ID / 异常类型 / 异常时余额 / 处理方式 / 备注

### 字段说明

- **日期**:bot 自动填(收到消息当天)
- **平台**:FB / Google / TikTok / 其他(消息里不显式,bot 用按钮让用户选)
- **户型**:户商代号,如 `PT media-233`、`LBTG-A2014+8`(`+8` 是户型的一部分,不要丢)
- **账户ID**:广告平台分配的 14-16 位数字
- **货币**:单一货币,不记币种和汇率
- **下户消息的"政策 30+8"**:30 是成本,8 是手续费
- **下户消息的"格式 2+3"**:2 是成本,3 是手续费(同义)
- **异常类型**:统一记为"封禁"(无论原文是死户/封停/限流/风控)
- **处理方式**:消息里没有,bot 给按钮 [清退] [转移] [其他](阶段 4.7 未实现,字段留空,需要时手动编辑)
- **异常时余额**:
  - 优先级 1:有"余额:340.19"这种明确数字 → 用数字
  - 优先级 2:只有"清零"/"清0" → 0
  - 优先级 3:都没有 → null

---

## 🏗️ 架构核心

### 一句话概括

```
用户转发消息 → bot 调 Claude Haiku 4.5 解析 → 多账户清单确认 → 批量写入 Google Sheets
```

### 关键决策(回顾)

1. **独立项目而非塑进 maimaibot**:ad-logger 不调 LLM 对话(只调 LLM 抽字段),
   塞进 maimaibot 等于强行套壳。所以完全独立部署。
2. **LLM 主力 + 正则备胎**:最初要求"零 LLM",阶段 6 改为启用 Haiku 4.5——
   因为真实消息格式多样性远超预期(超过 50% 是多账户、不同户商写法完全不同),
   纯正则会"打补丁打到永远"。正则保留为 fallback,API 挂了 bot 还能用。
3. **多账户原生支持**:LLM 返回字典列表(`accounts`),即使单账户也是单元素列表,
   bot 统一处理。多账户时 UI 显示"账户 1 / 账户 2 ..."清单,批量写入。
4. **白名单**:只有 `7862382612`(麦麦)能用,陌生人发消息明确拒绝并记录 warning。
5. **token/密钥从 env 读**,代码硬编码作本地默认值(Mac 开发体验不受影响)。

### 用户交互流程

```
转发消息 → 选[📋下户/💰充值/⚠️异常] → ⏳ LLM 解析(1-2 秒)
→ 选[FB/Google/TikTok/其他]
→ 看多账户清单(单账户时不显示"账户 1"标题)
→ [✏️ 编辑] / [✅ 全部写入] / [❌ 取消]
→ "已写入【X 表】第 N-M 行"
```

### 编辑流程

- 单账户:点 [✏️ 编辑] → 直接进字段列表
- 多账户:点 [✏️ 编辑] → 先选账户 → 再选字段
- 选了字段后:发新值 / 发 `-` 清空 / 发 `/cancel` 放弃本次编辑

---

## 📁 VPS 完整文件布局(2026-05-22 验证)

```
/home/maimaibot/                              # 和 maimaibot 共用 home
├── ad-logger/                                # ★ 代码目录
│   ├── bot.py             (~22 KB)           # TG 入口,带详细日志
│   ├── parser.py          (~9 KB)            # 正则备胎(LLM 挂了用)
│   ├── parser_llm.py      (~11 KB)           # ★ 主力,调 Anthropic API
│   └── sheets.py          (~6 KB)            # gspread 封装(write_row + write_rows)
└── .config/ad-logger/                        # ★ 密钥目录(权限 700)
    ├── env                                    # 配置(权限 600)
    └── credentials.json                       # Google 服务账号密钥(权限 600)

/etc/systemd/system/
└── ad-logger.service       (~1.2 KB)         # systemd 守护
```

### env 字段(都已配置好)

```
TELEGRAM_BOT_TOKEN=<BotFather 给的 token>
ALLOWED_USER_IDS=7862382612
SPREADSHEET_ID=14bbOAZ3jZ8dZyMMlg_RCl-1VW0MWhP476zy8Qo5OSQo
CREDENTIALS_FILE=/home/maimaibot/.config/ad-logger/credentials.json
ANTHROPIC_API_KEY=<和 maimaibot 共用,从 /home/maimaibot/.config/claude-bot/env 追加来>
```

### Google Cloud 服务账号信息

- **项目名**:`ad-logger`,项目 ID 后缀 `496909`
- **服务账号邮箱**:`ad-logger-bot@ad-logger-496909.iam.gserviceaccount.com`(Editor 权限)
- **Sheets ID**:`14bbOAZ3jZ8dZyMMlg_RCl-1VW0MWhP476zy8Qo5OSQo`
- **Sheets 文件名**:`ad-logger-data`(3 个 sheet:下户表/充值表/异常账户表)
- **开启的 API**:Google Sheets API、Google Drive API

---

## ⚙️ 关键技术栈

| 组件 | 版本 | 备注 |
|---|---|---|
| Python | 3.10.12(VPS)/ 3.9(Mac 开发) | Mac 上有 FutureWarning 但能跑 |
| python-telegram-bot | 21.6(VPS)/ 22.5(Mac) | 两个版本都兼容我们的代码 |
| gspread | 6.2.1 | 装在 `~/.local`(pip install --user) |
| Anthropic API | Messages API(直接 curl/urllib,**没用 SDK**) | model: `claude-haiku-4-5` |

---

## 💰 成本

| 项 | 单次 | 月成本估算 |
|---|---|---|
| 1 条消息 LLM 解析 | ~$0.0015(input 600-800 + output 80-150 token) | - |
| 日均 10 条 | - | ~$0.5/月 |
| 日均 30 条 | - | ~$1.5/月 |
| 日均 100 条 | - | ~$5/月 |

**LLM 调用频率**:每条消息**只调 1 次**(选完类型那一步),编辑/写入不调 LLM。

**和 maimaibot 共用 API key**:成本算到同一个账单,目前没分离;
日后如果想单独追踪,在 Anthropic Console 给 ad-logger 申请独立 key。

---

## 🛠️ 日常运维速查

### 看服务状态
```
systemctl status ad-logger --no-pager
systemctl is-active ad-logger     # 简短输出 active/inactive
```

### 看日志
```
# 实时
journalctl -u ad-logger -f

# 最近 N 分钟(诊断时常用)
journalctl -u ad-logger --since "10 minutes ago" --no-pager

# 最近 N 条
journalctl -u ad-logger -n 50 --no-pager
```

### 重启服务
```
# 改了 bot.py / parser_llm.py / sheets.py / parser.py 都要重启才生效
systemctl restart ad-logger
sleep 5 && journalctl -u ad-logger -n 10 --no-pager
```

### 改 env / 密钥
```
nano /home/maimaibot/.config/ad-logger/env
systemctl restart ad-logger
```

### 怀疑代码没传上去时
```
# 看文件修改时间
ls -la /home/maimaibot/ad-logger/

# 找特定标识(比如阶段 6 加的日志增强)
grep -c "消息原文" /home/maimaibot/ad-logger/bot.py        # 应该 > 0
grep -c "PROMPT_RECHARGE" /home/maimaibot/ad-logger/parser_llm.py    # 应该是 1
```

### 怀疑 polling 冲突(Conflict 错)
```
# 看是否有孤儿进程
ps aux | grep "ad-logger/bot.py" | grep -v grep
# 应该只有 1 行(systemd 启动的),如果有 2 行就有孤儿

# 杀掉孤儿
kill <PID>

# 极端情况:让 BotFather /revoke 重发 token,所有 polling 客户端自动失效
```

---

## 📋 从 Mac 改代码、部署到 VPS 的标准流程

### Mac 文件位置
```
/Users/<你的用户名>/Downloads/Google auto/    # 注意有空格,scp 时用双引号
```

### scp 上传(Mac 终端,zsh)

⚠️ **关键**:用**双引号**包路径,**不要**再加反斜杠转义:

```
# 单个文件
scp "/Users/<你>/Downloads/Google auto/bot.py" root@65.49.198.172:/home/maimaibot/ad-logger/bot.py

# 多个文件
scp "/Users/<你>/Downloads/Google auto/bot.py" "/Users/<你>/Downloads/Google auto/parser_llm.py" root@65.49.198.172:/home/maimaibot/ad-logger/
```

### VPS 上 chown + restart(scp 上去归 root,要交回 maimaibot)
```
chown maimaibot:maimaibot /home/maimaibot/ad-logger/bot.py /home/maimaibot/ad-logger/parser_llm.py
systemctl restart ad-logger
sleep 8 && journalctl -u ad-logger -n 15 --no-pager
```

---

## 🎯 改 LLM prompt 的标准流程(最常用!)

bot 上线后,**遇到识别错误时主要靠改 prompt 修复**,代码框架不动。

### Step 1:从日志找证据
```
journalctl -u ad-logger --since "5 minutes ago" --no-pager
```

找到 `消息原文: '...'` 和它后面的 `--- 账户 X ---` 字段解析结果,
看哪个字段错了。

### Step 2:在沙箱测试改 prompt

(让 Claude 帮你改,然后沙箱跑一次真实 LLM 调用,验证修对了)

### Step 3:scp + chown + restart(同上)

### Step 4:回归测试

用**老样本**重测一次,确认没把旧 case 改坏。

---

## 🐛 已知的"prompt 优先级"心得

LLM 偶尔会按 prompt 规则的**出现顺序**判断,而不是按"全文匹配"。
**写多条规则时,务必明确优先级**,并给出"看似冲突的 case"该怎么处理。

**反例**(2026-05-22 的 anomaly bug):
```
5. 异常时余额:
   - 消息含"清0"/"清零" → 填 0       ← LLM 看到第一条就停了
   - 消息含"余额 200"/"余额清135" → 提取数字
```
真实消息 `挂户清零\n余额:340.19` 被识别成 0(错)。

**修复**:
```
5. 异常时余额(按优先级判断,先看是否有明确数字):
   - 优先级 1(最高):"余额:340"/"余额 200" → 提取数字
   - 优先级 2:只有"清零"/"清0" → 0
   - 优先级 3:都没有 → null
   - 特别注意:同时含"清零"和"余额:340.19" → 以 340.19 为准
```

---

## ⚠️ 踩过的 6 个坑(避免再踩)

1. **孤儿 bot 进程**:`Ctrl+C` 不一定清干净进程。**判断进程退出要用 `ps aux | grep`**,
   不是看 Ctrl+C 后屏幕回到提示符就以为完事了。
2. **deleteWebhook 清不掉 polling 冲突**:对方进程会立刻重连。**必须 kill 那个进程的 PID**,
   或者最后一招:让 BotFather `/revoke` 重发 token,所有旧客户端立刻失效。
3. **scp 路径有空格**:Mac 的 zsh 对反斜杠转义敏感。**永远用双引号包整段路径**,
   不要在双引号里再加 `\`(双重转义会失效)。
4. **heredoc 终端粘贴回显错乱**:实际写入文件的内容**通常**正确,但终端显示可能错位。
   **永远以 `cat 文件` 输出为准**,不要看粘贴时屏幕显示判断成功与否。
5. **Python `str.format()` 在 prompt 含 JSON 时炸**:prompt 里有 `{"accounts": ...}`,
   `.format()` 会把 `{}` 当占位符报 `KeyError`。**改用 `replace()` 替代 `.format()`**。
6. **Mac 换机文件没自动同步**:从 MacBook Pro 换到 MacBook Air,
   旧 Mac 上的 `Google auto/` 文件夹在新 Mac 上是空的,要重新下载所有文件。

---

## 🧪 几个标准测试样本(LLM 解析验证用)

### 下户 - 单账户(经典格式)
```
PT media-233广告账户编号:1391544663010336
自带:200  RQ
wpzerdq5893@hotmail.com
政策30+8
```
LLM 预期:户型 `PT media-233` / 账户ID `1391544663010336` / 自带 200 /
邮箱 `wpzerdq5893@hotmail.com` / 成本 30 / 手续费 8 / 备注 `RQ`(LLM 智能放备注)

### 下户 - 多账户(新格式)
```
格式:2+3 时区:-8

账户ID/名称
1021760500523570  LBTG-A2014+8
850309214800399  LBTG-A2015+8

主页链接
https://www.facebook.com/profile.php?id=61589343270244
https://www.facebook.com/profile.php?id=61588951127793

主页账户已授权绑定
2027837158107880
```
LLM 预期:**2 个账户**,每个成本 2、手续费 3、备注 `时区:-8`,
**主页链接和主页授权 ID 都忽略**。

### 充值 - 多账户
```
LBTG-A183-8
广告账户编号:1667569044574876

充值350

LBTG-A182-8
广告账户编号:959566970147787
充值350
```
LLM 预期:**2 个账户**,各充值 350,户型 `LBTG-A183-8` 和 `LBTG-A182-8`(`-8` 是户型一部分)。

### 异常 - 经典(清零)
```
PT media-233
广告账户编号:1391544663010336
死户,余额清0
```
LLM 预期:异常类型 `封禁` / 异常时余额 `0`。

### 异常 - 有具体余额
```
LBTG-A2035+8
编号:1494691845366664
挂户清零
余额:340.19
```
LLM 预期:异常类型 `封禁` / 异常时余额 `340.19`(**不是 0**) / 备注 `挂户清零`。

---

## 🔄 开新对话使用本文件的方法

### 第一条消息(完整粘贴)
```
[完整粘贴本文件内容]
```

### 第二条消息(说明本次要做什么),例如:
- "bot 又遇到识别错误了,帮我排查"+ 贴日志
- "想加一个新字段,叫'XXX'"
- "想做阶段 8(Sheets 汇总公式)"
- "VPS 重启后 bot 没起来,帮看 status"

Claude 读完本文件后,应该能:
- 知道项目架构、现状、关键路径
- 知道 LLM prompt 怎么改、改完怎么部署
- 知道踩过的坑(避免重复)
- 立即接上,不重复问已经解决过的问题

---

## 📝 变更日志

### 2026-05-19:阶段 1-2 启动
- 阶段 1:写正则 parser.py,3 条样本 40 个字段断言全过(Mac 本地验证)
- 阶段 2:Google Cloud 注册项目 `ad-logger`,开启 Sheets API + Drive API,
  创建服务账号 + 下载 credentials.json,共享 Sheets 给服务账号 Editor 权限,
  gspread 写入测试通过(Mac 本地)
- **踩坑**:Google Cloud 强制 2SV,先开了两步验证再继续

### 2026-05-20:阶段 3-5 完成
- 阶段 3:BotFather 注册 `@maimai_ad_logger_bot`,Mac 本地 echo bot 跑通
- 阶段 4:7 个小阶段,完成完整功能
  - 4.1 最小可工作版(只 print 不写表)
  - 4.2 加类型选择按钮
  - 4.3 加平台选择按钮
  - 4.4 加确认按钮 + 写入 Sheets(里程碑!)
  - 4.5 加白名单
  - 4.6 加编辑字段(D 方案:点 [编辑] 总按钮后弹字段列表)
  - 4.7 异常处理方式(决定留空,需要时手动编辑)
- 阶段 5:VPS 部署
  - 建独立目录 `/home/maimaibot/ad-logger/` 和 `/home/maimaibot/.config/ad-logger/`
  - scp 传 3 个 .py 文件 + credentials.json
  - 装 gspread(`pip install --user`)
  - 把 token 从代码里抠出来放 env(`os.environ.get` 兜底硬编码)
  - 写 `ad-logger.service`(参考 maimaibot-ads,改 5 处)
  - 验证开机自启 + 崩溃自动重启
- **踩坑**:Mac zsh 反斜杠转义;VPS 上有孤儿 bot 进程导致 Conflict;Mac 换机后文件夹空

### 2026-05-21:阶段 6-7 完成,bot 重大升级
- 用户反馈"识别有很多问题",**加详细日志(消息原文 + 9 字段解析结果)**
- 用真实消息诊断,发现**超过 50% 是多账户消息**,正则做不到智能
- **架构变更:接入 Claude Haiku 4.5 LLM 解析**
  - 新建 `parser_llm.py`,prompt 设计 + 调用 Anthropic API(用 urllib,没用 SDK)
  - 复用 maimaibot 的 ANTHROPIC_API_KEY(grep 追加到 ad-logger env)
  - 改 bot.py 支持字典列表(多账户清单 UI、批量写入)
  - 改 sheets.py 加 `write_rows()` 函数
  - 正则降为 fallback(LLM 失败时回退)
- 阶段 7:LLM 扩展到充值 + 异常(每种类型一个 prompt,框架不变)
- **踩坑**:Python `.format()` 在 prompt 含 JSON 时炸(改用 `replace()`)

### 2026-05-22:LLM prompt 优先级 bug 修复
- **现象**:`挂户清零\n余额:340.19` 被识别为余额 0(错,应该是 340.19)
- **诊断**:不是 LLM 抽风,是 anomaly prompt 规则 5 优先级写得不清,
  LLM 看到"清零"就按第一条规则填 0,忽略了后面的"余额:340.19"
- **修复**:改 anomaly prompt 规则 5,反转优先级:
  - 优先级 1:有明确"余额:数字" → 用数字
  - 优先级 2:只有"清零" → 0
  - 优先级 3:都没有 → null
  - 增加"挂户清零+余额:340.19"作为反例 case
- **验证**:用同一条消息重测,LLM 正确抽出 `340.19`;
  老样本 `死户,余额清0` 仍正确识别为 0(无回归)
- **教训**:LLM 偶尔按 prompt 规则的"出现顺序"判断,**多条规则务必明确优先级**

### <下次更新填这里>
- 

---

## ⏳ 待办(放着,数据积累后再做)

### 阶段 8:Sheets 公式 + 数据透视表(暂缓)
**目标**:在 Sheets 网页里加汇总公式,实现 3 种维度的汇总视图——
- 按账户 ID:这个账户花了多少、充了多少、当前状态
- 按时段(本月/本周):总充值、总下户费用
- 按户商(PT media / LBTG):总下了多少户、收了多少钱

**为什么暂缓**:数据还少(各表几十行),设计汇总等于猜需求。
等漫用 1-2 周积累 100+ 行真实数据,需求自然清晰,30-40 分钟就能搞定。

**预期方法**:不写代码,在 Sheets 网页里加 SUMIF 公式 + 数据透视表。

### 持续:遇到识别错误时调 prompt
本质上 ad-logger 上线后就是个"漫用 + 偶尔调 prompt"的状态。
每次遇到识别错误:
1. 看日志拿到消息原文 + 错误的解析结果
2. 改对应类型的 prompt
3. 测试 + 回归测试
4. 部署到 VPS

---

*本文件的设计原则:所有声明都经过 VPS 实际验证,所有改动都有时间线,所有命令都可以直接执行。*
