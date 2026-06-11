# 音频系统设计 v0.1（音乐 + 音效）

> **设计目的**：唐代边军战棋的听感分层——战场氛围、脚步、战斗反馈——在 **零侵权风险** 前提下落地。  
> **策略**：战斗短音效以 **程序生成** 为主（`CombatAudio`）；长音频（BGM / 氛围 loop）以 **自有 AI 创作 + 可商用库** 为辅。  
> **参考（仅设计，不拷素材）**：Battle Brothers 事件分层与命名规律，见本文 §五。

---

## 一、资产来源与合规

| 来源 | 用途 | 合规要求 |
|------|------|----------|
| **程序生成** | 战斗 SFX、脚步 | 无授权问题；代码即资产 |
| **MakeBestMusic（AI）** | BGM、战场氛围、可选短号 | 须确认平台 **商用/游戏内嵌** 条款；导出后本地归档并填 §三 登记表 |
| **CC0 / 商用音效库** | 补充脚步、环境 one-shot | 保留 license 截图或 PDF |
| **自录 Foley** | 后续打磨 | 工作-for-hire / 自有版权 |
| **他作解包（如 BB）** | **仅本地试听、对规格** | ❌ 不得进入 `assets/`、不得进 git、不得打进发行包 |

发行前每条进包的 wav/ogg 须在 **§三 资产登记表** 有对应行。

---

## 二、听感分层（目标规格）

```
战场氛围 bed（loop，-12~-18 dB）── 风、远鼓、营地杂音
        ↓ duck 战斗高峰
移动层 ── 每格一步，地形 × 重量 × 左右脚 pitch 微扰
        ↓
战斗层 ── 挥砍/命中分轨（程序生成）
        ├── miss      短风声
        ├── blocked   闷盾
        ├── armor     破甲、无 HP 伤害
        ├── damage    见血（强度随伤害）
        ├── crit      damage + 金属亮峰
        └── death     下行尾音
音乐层 ── 战术 BGM（AI / 库），与氛围二选一或叠加（待混音）
```

**风格锚点**：硬核、干燥、中世纪边军；避免现代合成 Lead、过度 reverbed trailer 感。  
**与 BB 差异**：可用唐代动机（低号区、可选三音句）；不必模仿 BB 单声短号，但 **事件触发时机** 可对齐。

---

## 三、资产登记表

> 新增/替换音频时 **先登记再进 `assets/audio/`**。  
> `本地路径` 相对于仓库根目录。

### 3.1 音乐（BGM / 长氛围）

| ID | 标题 | 来源 | 授权 | 链接 | 本地路径 | 用途 | 状态 | 备注 |
|----|------|------|------|------|----------|------|------|------|
| `bgm_mbm_001` | *（待填：生成后作品名）* | MakeBestMusic AI | *待确认 Terms* | [分享页](https://makebestmusic.com/s/Lfgzls9k?pid=invite&source=makebestmusic) | `assets/audio/music/` *待导入* | 战术战斗 BGM 候选 | 🟡 已创作，待导出归档 | 2026-06-11 记录；分享链打开曾显示 Music not found，**请以本地下载文件为准** |
| `bgm_menu_001` | — | — | — | — | — | 主菜单 | ⬜ 未开始 | |
| `amb_battle_001` | — | — | — | — | — | 战场氛围 loop | ⬜ 未开始 | 可与 BGM 分离 |

**MakeBestMusic 归档 checklist**

- [ ] 在平台下载 **WAV/MP3**（优先 WAV 或 48k/44.1k）
- [ ] 阅读 [MakeBestMusic](https://makebestmusic.com) 当前 **Terms / Royalty-Free** 表述并截图存档
- [ ] 文件命名为 `mbm_<简短描述>_<日期>.wav`，放入 `assets/audio/music/`
- [ ] 更新上表「标题」「本地路径」「授权」
- [ ] 在 Godot 中试播：循环点、响度（目标 integrated **-14 ~ -18 LUFS** 战术 BGM）

### 3.2 音效（采样 / 程序）

| ID | 事件 | 实现方式 | 代码 / 路径 | 状态 | 备注 |
|----|------|----------|-------------|------|------|
| `sfx_miss` | 未命中 | 程序生成 | `CombatAudio.play_miss()` | ✅ | |
| `sfx_armor` | 破甲无血 | 程序生成 | `play_armor_hit()` | ✅ | |
| `sfx_damage` | 见血 | 程序生成 | `play_damage(intensity)` | ✅ | |
| `sfx_crit` | 暴击 | 程序生成 | `play_crit()` | ✅ | |
| `sfx_blocked` | 格挡 | 程序生成 | `play_blocked()` | ✅ | |
| `sfx_death` | 死亡 | 程序生成 | `play_death()` | ✅ | |
| `sfx_footstep` | 步行 | 程序生成 | `play_footstep(weight)` | ✅ | 每格一步，`BattleScene` 移动后触发 |
| `sfx_horn` | 开战号角 | — | — | ❌ 已移除 | 2026-06-11：程序版听感不佳，暂不开场播放；日后可用 AI/采样重做 |
| `sfx_ui_*` | UI 点击 | — | — | ⬜ | |
| `sfx_new_round` | 每回合提示 | — | — | ⬜ | 待定 |

---

## 四、当前实现（代码 SoT）

| 项 | 位置 |
|----|------|
| Autoload | `project.godot` → `CombatAudio` |
| 战斗 SFX | `scripts/audio/combat_audio.gd` |
| 合成原语 | `scripts/audio/audio_synth.gd` |
| 触发 | `scripts/core/BattleScene.gd`（攻击结算、移动） |

### 4.1 触发映射

| 游戏事件 | 调用 |
|----------|------|
| 攻击格挡 | `play_blocked()` |
| 攻击 miss | `play_miss()` |
| 暴击 | `play_crit()` |
| HP 伤害 > 0 | `play_damage(hp_dmg/40)` |
| 仅护甲伤害 | `play_armor_hit()` |
| 单位死亡 | `play_death()` |
| 单位移动落格 | `play_footstep(total_weight)` |

### 4.2 无头 / 测试

`OS.has_feature("headless")` 时 `CombatAudio` 不播放，不影响 `tools/smoke.sh` / 单测。

---

## 五、参考调研摘要（Battle Brothers，不引入素材）

> 解包路径（本地参考，**禁止入库**）：`~/Downloads/data_001/sounds/`

| BB 资产 | 时长 | 用途 |
|---------|------|------|
| `new_round_01~03.wav` | ~1.5s | 战术界面每回合短号（随机） |
| `intro_battle.wav` | ~11s | 遭遇战长开场 |
| `combat/*.wav` | 短 | 挥砍/命中分轨；`*_hit_*` 与 whoosh 分离 |
| `movement/movement_{地形}_*.wav` | 短 | 地形脚步 |
| `enemies/*` | — | 怪物 idle/hurt/death |

**程序生成应对齐的设计点**：事件分轨、3 变体随机、pitch/volume 微扰、3D 定位（我们战棋可先立体声无定位）。

---

## 六、目录规范（导入后）

```
assets/audio/
├── music/           # BGM、长 loop（含 MakeBestMusic 导出）
├── ambience/        # 战场/营地氛围 bed
├── sfx/             # 若将来用采样替代程序 SFX
│   ├── combat/
│   ├── movement/
│   └── ui/
└── licenses/        # 平台条款截图、库 license PDF
```

**Git**：仅提交已登记、授权清晰的文件；`licenses/` 与登记表同步更新。

---

## 七、待办（Phase 2 音频）

| 优先级 | 任务 | 验收 |
|--------|------|------|
| P0 | 从 MakeBestMusic **导出并入库** `bgm_mbm_001` | 表 §3.1 填完；`assets/audio/music/` 有文件 |
| P0 | 确认 MakeBestMusic **商用条款** | `licenses/` 有截图 |
| P1 | 战术场景接入 BGM + 氛围 bus（Master / Music / SFX） | 战斗可开关；氛围 ducking |
| P2 | 开战号角（AI 采样或新程序版） | 可选；当前已关闭 |
| P2 | 地形脚步：程序 vs 采样 | 至少 2 种地形可区分 |
| P2 | 写 `design/references/bb-audio-deep-dive.md`（可选） | 事件表与 BB 文件名对照 |

---

## 八、修订记录

| 日期 | 版本 | 说明 |
|------|------|------|
| 2026-06-11 | v0.1 | 初稿：策略、登记表、MakeBestMusic 链接、CombatAudio 映射、BB 参考摘要 |
| 2026-06-11 | v0.2 | 移除开战号角（程序版听感不佳） |
