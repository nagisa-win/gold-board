# 桌面浮窗小工具 · 设计文档

> 版本 v0.2 / 2026-11-23 / 基于现有 `gold-board` 金价浮窗扩展
>
> v0.2 变更（已与需求方确认）：视觉方向取 **A / HUD 玻璃**；原「独立控制台窗」并入浮卡本身，浮卡左侧改为三图标 rail（金价 / 唤醒 / 通知）；Codex `notify` 直接接管不做转发；caffeinate 默认 `-i` 且胶囊按钮复用上次参数；通知能力扩为系统通知 + 触控板震动 + 强度 + 声音。

## 1. 产品定位

一个常驻桌面的**个人仪表盘**（不是应用窗口，是一件桌面物件）：平时只有一行数字，需要时展开成一块三页的控制台。

三条设计原则，按优先级排序：

1. **0% 透明时也绝不能"丢掉"**——可发现性优先于极简。
2. **静止时安静，触碰时给反馈**——毛玻璃、描边、震动都属于"被碰到"的时刻。
3. **数据先于装饰**——数字永远是最粗、最亮、对齐最严格的那个元素。

明确不做：不做与其他行情软件的 K 线对比、不做多品种、不做云同步、不做 Dock 图标（保持 `LSUIElement`）。

## 2. 现有代码盘点与约束

| 现状 | 影响 |
| --- | --- |
| `main.swift` 单文件 231 行：`Quote` 解析、`Delegate` 轮询、`Card` 自绘、右键菜单 | 需拆分为模块，否则加三页后会失控 |
| `Trend.swift`：`HoverTrend`（悬停弹窗）+ `TrendView`（自绘曲线）+ `DayCurve`（配对换算） | 曲线绘制直接复用，只换配色与容器 |
| 浮窗 = `NSPanel(.borderless, .nonactivatingPanel)`，`level = .statusBar` | 控制台窗沿用同款 panel，避免抢焦点 |
| `build.sh`：swiftc 直编 `*.swift` + lipo + adhoc 签名，无 SPM | 继续沿用；新增文件放 `src/` 即自动纳入编译 |
| 依赖：仅 AppKit / Foundation，无第三方 | 全程手写 AppKit，不引 SwiftUI、不引 SPM 包 |
| 签名：adhoc（`local.goldfloat.cnspot`） | 私有 API（触控板马达）可用；不做沙盒 |

新增能力带来的新约束：

- **触控板震动**要用私有框架 `MultitouchSupport`（`MTActuator*`），必须运行时 `dlopen` + `dlsym`，符号缺失时降级为 `NSHapticFeedbackManager`，再缺失则静默。
- **caffeinate** 用子进程管理，必须有 PID 文件与清理路径，避免 App 崩溃后系统一直不睡。
- 控制台窗比原浮窗大 3 倍，需要真正的布局代码（`NSStackView` + 手写约束），不能再靠绝对坐标。

## 3. 信息架构

两个表面，一个入口：

```
                ┌─ 悬停 250ms ─▶ 毛玻璃底 + 浮卡(金价页) 自动展开/收起
胶囊浮窗(104×28)┤
                └─ 单击数字 ──▶ 浮卡锁定展开（点浮窗外关闭）

浮卡(372×268) ┌──┬──────────────────────────┐
              │走势│ 金价：大字 + 涨跌 + 三日曲线 │
              │唤醒│ 唤醒定时器：caffeinate      │
              │通知│ 通知：系统/震动/强度/声音/接入 │
              ├──┤                          │
              │⚙ │ 底部：外观设置抽屉（透明度、按钮图标）│
              └──┴──────────────────────────┘
```

- **胶囊浮窗**是唯一常驻元素：金价数字 + 开关按钮。拖动=移动，单击数字=开浮卡，右键=菜单，悬停=毛玻璃 + 自动展开浮卡。
- **浮卡**是左侧三图标 rail + 内容区：金价走势 / 唤醒定时器 / 通知设置。rail 底部一个 14pt 齿轮打开外观抽屉（浮窗透明度、按钮图标、浮卡不透明度），不占菜单项，保持「三个 icon」的约定。
- 浮卡不受鼠标移出影响的前提是已锁定（单击过）；hover 展开的浮卡在鼠标移开 400ms 后自动收起。

## 4. 表面 A：胶囊浮窗

### 4.1 几何

| 项 | 值 |
| --- | --- |
| 尺寸 | 高 28pt，宽自适应（数字 4–7 位 + 按钮），下限 104pt |
| 内边距 | 左 12 / 右 8 / 上下 4 |
| 圆角 | 14pt（= 高/2，纯胶囊） |
| 数字 | 17pt `monospacedDigit` semibold，字距 -0.2 |
| 按钮 | 20×20 点击区，图标 13pt，线宽 1.6 |
| 数字与按钮间距 | 8pt |

宽度随内容变化时用 120ms 动画改 frame，锚点固定在右上角（`setFrameTopLeftPoint`），避免数字位数变化时整块跳动。

### 4.2 背景透明度与文字对比度

用户可调 `t ∈ [0, 100]`，默认 **0**（现状）。

底色绘制：`NSColor(srgb 0.078, 0.086, 0.094, alpha: 0.92 × t/100)`（石墨黑，不是纯黑，避免在黑色壁纸上出现"挖洞"感）。

文字颜色不是硬编码两档，而是按 t 分段 + **始终带反色描边**，保证任意壁纸上可读：

| t 区间 | 数字颜色 | 描边 | 说明 |
| --- | --- | --- | --- |
| 0 – 24 | `ink #0B0C0D` | 白 85%，1.1pt | 纯浮字，靠描边从任何壁纸上"抠"出来 |
| 25 – 55 | `paper #F5F3EE` | 黑 55%，1.0pt | 半透深底，白字 + 黑描边防浅色壁纸 |
| 56 – 100 | `paper #F5F3EE` | 无 | 实底足够，去掉描边让数字更干净锐利 |

过渡带（24–25、55–56）用 160ms 颜色交叉淡入，不做颜色插值（描边与字色指数不同，插值会发灰）。

涨跌色不随 t 变化，但在 t < 25 时提高 8% 亮度，补偿无底色造成的感知压暗：

- 常态 `#8A8A8A` → 急涨 `#F0993C` → 急跌 `#34C38F` → 过期 `#E24B4B`（t<25 时各 +8% L）

### 4.3 悬停毛玻璃

- 结构：`NSVisualEffectView(material: .hudWindow, blendingMode: .behindWindow, state: .active)` 垫在最底层，圆角 14 裁剪，外面再套 0.5pt `white@8%` 高光描边 + `shadow(0, 10, 28, black@32%)`。
- 触发：`NSEvent.mouseLocation` 进入 frame（现有 0.15s hoverClock 已具备），进入 140ms fade in，离开 180ms fade out（离开稍慢，避免边缘抖动闪烁）。
- 毛玻璃与"背景透明度"是**两层独立**的东西：毛玻璃只在 hover 时存在，`t` 控制的是常态底色。hover 时底色按 `max(0.35, t/100 × 0.92)` 兜底，保证毛玻璃下有足够深度。
- 拖动时（`mouseDown` 到 `mouseUp`）强制显示毛玻璃 + 1pt `white@18%` 描边，给"正在搬动"的确认感。

### 4.4 开关按钮（系统唤醒）

- 点击 = toggle caffeinate。**是开关，不是菜单**；右键按钮出快捷菜单直接勾选 `-i/-d/-m/-s/-u` 组合（勾选即写入"上次参数"并立即作用于下一次开关）。
- 默认参数 `-i`（仅防范闲置休眠）。胶囊按钮**永远复用上次选择的参数**：上次勾了 `-d -s`，下次一点就按 `-d -s` 起；控制台唤醒页改动参数同样写回"上次参数"，两处共用一份设置。
- 三态视觉：
  - 关：图标 `white@55%`（t<25 时为 `ink@45%`），无底
  - 开：图标 `gold #E5B45A`，外加 1.5pt 环形进度（半径 11pt，从 12 点逆时针走），环显示剩余时间；无固定时长（`-w PID` 或无限）时环变成缓慢呼吸的实心圆点
  - 启动/停止瞬间：图标 80ms 缩放 0.92 → 1.0（spring），同时触发一次"轻点"震动
- 图标可自定义：SF Symbols 名（内置 12 个候选网格：cup.and.saucer / moon.zzz / bolt / eye / lock / flame / leaf / waveform / cpu / timer / coffee / bed.double）+ emoji + 导入 PNG（着色为单色模板）。选中的图标在"关闭态"显示描边版，"开启态"显示填充版（若该符号有 `.fill` 变体）。

### 4.5 右键菜单

`立即刷新` / `打开控制台` / `唤醒：开/关` / `分隔线` / `退出金价小窗`。菜单本体走系统样式（`NSMenu` 深色），不自绘。

## 5. 表面 B：控制台窗

### 5.1 几何

| 项 | 值 |
| --- | --- |
| 尺寸 | 380 × 300pt，可拖拽右下角缩放到最小 340×260 |
| 圆角 | 16pt |
| 底色 | 石墨 `#141618` @ 0.92，叠 `.hudWindow` 毛玻璃 |
| 描边 | 0.5pt 外 `white@10%` + 内 `black@35%`（双层，模拟玻璃厚度） |
| 整体不透明度 | 用户可调 100% – 50%（作用于 `panel.alphaValue`，滑块步进 1%） |
| 定位 | 相对胶囊浮窗：优先浮窗下方 8pt；屏幕不够则上方；水平优先右对齐 |

### 5.2 侧栏 rail

- 宽 56pt，右侧 0.5pt `white@8%` 分隔线，背景比内容区深一档（`black@18%` 叠加）。
- 三个页面项（自上而下）：`chart.line.uptrend.xyaxis` 金价 / `timer` 唤醒 / `waveform.path` 震动；底部 `gearshape` 设置。
- 单项 40×40 圆角 10pt：默认图标 `white@45%`；hover 图标 `white@85%` + 底 `white@6%`；选中 底 `gold@14%` + 图标 `gold #E5B45A` + 左侧 2pt×16pt 竖条指示器。
- 切换页面：内容区 160ms cross-fade + 8pt 横向位移；rail 指示器 180ms spring 滑到新位置。

### 5.3 页 1 · 金价

```
┌────────────────────────────────────┐
│ 国际现货金                元/克      │  ← 14pt 标题 + 11pt 单位
│ 777.08   ▲+3.42  +0.44%            │  ← 28pt 数字 + 涨跌徽章
│ ┌────────────────────────────────┐ │
│ │      近三日分时曲线（复用）      │ │  ← 复用 TrendView，高 108
│ └────────────────────────────────┘ │
│ 794.46 ─ 773.26 ─ 752.06           │  ← 轴标签
│ 11/20    11/21    11/23   末笔 777 │
└────────────────────────────────────┘
```

- 大数字 28pt semibold monospacedDigit；涨跌徽章 = 胶囊 12% tint 底 + 同色文字（涨橙/跌绿），不填充满色。
- 曲线沿用 `TrendView` 的自绘逻辑，仅换配色并去掉内嵌标题（标题已上移）。

### 5.4 页 2 · 唤醒定时器

```
┌────────────────────────────────────┐
│ 保持系统唤醒                        │
│ ┌──────────┬──────────┐            │
│ │  时间段   │  倒计时   │            │  ← 分段控件
│ └──────────┴──────────┘            │
│ 剩余  02:14:36        ◜◝ 环形进度   │
│ 参数  [i] [d] [m] [s] [u]          │  ← 可多选 chip
│       i=闲置不睡 d=屏幕不睡         │
│       m=磁盘不睡 s=系统不睡 u=声明用户活动│
│ ┌──────────────┬──────────────┐    │
│ │  开始唤醒     │    停止       │    │
│ └──────────────┴──────────────┘    │
│ 子进程 /usr/bin/caffeinate -dimsu   │
└────────────────────────────────────┘
```

- 倒计时模式：`caffeinate -<flags> -t <seconds>`，到点自动结束。
- 时间段模式：选择 `开始—结束`（默认 现在 → 现在+2h），`caffeinate -<flags>` 无 `-t`，由应用在结束时刻 kill。
- 参数 chip 逻辑：`-i`/`-d`/`-m`/`-s` 至少选一个才允许开始；`-u` 需 `-t` 且只在用户空闲时生效（文案注明）。
- 状态机：`idle → starting → running → stopping → idle`，`running` 时按钮区变为"停止"+ 剩余时间；启动失败（找不到二进制/权限）在窗口内显示红字一行，不弹窗。
- 与胶囊按钮共用同一个状态源 `WakeController`，两边同时反映（浮窗环形进度与控制台环形进度同源）。

### 5.5 页 3 · 震动提醒

```
┌────────────────────────────────────┐
│ 触控板震动提醒                      │
│ Turn 完成      [开关]  试听  ⟨双击⟩ │
│ 金价急涨       [开关]  试听  ⟨三连⟩ │
│ 金价急跌       [开关]  试听  ⟨长震⟩ │
│ 定时器结束     [开关]  试听  ⟨双击⟩ │
│ ────────────────────────────────── │
│ 已接入：                            │
│  DSH          ● 未接入    [一键配置]│
│  Claude Code  ● 未接入    [一键配置]│
│  Codex        ● 未接入    [一键配置]│
│ ────────────────────────────────── │
│ 强度 ▁▂▃▄▅  ●●●○○   (默认 中)      │
└────────────────────────────────────┘
```

- 每条事件 = 开关 + 试听 + 预设下拉（轻点 / 双击 / 三连 / 长震 / 心跳）。
- "一键配置"直接改对应工具的配置文件，成功后徽章变 `● 已接入`，并显示改动的文件路径（可点击 `reveal in Finder`）。失败时显示原因（如 Codex 的 `notify` 已被占用）。
- 强度用 5 档点选（映射到 `MTActuationActuate` 的 level 0.35 / 0.5 / 0.65 / 0.8 / 1.0）。

### 5.6 页 4 · 设置

- 浮窗背景透明度 0–100%（滑块，实时预览，左侧数字）
- 控制台不透明度 50–100%（滑块）
- 按钮图标选择器（12 网格 + emoji 输入 + 导入 PNG）
- 按钮行为：固定"系统唤醒开关"（灰显说明，为将来留位）
- 快捷键（可选，v2）：⌃⌥G 打开控制台
- 复位默认值

## 6. 视觉令牌

以下为方向 A（HUD 玻璃）的取值；B/C 方向见 §9 对比。

```
色板
  ink        #0B0C0D   浮字态文字
  paper      #F5F3EE   深底态文字
  graphite   #141618   浮窗/控制台底色（92%）
  rail       #0E1012   侧栏更深一档
  gold       #E5B45A   品牌强调（开关态、选中态）
  curve      #F7C973   曲线主线（沿用现有 accent）
  up         #F0993C   急涨
  down       #34C38F   急跌
  warn       #E24B4B   过期 / 错误
  hairline   white@8%  所有 0.5pt 分隔线

字体
  Display   SF Pro Display Semibold 28 / -0.4 字距
  Number    SF Pro Text Semibold 17（monospacedDigit）
  标题      SF Pro Text Semibold 14
  正文      SF Pro Text Regular 12
  标注      SF Pro Text Regular 11，muted white@55%
  数据轴    SF Mono Regular 10，tabular

间距  4 / 8 / 12 / 16 / 24（8 网格，4 为半格）
圆角  胶囊 14 · 控制台 16 · 卡片 12 · chip 6 · 图标底 10

阴影
  静置        0 4 12  black@22%
  hover       0 10 28 black@32%
  控制台      0 18 48 black@40%
```

## 7. 动效规格

| 场景 | 曲线 | 时长 |
| --- | --- | --- |
| 毛玻璃浮现 | ease-out | 140ms |
| 毛玻璃消退 | ease-in | 180ms |
| 文字颜色档位切换 | cross-fade | 160ms |
| 页面切换 | ease-out + 8pt 位移 | 160ms |
| rail 指示器移动 | spring(0.35, 0.8) | 180ms |
| 按钮按下 | scale 0.92→1.0 spring(0.4, 0.7) | 80ms |
| 数字变化 | 无动画，仅颜色 flash 80ms | — |
| 窗口出现（控制台） | alpha 0→1 + 上移 6pt | 180ms |

原则：所有动效都回答"我刚做了什么"，不做装饰性动画；桌面常驻元素不允许持续动效（呼吸环除外，周期 3s，仅唤醒开启时）。

## 8. 能力实现方案

### 8.1 触控板震动（参考 nospeaker）

技术路径与 `os6/nospeaker` 一致：`dlopen` 私有框架 + 运行时解析符号。

```swift
dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
MTDeviceCreateList() → MTDeviceGetDeviceID → MTActuatorCreateFromDeviceID
MTActuatorOpen → motorPointer = Unmanaged.passUnretained(motor).toOpaque()
MTActuationCreateFromDictionary(dict, 0) → MTActuationActuate(act, motorPointer, 0, level, 0)
```

波形字典（每个"拍"一次调用，一串拍 = 串行 dispatch 定时器）：

```swift
["BaseWaveform": ["Type": "Gaussian", "Amplitude": 0.0, "DurationMS": ms],
 "Tones": [["Type": "Sine", "Amplitude": 1.0, "DurationMS": ms,
            "DelayMS": 0.0, "FrequencykHz": hz / 1000]]]
```

预设（频率 × 时长 × 间隔，最终以实机试听微调）：

| 预设 | 组成 |
| --- | --- |
| 轻点 | 1 × (70Hz, 12ms) |
| 双击 | 2 × (70Hz, 10ms)，间隔 110ms |
| 三连 | 3 × (70Hz, 9ms)，间隔 90ms |
| 长震 | 1 × (45Hz, 240ms) |
| 心跳 | (45Hz,60ms) → 180ms → (45Hz,60ms) → 400ms 循环 3 次 |

降级链：`MultitouchSupport` 缺失 → `NSHapticFeedbackManager.defaultPerformer.perform(.generic/.alignment)` → 静默（仅写日志）。

### 8.2 Hook 接入矩阵

统一出口是一个**独立短进程 CLI**，不依赖 App 常驻、不需要 IPC：

```
/N 国内金价.app/Contents/MacOS/GoldFloat --haptic turn-done
```

| 工具 | 机制 | 落点 | 备注 |
| --- | --- | --- | --- |
| Claude Code | 官方 hooks | `~/.claude/settings.json` → `hooks.Stop[].hooks[] = {type:"command", command:"… --haptic turn-done"}` | 无副作用，可幂等安装与卸载 |
| Codex | `notify` 数组 | `~/.codex/config.toml` → `notify = ["…GoldFloat", "--haptic", "turn-done"]` | 需求方确认：**直接接管，不转发**；原 `SkyComputerUseClient` 项会被替换，安装前备份原文件 |
| DSH | 待落地核对（插件 hook 或会话事件订阅） | 实现阶段按 DSH 插件参考确认 | 若 DSH 无 hook 配置，则用 `@local/dsh-goldfloat` 插件订阅 turn 结束事件调用同一 CLI |

安装器行为：写入前备份原文件（`*.bak-时间戳`），写入后打印改动 diff 摘要；卸载即回滚备份。

### 8.3 caffeinate

- 路径 `/usr/bin/caffeinate`，flags 由 chip 拼装（`-dims`），倒计时追加 `-t N`。
- 子进程用 `Process` 启动，`terminationHandler` 回收；PID 与参数写 `~/Library/Application Support/GoldFloat/wake.json`，App 启动时若发现陈旧 PID 且进程仍存活则接管或杀掉（避免残留导致 Mac 不睡）。
- 时间段模式用一个 `Timer` 到点 `terminate()`；系统休眠/唤醒事件（`NSWorkspace.didWakeNotification`）后重算剩余时间。

## 9. 视觉方向候选

见交付说明（三选一后再落 token）。

## 10. 文件组织

```
src/
  main.swift              入口，组装 NSApplication 与 delegate
  model/
    Quote.swift           行情解析（从 main.swift 抽出）
    Settings.swift        Codable 设置 + UserDefaults 读写
  window/
    CapsulePanel.swift    胶囊浮窗：布局、透明度、对比度、毛玻璃、拖动
    ConsolePanel.swift    控制台窗：rail + 内容区切换
  page/
    PricePage.swift       金价页
    WakePage.swift        唤醒定时器页
    HapticPage.swift      震动提醒页
    SettingsPage.swift    设置页
  feature/
    QuoteFeed.swift       轮询与状态机（原 Delegate 的行情部分）
    WakeController.swift  caffeinate 子进程与状态
    Haptics.swift         私有 API 马达 + 预设 + 降级
    TrendChart.swift      原 TrendView/DayCurve（去标题、换配色）
    HoverTrend.swift      悬停曲线卡
    HookInstaller.swift   Claude/Codex/DSH 配置读写与备份
  ui/
    Tokens.swift          颜色/字体/间距/圆角/阴影常量
    GlassView.swift       NSVisualEffectView 封装 + 描边 + 阴影
    Controls.swift        chip、分段控件、图标按钮、环形进度
```

## 11. 里程碑

| # | 内容 | 验收 |
| --- | --- | --- |
| M1 | 拆模块 + 胶囊浮窗（透明度、对比度、毛玻璃、可自定义按钮图标） | 0/25/55/100% 四档文字都清晰；hover 有玻璃感；按钮可换图标 |
| M2 | 控制台骨架（rail + 四页切换 + 不透明度滑块） | 三页可切，50%/100% 都可用 |
| M3 | 唤醒定时器（caffeinate 双模式 + 浮窗联动环形进度） | 倒计时与时段都能起停，退出无残留进程 |
| M4 | 震动（预设 + 强度 + 三个 Hook 安装器 + 金价急涨急跌触发） | 实机可感知；Claude/Codex 一键接入生效；文件可回滚 |
| M5 | 打磨（间距审计、动效、深浅壁纸回归、README 更新） | 截图走查通过 |

## 12. 待确认

1. 视觉方向 A / B / C（见交付说明）。
2. Codex 的 `notify` 当前被 Computer Use 占用——接受"转发包装"吗？（会改 `~/.codex/config.toml`）
3. 唤醒默认参数：建议默认 `-dimsu`（不睡屏、不睡盘、不睡系统、声明活动），你要不要默认不带 `-d`（允许熄屏）？
4. 曲线浮卡与控制台金价页同时存在，是否保留 hover 曲线浮卡（我倾向保留，它是这个工具的招牌动作）。

## 13. 实现现状（v0.3，2026-11-23）

已按 v0.2 决策落地，并在实机验证中修掉三处问题：

1. **左侧圆角**：浮卡根视图加 `layer.cornerRadius + masksToBounds`，rail 的直角底不再溢出圆角。
2. **浮窗拖动**：`CapsuleView.onMove` 广播 frame，`CardPanel.follow(_:)` 让浮卡与浮窗同步位移。
3. **价格/曲线断流**：东方财富 `push2` 与 `push2his` 会出现连续 SSL 断开（同一 IP 短时间高频请求后被限），因此补了三层容错——
   - 行情：`ulist` → 分时线末笔 → 新浪 `hf_XAU × fx_susdcnh`；失败按 5→10→20→40→60 秒退避。
   - 曲线：`trends2` → 新浪 COMEX 分钟线 × 当前汇率（页脚标「COMEX 备用」）→ 本地缓存曲线；失败 20 秒后自动重试。
   - 胶囊宽度改为固定 122pt，数字位数变化不再导致窗口位移。

另按实机观感调整：底色 alpha 用 `0.94 × t^0.7`（半透明时不发灰）、自绘金色 Toggle 取代 NSSwitch、下拉框去边框、分段控件/图标网格微调。
