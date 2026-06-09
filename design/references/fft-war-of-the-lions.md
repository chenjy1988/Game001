# Final Fantasy Tactics: The War of the Lions（PSP 狮子战争）— 调研

> 2007 年 Square Enix 在 PSP 上对 1997 PS1 原版 FFT 的**强化重制**。
> 莎士比亚式古典英语剧本 + 新职业 + 新角色 + CG 动画 + 多人模式。
> **是大多数玩家心中"FFT 决定版"**——但**慢动作 (slowdown) bug** 让它毁誉参半。

## 一、版本概述

| 项 | 内容 |
|---|---|
| 全名 | Final Fantasy Tactics: The War of the Lions（WotL）|
| 平台 | PSP（2007）/ iOS & Android（2011 起，修复了慢动作）|
| 发行商 | Square Enix |
| 监督 | 松野泰己（剧情概念）+ Tactics Ogre 团队成员 |
| 译制总监 | Tom Slattery（莎士比亚式英文翻译，沿用至 2025）|
| 子类 | SRPG，PS1 FFT 的强化重制 |
| 发售 | 2007 年北美 / 欧洲，PSP 后期最受欢迎的作品之一 |

**设计目标**：把 1997 PS1 的 FFT **现代化、补完、扩展**——
> "原版剧本翻译质量参差，没有 CG，没有多人，
> 我们让这部杰作配得上 PSP 的高清屏幕。"
> 设计哲学：**致敬不拘泥**——基本玩法不动，但每一层都加东西。

---

## 二、对比 PS1 原版的 5 大新增

### 2.1 全新莎士比亚式英语翻译（最大胜利）

PS1 原版翻译被广泛批评为"破碎、机械、信息丢失"——
- WotL 重译为**伪伊丽莎白时代英语**（"thou art"、"prithee"、"forsooth"…）
- 与中世纪封建战争主题完美契合
- **沿用至 2025 Ivalice Chronicles 经典模式 + Enhanced 模式**——成为标准
- 这次翻译是 WotL 对 FFT 系列最大的贡献

> 评论原话："读 WotL 剧本就像在读莎翁悲剧——这是 RPG 翻译史上的高峰。"

### 2.2 新增 2 个新职业

| 职业 | 来源 | 特点 |
|---|---|---|
| **Onion Knight（洋葱剑士）** | FF3 致敬 | 装备特殊"洋葱装备"才能解锁全潜力，前期弱、终极强；mastered 后**所有基础属性最高** |
| **Dark Knight（暗黑骑士）** | FF 系列经典 | 解锁条件极苛刻（需精通 Knight + Black Mage + 杀够人）；技能消耗自身 HP，伤害极高 |

→ 都是**"刷成就才能用"**的奖励职业，FFT 老玩家的炫技目标。

### 2.3 新增 2 个客串角色

| 角色 | 来源 | 招募方式 |
|---|---|---|
| **Balthier**（巴尔弗莱）| Final Fantasy XII | 通过新增多关支线 |
| **Luso**（卢索）| Final Fantasy Tactics A2 | 通过新增多关支线 |

→ 跨作客串成为 **FFT 与其他 FF 作品的连接桥梁**。

### 2.4 CG 动画过场

- 全新 **预渲染动画 cutscene**（关键剧情：王朝政变、教会阴谋、最终决战）
- 美术由 Tetsuya Nomura 监修风格统一
- **配乐重新编曲**——崎元仁/岩田匡治的原曲在 PSP 高保真音轨下听感升级
- 这些 CG 在 2025 Ivalice Chronicles 中**保留**（少数被保留的 WotL 资产之一）

### 2.5 多人合作模式（Multiplayer）

- **PSP Ad-hoc 局域联机**——2 人合作打专属副本
- 专属任务：**Brave Story 联机副本**，掉落限定装备
- 是 FFT 系列**唯一一次**正经做多人合作
- **缺点**：联机匹配麻烦，PSP 联机功能本身就小众，**实际玩家比例 < 5%**

### 2.6 其他改动

- **30+ 新道具**（与新职业配套）
- **新支线任务**：Brave Story 系列（Cloud、Beowulf、Reis 等支线在原版基础上扩展）
- **撤销键 / 加速键**——在 PSP 时代 QoL 改进
- **过场动画字幕**

---

## 三、致命缺陷：**慢动作 (slowdown) bug**

这是 WotL **最被诟病的 bug**：

### 现象
- 任何**带特效的法术 / 必杀技**释放时，整个游戏帧率从 30fps **掉到 5-10fps**
- Holy / Ultima / Limit Break 这种重头戏 = 慢动作折磨
- **每一场战斗都要忍受 5-15 次掉帧**

### 原因（社区反向工程）
- WotL 在 PS1 emulation 上跑 PS1 资产 + PSP 新增特效层
- PSP CPU 不够强，无法实时合成
- 不是模拟器问题，**原始硬件就这样**

### 解决方案
1. **PPSSPP（PSP 模拟器）** + 慢动作移除补丁（Archaemic 制作）→ 完美修复
2. **iOS / Android 移动版（2011）** → 全部修复，**这是当今想体验 WotL 的最佳渠道**
3. PSP 物理机 → 必须打补丁

→ **这条 bug 让 WotL 在 PSP 物理机上几乎不可玩**——要 emulator 才能享受。

---

## 四、其他设计批评

### 4.1 PS1 老问题原封不动
- **强制随机遇敌**：未修复
- **无三倍速**：仍只有 1x/2x
- **职业平衡灾难**：Calculator / Mime / Cid 仍然破坏游戏
- **Wiegraf 单挑**陷阱：未修复

### 4.2 多人合作功能限制
- 联机副本数量少
- 装备掉落随机性大，刷取折磨
- PSP 后期玩家流失，联机找不到人

### 4.3 新职业平衡问题
- **Onion Knight 前 60 级几乎无用**——"成就职业"，不是"实战职业"
- **Dark Knight 解锁要刷 30+ 小时**——玩到这时候已经通关了
- → 新职业**为炫技存在**，普通玩家通关流程接触不到

### 4.4 Luso / Balthier 招募时机晚
- 必须打到 Ch3 中段才能招
- 通关流程已经过半，他们更多是"花瓶"

---

## 五、为什么 WotL 仍是大多数玩家心中的 FFT 决定版

虽然有 slowdown bug，但 WotL 是**FFT 内容最完整、最易获取**的版本：

| 维度 | PS1 | **WotL** | Ivalice Chronicles 2025 |
|---|---|---|---|
| 剧本翻译 | 差 | **莎士比亚式（好）** | 沿用 WotL（好）|
| Onion Knight + Dark Knight | ❌ | **✅** | ❌ 砍了 |
| Luso + Balthier | ❌ | **✅** | ❌ 砍了 |
| CG 动画 | ❌ | **✅** | ✅ 保留 |
| 多人合作 | ❌ | **✅** | ❌ 砍了 |
| 全语音 | ❌ | ❌ | ✅ |
| 慢动作 | 无 | **❌ 严重** | 无 |
| QoL（加速 / 跳过 / 撤回）| ❌ | 部分 | ✅ |

→ 矛盾的真相：
- **想要内容最全** → WotL（iOS / Android 修复版）
- **想要 QoL 最好** → 2025 Ivalice Chronicles（但内容缩水）
- **想要原汁原味** → PS1 原版（翻译差）

→ **没有一个版本是完美的**——这是 FFT 玩家社区的永恒话题。

---

## 六、对我们项目的启发

### 6.1 直接拿（哲学层）
- ✅ **翻译/文本质量是 IP 价值的关键**——莎士比亚化的剧本让 FFT 提升一个档次
  - 我们用中世纪雇佣兵 IP，**文风一致性**是低成本高回报的设计
  - 战斗日志、技能描述、武器说明用统一的"中世纪粗砺感"语调
- ✅ **重制时不必照搬**——2025 Ivalice Chronicles 砍掉 Onion Knight / Luso 的决策证明
  - 玩家"想要"的内容 ≠ 设计师"该保留"的内容
  - 我们做 DLC / 内容更新时，**取舍勇气**比"全部保留"重要

### 6.2 直接拿（机制层）
- 🟡 **CG 动画过场**—— 关键剧情的"惊艳节点"是低成本高回报
  - 我们用像素美术，可以做**手绘立绘 + Ken Burns 效果**作为低成本 CG 替代
- 🟡 **联机合作（多人）** —— Phase 4+ 候选，**优先级低**
  - WotL 证明 SRPG 的多人合作是"加分项不是必需"
- ❌ **奖励职业（Onion Knight）** —— 解锁 60 小时后才能用 = 设计失败
  - 任何"奖励"必须在 ~ 50% 流程内可获得

### 6.3 警示（避开它的坑）
- ❌ **slowdown bug** —— 任何动画/特效**必须可中断 / 可加速**
- ❌ **新职业平衡缺失** —— 内容更新时必须做平衡测试，不能"加了就交付"
- ❌ **多人合作的低参与率（5%）** —— 单机内容必须独立成立，多人是奖励
- ❌ **QoL 不重要心态** —— 2007 年 PSP 时代认为可接受的折磨，2025 年都被骂

### 6.4 真正值得借鉴的"WotL 精神"
1. **"重制不是简单画质升级，是文本升华 + 内容补完"** —— 任何项目长线运营都要有"重制的觉悟"
2. **慢动作 bug 是技术债 + 设计妥协的产物** —— 我们的所有性能问题必须在 alpha 阶段就解决
3. **WotL 翻译是 SRPG 史上的高峰** —— 文本不是装饰，是 IP 的灵魂

---

## 七、引用

- RPG Site 三版本对比: https://www.rpgsite.net/feature/18591-final-fantasy-tactics-the-ivalice-chronicles-switch-2-vs-ps5-psp-war-of-the-lions-ps1-features-xbox-pc-steam-differences-compared
- gameland.gg WotL 内容删减: https://gameland.gg/final-fantasy-tactics-ivalice-chronicles-new-cut-content/
- Final Fantasy Wiki 版本差异: https://finalfantasy.fandom.com/wiki/Final_Fantasy_Tactics_version_differences
- TCRF (TheCuttingRoomFloor) WotL 数据: https://tcrf.net/Final_Fantasy_Tactics:_The_War_of_the_Lions
- 慢动作移除补丁: https://www.gamebrew.org/wiki/War_of_the_Lions_Slowdown_Removal_Patch_PSP
- FFHacktics 版本对比 Wiki: https://ffhacktics.com/wiki/FFT_Versions_Comparison
