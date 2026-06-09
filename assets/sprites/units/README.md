# 单位 Sprite 素材目录

游戏会在这里按 **武器类型 + 阵营色** 自动加载 PNG。

## 命名约定（一一对应）

| 武器 id | sprite 前缀 | 友方文件名（蓝） | 敌方文件名（红） |
|---|---|---|---|
| `short_sword` | `warrior`   | `warrior_blue.png`   | `warrior_red.png`   |
| `war_hammer`  | `hammerman` | `hammerman_blue.png` | `hammerman_red.png` |
| `dagger`      | `rogue`     | `rogue_blue.png`     | `rogue_red.png`     |
| `spear`       | `spearman`  | `spearman_blue.png`  | `spearman_red.png`  |
| `battle_axe`  | `axeman`    | `axeman_blue.png`    | `axeman_red.png`    |

> 找不到对应文件时，自动回退到代码里的程序化人形绘制，不会报错。

## 推荐素材包（CC0 / 免费可商用）

1. **Kenney - Tiny Battle** —— https://kenney.nl/assets/tiny-battle
   - 顶视战旗风小人，最贴合本游戏
   - 解压后在 `PNG/Default size/` 目录挑兵种 → 复制 → 重命名到上表

2. **Kenney - Medieval RTS** —— https://kenney.nl/assets/medieval-rts
   - 顶视中世纪兵种，已自带蓝/红阵营色

## 调整显示大小

如果素材太大/太小，改 `scripts/core/Unit.gd` 顶部：

```gdscript
const SPRITE_DISPLAY_SIZE: float = 36.0   # 单位贴图直径（像素）
```
