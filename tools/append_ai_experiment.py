#!/usr/bin/env python3
"""Append one BattleSim run to design/ai-experiments.md."""
import json
import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 10:
        print("usage: append_ai_experiment.py EXP_LOG TS CHANGE SNAPSHOT "
              "SIM_GAMES SIM_MIRROR SIM_DISP SIM_STRICT TELEMETRY", file=sys.stderr)
        return 2

    exp_log, ts, change, snapshot, sim_games, sim_mirror, sim_disp, sim_strict, telemetry_path = sys.argv[1:10]
    log_path = Path(exp_log)
    text = log_path.read_text(encoding="utf-8")
    nums = [int(m.group(1)) for m in re.finditer(r"^## EXP-(\d+)", text, re.M)]
    exp_tag = f"EXP-{max(nums, default=0) + 1:03d}"

    with open(telemetry_path, encoding="utf-8") as f:
        report = json.load(f)

    suites = report.get("suites", {})
    i3_strict = report.get("i3_strict", False)
    project_root = log_path.parent.parent

    def gate_label(suite_name: str, agg: dict) -> str:
        if suite_name != "mirror":
            return "—"
        eng = float(agg.get("avg_engagement_rate", 0)) * 100
        stall = float(agg.get("avg_stall_rate", 0)) * 100
        rounds = float(agg.get("median_rounds", agg.get("avg_rounds", 0)))
        wr = float(agg.get("ally_win_rate", 0)) * 100
        ap = float(agg.get("avg_ap_utilization", 0)) * 100
        ok = eng >= 90 and stall <= 2 and 8 <= rounds <= 16 and 45 <= wr <= 55 and ap >= 60
        return "PASS" if ok else ("FAIL" if i3_strict else "WARN")

    def rounds_metric(agg: dict) -> float:
        return float(agg.get("median_rounds", agg.get("avg_rounds", 0)))

    def fmt_pct(v: float) -> str:
        return f"{v * 100:.1f}%"

    def row(suite_name: str, label: str) -> str:
        agg = suites.get(suite_name, {}).get("aggregate", {})
        if not agg:
            return f"| {label} | — | — | — | — | — | — | — |"
        return "| {label} | {games} | {rounds:.1f} | {eng} | {stall} | {ap} | {wr} | {gate} |".format(
            label=label,
            games=agg.get("games", "—"),
            rounds=rounds_metric(agg),
            eng=fmt_pct(float(agg.get("avg_engagement_rate", 0))),
            stall=fmt_pct(float(agg.get("avg_stall_rate", 0))),
            ap=fmt_pct(float(agg.get("avg_ap_utilization", 0))),
            wr=fmt_pct(float(agg.get("ally_win_rate", 0))),
            gate=gate_label(suite_name, agg),
        )

    mirror_bc = suites.get("mirror", {}).get("aggregate", {}).get("behavior_counts", {})
    bc_line = "—"
    if mirror_bc:
        bc_line = "move={move} attack={attack} wait={wait} defend={defend} end_turn={end_turn} ability={ability}".format(
            **{k: mirror_bc.get(k, 0) for k in ("move", "attack", "wait", "defend", "end_turn", "ability")}
        )

    mirror_pc = suites.get("mirror", {}).get("aggregate", {}).get("post_contact", {})
    pc_line = "—"
    if mirror_pc and int(mirror_pc.get("ai_unit_turns", 0)) > 0:
        pbc = mirror_pc.get("behavior_counts", {})
        pc_line = (
            f"接敌回合中位={mirror_pc.get('median_contact_round', 0):.0f} "
            f"AP={float(mirror_pc.get('ap_utilization', 0)) * 100:.1f}% "
            f"站桩={float(mirror_pc.get('stall_rate', 0)) * 100:.1f}% "
            f"AP空转={float(mirror_pc.get('ap_unused_rate', 0)) * 100:.1f}% "
            f"Defend轮={float(mirror_pc.get('defend_turn_rate', 0)) * 100:.1f}% "
            f"hold轮={float(mirror_pc.get('hold_stance_turn_rate', 0)) * 100:.1f}% | "
            f"move={pbc.get('move', 0)} attack={pbc.get('attack', 0)} "
            f"wait={pbc.get('wait', 0)} defend={pbc.get('defend', 0)} "
            f"end_turn={pbc.get('end_turn', 0)} ability={pbc.get('ability', 0)}"
        )

    berserk_r = rounds_metric(suites.get("disposition_berserk", {}).get("aggregate", {}))
    guard_r = rounds_metric(suites.get("disposition_guard", {}).get("aggregate", {}))
    disp_delta = abs(berserk_r - guard_r) if berserk_r and guard_r else 0

    summary_lines = []
    mirror_agg = suites.get("mirror", {}).get("aggregate", {})
    if mirror_agg:
        check_failures = []
        eng = float(mirror_agg.get("avg_engagement_rate", 0))
        if eng < 0.90:
            check_failures.append(f"交火率 {eng * 100:.1f}% < 90%")
        stall = float(mirror_agg.get("avg_stall_rate", 0))
        if stall > 0.02:
            check_failures.append(f"站桩率 {stall * 100:.1f}% > 2%")
        rounds = rounds_metric(mirror_agg)
        if rounds < 8 or rounds > 16:
            check_failures.append(f"中位回合 {rounds:.1f} ∉ [8,16]")
        wr = float(mirror_agg.get("ally_win_rate", 0))
        dwr = float(mirror_agg.get("decisive_ally_win_rate", wr))
        draws = int(mirror_agg.get("draws", 0))
        if wr < 0.45 or wr > 0.55:
            check_failures.append(
                f"友胜率 {wr * 100:.1f}% ∉ 45~55%（decisive {dwr * 100:.1f}%，draws {draws}）"
            )
        ap = float(mirror_agg.get("avg_ap_utilization", 0))
        if ap < 0.60:
            check_failures.append(f"AP 利用 {ap * 100:.1f}% < 60%")
        summary_lines.append(
            "镜像 §十四 全部达标" if not check_failures else "镜像未达标：" + "；".join(check_failures)
        )

    rel_snap = str(Path(snapshot).relative_to(project_root)) if Path(snapshot).is_absolute() else snapshot

    entry = f"""
## {exp_tag} — {ts}

**改动**：{change}

**配置**：`SIM_GAMES={sim_games}` `SIM_MIRROR_GAMES={sim_mirror}` `SIM_DISPOSITION_GAMES={sim_disp}` `SIM_I3_STRICT={sim_strict}`

### 指标

| Suite | 局数 | 中位回合 | 交火率 | 站桩率 | AP利用 | 友胜率 | §十四 |
|---|---:|---:|---:|---:|---:|---:|---|
{row("demo", "demo 不对称")}
{row("mirror", "mirror 镜像")}
{row("disposition_berserk", "disp berserk")}
{row("disposition_guard", "disp guard")}

### behavior_counts（mirror 汇总）

`{bc_line}`

### 接敌后诊断（mirror 汇总，最近敌我距≤2 起）

`{pc_line}`

### 倾向差异

berserk 中位回合 {berserk_r:.1f} vs guard {guard_r:.1f}（差 {disp_delta:.1f}，目标 ≥3）

### 摘要

{chr(10).join("- " + s for s in summary_lines) if summary_lines else "- （无 mirror 数据）"}

**快照**：`{rel_snap}`

---

"""
    log_path.write_text(text.rstrip() + "\n" + entry, encoding="utf-8")
    print(f"   appended {exp_tag} → design/ai-experiments.md")
    print(exp_tag)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
