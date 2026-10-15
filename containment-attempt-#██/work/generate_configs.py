"""Write editable project data. This is file generation, not a game/test runner."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "configs"
OUT.mkdir(exist_ok=True)

def write(name, content):
    (OUT / name).write_text(json.dumps(content, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

def table(description, items):
    return {"schema_version": 1, "description": description, "items": items}

def effect(stat, op, value):
    return {"stat": stat, "op": op, "value": value}

stat_rows = [
    ("max_hp", "生命上限", "float", 100, 1, 10000),
    ("damage", "弹丸伤害", "float", 12, 0.1, 10000),
    ("fire_interval", "攻击间隔（秒，越小越快）", "float", 0.52, 0.12, 10),
    ("speed", "移动速度（像素/秒）", "float", 235, 20, 400),
    ("projectiles", "每次攻击的弹丸数", "int", 1, 1, 5),
    ("pierce", "额外穿透数量", "int", 0, 0, 3),
    ("armor", "伤害减免比例，0.08 为 8%", "float", 0, 0, 0.48),
    ("magnet", "零件吸取范围（像素）", "float", 92, 25, 330),
    ("range", "自动瞄准和弹丸最大射程", "float", 690, 30, 2000),
    ("bullet_speed", "弹丸速度（像素/秒）", "float", 610, 50, 2000),
    ("spread_angle", "相邻弹丸夹角（弧度）", "float", 0.15, 0, 1.5),
    ("dash_speed", "冲刺速度（像素/秒）", "float", 690, 100, 1500),
    ("dash_duration", "冲刺持续时间（秒）", "float", 0.17, 0.02, 1),
    ("dash_cooldown", "冲刺冷却时间（秒）", "float", 1.4, 0.1, 10),
]
write("stats.json", table("已接入的角色战斗属性。新增属性还需要实现对应游戏逻辑。", [
    {"id": key, "name": title, "type": kind, "default": default, "min": low, "max": high}
    for key, title, kind, default, low, high in stat_rows
]))

write("weapon_categories.json", table("武器品类编号是角色 buff/debuff/禁用列表的引用来源。", [
    {"id": "WC001", "name": "实弹", "description": "单发、连发等动能弹丸武器"},
    {"id": "WC002", "name": "散射", "description": "多弹丸、扇形弹道武器"},
    {"id": "WC003", "name": "能量", "description": "能量武器品类；当前示例仍使用弹丸行为"},
    {"id": "WC004", "name": "生物", "description": "生物武器品类预留"},
]))

write("weapons.json", table("当前实现 projectile_auto 行为。品类只决定分类和角色适配，不自动赋予新的攻击行为。", [
    {"id": "WPN001", "name": "标准回收枪", "enabled": True, "category_id": "WC001",
     "behavior": "projectile_auto", "description": "自动瞄准最近的异常体。", "effects": []},
    {"id": "WPN002", "name": "扩散回收器", "enabled": True, "category_id": "WC002",
     "behavior": "projectile_auto", "description": "散射三枚弹丸，单枚伤害较低。",
     "effects": [effect("projectiles", "add", 2), effect("damage", "multiply", 0.7), effect("fire_interval", "multiply", 1.25)]},
    {"id": "WPN003", "name": "脉冲发射器", "enabled": True, "category_id": "WC003",
     "behavior": "projectile_auto", "description": "可穿透一个目标的能量弹丸。",
     "effects": [effect("pierce", "add", 1), effect("damage", "multiply", 1.2), effect("fire_interval", "multiply", 1.3)]},
    {"id": "WPN004", "name": "活体培养器", "enabled": False, "category_id": "WC004",
     "behavior": "projectile_auto", "description": "未开放的武器样例。", "effects": []},
]))

write("characters.json", table("属性使用 stats.json 默认值，再覆盖 base_stats；后三类规则一律引用 WC 品类编号。", [
    {"id": "CHR001", "name": "回收员", "code": "E–01", "english_name": "RECLAIMER", "enabled": True,
     "description": "标准回收人员。清空房间，回收零件，继续收容。",
     "base_stats": {key: default for key, _, _, default, _, _ in stat_rows},
     "starting_weapon_id": "WPN001",
     "buff_weapons": [{"category_id": "WC002", "effects": [effect("damage", "multiply", 1.15)]}],
     "debuff_weapons": [{"category_id": "WC003", "effects": [effect("fire_interval", "multiply", 1.2)]}],
     "forbidden_weapon_categories": ["WC004"]},
    {"id": "CHR002", "name": "重装员", "code": "E–02", "english_name": "WARDEN", "enabled": False,
     "description": "未开放。较高生命，较低速度。", "base_stats": {"max_hp": 140, "speed": 190},
     "starting_weapon_id": "WPN001", "buff_weapons": [], "debuff_weapons": [], "forbidden_weapon_categories": []},
    {"id": "CHR003", "name": "勘探员", "code": "E–03", "english_name": "SURVEYOR", "enabled": False,
     "description": "未开放。较高速度和回收范围，较低生命。", "base_stats": {"max_hp": 80, "speed": 270, "magnet": 140},
     "starting_weapon_id": "WPN001", "buff_weapons": [], "debuff_weapons": [], "forbidden_weapon_categories": []},
]))

upgrades = [
    ("UPG001", "高压弹头", "伤害", "弹丸伤害 +25%", "damage", "multiply", 1.25, None, 28, 0),
    ("UPG002", "快速循环", "射速", "攻击间隔缩短 15%", "fire_interval", "multiply", 0.85, None, 30, 0),
    ("UPG003", "分裂协议", "弹数", "每次攻击额外发射 1 枚弹丸\n最多 5 枚；形成扇形弹道", "projectiles", "add", 1, 5, 40, 0),
    ("UPG004", "贯穿许可", "穿透", "弹丸可额外穿过 1 个敌人\n最多额外穿过 3 个敌人", "pierce", "add", 1, 3, 32, 0),
    ("UPG005", "应急组织", "生命", "生命上限 +20\n同时恢复 20 点生命", "max_hp", "add", 20, None, 26, 20),
    ("UPG006", "复合外壳", "防御", "伤害减免 +8 个百分点\n最多减免 48%", "armor", "add", 0.08, 0.48, 30, 0),
    ("UPG007", "轻量骨架", "移动", "移动速度 +12%\n上限 400", "speed", "multiply", 1.12, 400, 24, 0),
    ("UPG008", "磁场回收", "回收", "零件吸取范围 +60\n上限 330", "magnet", "add", 60, 330, 20, 0),
]
upgrade_items = []
for uid, name, tag, desc, stat, op, value, cap, price, heal in upgrades:
    modifier = effect(stat, op, value)
    if cap is not None:
        modifier["cap"] = cap
    upgrade_items.append({"id": uid, "name": name, "enabled": True, "tag": tag,
        "description": desc, "effects": [modifier], "heal_on_apply": heal, "price": price})
write("upgrades.json", table("强化可以包含多个属性效果；price 是默认补给价格，奖励记录可覆盖价格。", upgrade_items))

write("rewards.json", table("奖励定义具体发什么；奖励池定义出现范围与权重。kind 支持 upgrade、scrap、heal、weapon、containment。", [
    *[{"id": f"RWD_UPG{i:03}", "name": name, "enabled": True, "kind": "upgrade", "upgrade_id": uid}
      for i, (uid, name, *_rest) in enumerate(upgrades, 1)],
    {"id": "RWD_SCRAP_SMALL", "name": "零件回收", "enabled": True, "kind": "scrap", "amount": 2, "price": 0},
    {"id": "RWD_SCRAP_TANK", "name": "重型零件", "enabled": True, "kind": "scrap", "amount": 3, "price": 0},
    {"id": "RWD_SCRAP_CORE", "name": "核心零件", "enabled": True, "kind": "scrap", "amount": 30, "price": 0},
    {"id": "RWD_ROOM_CLEAR", "name": "区域净化奖金", "enabled": True, "kind": "scrap", "amount": 8, "price": 0},
    {"id": "RWD_MEDICAL", "name": "应急医疗", "enabled": True, "kind": "heal", "amount": 35, "price": 12},
    {"id": "RWD_WPN002", "name": "扩散回收器", "enabled": True, "kind": "weapon", "weapon_id": "WPN002", "price": 45},
    {"id": "RWD_WPN003", "name": "脉冲发射器", "enabled": True, "kind": "weapon", "weapon_id": "WPN003", "price": 45},
    {"id": "RWD_CNT002", "name": "静磁芯", "enabled": True, "kind": "containment", "containment_id": "CNT002", "price": 38},
]))
default_pool = [{"reward_id": f"RWD_UPG{i:03}", "weight": 1} for i in range(1, 9)]
write("reward_pools.json", table("同一次选择按权重无放回抽取；默认保持原版的八种强化。可以自行加入武器/收容物奖励编号。", [
    {"id": "POOL_COMBAT", "name": "战斗强化池", "entries": default_pool},
    {"id": "POOL_TREASURE", "name": "探索奖励池", "entries": default_pool},
    {"id": "POOL_SUPPLY", "name": "补给物资池", "entries": default_pool},
]))

write("monsters.json", table("behavior 关联程序实现；外观编号与怪物编号分离，新增相同行为的变体无需新增代码。", [
    {"id": "MON001", "name": "游离体", "enabled": True, "behavior": "chaser", "visual": "chaser",
     "stats": {"hp": 28, "radius": 16, "speed": 80, "contact_damage": 13},
     "scaling": {"hp_per_clear": 4, "speed_per_clear": 4}, "attack": {}, "drop_reward_id": "RWD_SCRAP_SMALL"},
    {"id": "MON002", "name": "喷射体", "enabled": True, "behavior": "shooter", "visual": "shooter",
     "stats": {"hp": 28, "radius": 16, "speed": 54.4, "contact_damage": 13},
     "scaling": {"hp_per_clear": 4, "speed_per_clear": 2.72},
     "attack": {"approach_distance": 285, "retreat_distance": 165, "interval": 2.5, "bullet_speed": 190, "damage": 11},
     "drop_reward_id": "RWD_SCRAP_SMALL"},
    {"id": "MON003", "name": "聚合体", "enabled": True, "behavior": "chaser", "visual": "tank",
     "stats": {"hp": 75.6, "radius": 24, "speed": 41.6, "contact_damage": 13},
     "scaling": {"hp_per_clear": 10.8, "speed_per_clear": 2.08}, "attack": {}, "drop_reward_id": "RWD_SCRAP_TANK"},
    {"id": "MON_CORE", "name": "异常核心", "enabled": True, "behavior": "boss_radial_charge", "visual": "boss",
     "stats": {"hp": 760, "radius": 43, "speed": 50, "contact_damage": 20},
     "scaling": {"hp_per_clear": 55, "speed_per_clear": 0},
     "attack": {"initial_interval": 1.6, "phase_threshold": 0.5, "bullet_count": 10, "enraged_bullet_count": 14,
                "interval": 2.8, "enraged_interval": 2, "bullet_speed": 155, "damage": 15,
                "charge_warning": 0.85, "charge_duration": 0.5, "charge_speed": 430},
     "drop_reward_id": "RWD_SCRAP_CORE"},
]))

write("containments.json", table("hostile 是需击败的收容对象，artifact 是可领取的一次性被动物品；普通怪物和收容对象分别定义。", [
    {"id": "CNT001", "name": "异常核心", "enabled": True, "kind": "hostile", "code": "CA–001", "risk_class": "失控",
     "description": "设施中央的异常聚合核心。", "monster_id": "MON_CORE", "effects": [], "heal_on_apply": 0},
    {"id": "CNT002", "name": "静磁芯", "enabled": True, "kind": "artifact", "code": "CA–002", "risk_class": "稳定",
     "description": "回收范围 +60\n伤害减免 +8 个百分点", "tag": "收容物", "unique": True,
     "effects": [effect("magnet", "add", 60), effect("armor", "add", 0.08)], "heal_on_apply": 0},
]))

write("rooms.json", table("房型控制战斗、锁门、奖励与补给。具体坐标写在 floors.json。", [
    {"id": "ROOM_ENTRY", "name": "入口", "kind": "start", "title": "入口 / 安全区域", "map_symbol": "S", "cleared_on_entry": True, "lock_until_clear": False},
    {"id": "ROOM_COMBAT", "name": "隔离室", "kind": "combat", "title": "隔离室 / 清除异常体", "map_symbol": "·", "cleared_on_entry": False, "lock_until_clear": True,
     "waves": {"count": 2, "initial_delay": 0.7, "between_delay": 1.5, "base_count": 5, "extra_per_wave": 1, "extra_per_clear": 1, "clear_bonus_cap": 5,
               "monster_cycle": ["MON001", "MON001", "MON001", "MON002", "MON003"]},
     "clear_reward_id": "RWD_ROOM_CLEAR", "choice_pool_id": "POOL_COMBAT", "choice_count": 3},
    {"id": "ROOM_SUPPLY", "name": "补给站", "kind": "supply", "title": "补给站 / 回收终端", "map_symbol": "+", "cleared_on_entry": True, "lock_until_clear": False,
     "shop": {"pool_id": "POOL_SUPPLY", "slots": 3, "reroll_cost": 6, "reroll_increment": 3, "medical_reward_id": "RWD_MEDICAL", "medical_uses": 1}},
    {"id": "ROOM_TREASURE", "name": "封存仓", "kind": "treasure", "title": "封存仓 / 探索奖励", "map_symbol": "?", "cleared_on_entry": True, "lock_until_clear": False,
     "choice_pool_id": "POOL_TREASURE", "choice_count": 3},
    {"id": "ROOM_CORE", "name": "收容核心", "kind": "boss", "title": "收容核心 / 最终区域", "map_symbol": "!", "cleared_on_entry": False, "lock_until_clear": True,
     "containment_id": "CNT001", "required_combat_clears": 4},
]))
cells = []
for y in range(3):
    for x in range(4):
        room_id = {(0, 0): "ROOM_ENTRY", (3, 0): "ROOM_CORE", (0, 1): "ROOM_SUPPLY", (2, 2): "ROOM_TREASURE"}.get((x, y), "ROOM_COMBAT")
        cells.append({"position": [x, y], "room_id": room_id})
write("floors.json", table("显式坐标定义一层连通设施；可增删房间或改变房型。", [
    {"id": "FLOOR001", "name": "第九设施", "start_position": [0, 0], "cells": cells}
]))

write("balance.json", {"schema_version": 1, "description": "与内容无关的全局战斗参数，单位为秒或像素。",
    "default_character_id": "CHR001", "default_floor_id": "FLOOR001",
    "combat": {"entry_invulnerability": 1, "hit_invulnerability": 0.75, "door_cooldown": 0.9, "door_trigger_distance": 39,
               "spawn_margin": 55, "spawn_min_distance": 240, "spawn_position_attempts": 24,
               "enemy_initial_attack_min": 1, "enemy_initial_attack_max": 2.5, "hostile_bullet_lifetime": 7,
               "pickup_radius": 25, "pickup_speed": 340}})

write("manifest.json", {"schema_version": 1, "description": "新增配置表时在此注册；各表 id 独立且稳定，不使用数组下标作为引用。",
    "settings": "balance.json", "tables": {name: name + ".json" for name in [
        "stats", "weapon_categories", "weapons", "characters", "upgrades", "rewards", "reward_pools", "monsters", "containments", "rooms", "floors"]}})
