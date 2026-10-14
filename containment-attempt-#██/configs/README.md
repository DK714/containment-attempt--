# 配置编辑指南

这些文件是实际使用的游戏数据，不是与代码无关的空模板。默认参数、奖励池和房间布局延续第一版。添加内容可以复用现有行为；添加全新机制仍需要写对应逻辑。

## 格式与读取

全部使用 UTF-8 JSON。Godot 用 `FileAccess` 读取 `res://configs/` 中的文件，用 `JSON.parse()` 解析成 Dictionary / Array。这里已提供统一读取器 `scripts/config_database.gd`，使用它不用在每个玩法脚本里重复解析。

配置在启动、进入选人界面和每次开始新局时读取。在一局战斗中修改文件不会立即影响当前这局。修改后停止再运行，或返回选人界面开始新局即可。

在其他脚本中引用的例子：

```gdscript
const ConfigDatabase = preload("res://scripts/config_database.gd")

func read_character() -> void:
    var database = ConfigDatabase.new()
    if not database.load_all():
        push_error("\n".join(database.errors))
        return
    var character = database.get_record("characters", "CHR001")
    var weapon = database.get_record("weapons", character.starting_weapon_id)
    var category = database.get_record("weapon_categories", weapon.category_id)
    print(character.name, " / ", weapon.name, " / ", category.name)
```

主游戏已经持有 `config_db`，其中直接使用同样的 `get_record()`，不需要为每次查询重新加载。这个方法返回数据副本，修改副本不会覆盖配置表；不存在的编号返回空对象。新增表可在 manifest 注册路径，读取器会索引其 id/name，具体如何使用新表仍需接入相应玩法。

JSON 不支持 `//`、`#` 注释，说明写在 `description` 中。字符串必须用双引号，换行用 `\n`，布尔值写 `true` / `false`。虽然 Godot 解析器可容忍部分非标准写法，请保持标准 JSON，方便以后用表格工具生成。

所有内容编号都用字符串：例如 `CHR001`、`WC002`、`UPG003`。编号不是数组下标；重排记录不改变引用。已有编号不要为了改名字而改掉。

各表的通用结构是：

```json
{
  "schema_version": 1,
  "description": "这份配置的用途",
  "items": [
    { "id": "稳定编号", "name": "显示名称" }
  ]
}
```

`manifest.json` 注册文件路径；`balance.json` 是全局设置对象，其余均为 `items` 表。当前支持 schema_version 1。

## 文件职责

| 文件 | 修改内容 | 主要引用 |
| --- | --- | --- |
| `characters.json` | 名称、基础属性、初始武器、擅长/削弱/禁用品类、开放状态 | `stats`、`weapons`、`weapon_categories` |
| `weapon_categories.json` | 武器品类编号与名称 | 无 |
| `weapons.json` | 具体武器、攻击行为、属性修正、品类 | `weapon_categories`、`stats` |
| `stats.json` | 属性名称、默认值、最小/最大值、整数或小数 | 无 |
| `upgrades.json` | 强化名称、多个属性效果、即时回血、默认价格 | `stats` |
| `rewards.json` | 实际发放的强化、零件、治疗、武器、收容物 | `upgrades`、`weapons`、`containments` |
| `reward_pools.json` | 哪些奖励会出现、各自权重 | `rewards` |
| `monsters.json` | 生命、速度、碰撞尺寸、接触伤害、射击、冲刺、成长、掉落 | `rewards` |
| `containments.json` | 敌对收容对象或可领取被动物品、编号、危险等级、效果 | `monsters`、`stats` |
| `rooms.json` | 房型、锁门、波次、怪物循环、奖励池、补给和核心门禁 | `monsters`、`reward_pools`、`rewards`、`containments` |
| `floors.json` | 房间坐标、房型安排、起点 | `rooms` |
| `balance.json` | 默认角色/楼层、受击无敌、拾取和刷怪参数 | `characters`、`floors` |
| `manifest.json` | 上述文件路径 | 配置文件 |

## 角色：品类加成与装备限制

`buff_weapons`、`debuff_weapons`、`forbidden_weapon_categories` 使用的都是 **WC 品类编号**，不是 WPN 具体武器编号。

角色样例中的这段表示：散射伤害增加 15%；能量武器攻击间隔增加 20%，即射速变慢；禁止生物武器。

```json
{
  "buff_weapons": [
    {
      "category_id": "WC002",
      "effects": [{ "stat": "damage", "op": "multiply", "value": 1.15 }]
    }
  ],
  "debuff_weapons": [
    {
      "category_id": "WC003",
      "effects": [{ "stat": "fire_interval", "op": "multiply", "value": 1.2 }]
    }
  ],
  "forbidden_weapon_categories": ["WC004"]
}
```

这些规则已接入装备与奖励筛选，禁止的武器不会出现在该角色的奖励选项中。默认初始回收枪为 WC001，所以新增的示例适配规则不会改变原本初始战斗数值。

最终属性的计算顺序为：`stats 默认值 → 角色 base_stats 覆盖 → 武器 effects → 角色对应品类的 effects → 本局强化和被动物品 effects → 属性全局边界`。各阶段效果按数组顺序执行。换武器时重新计算，旧武器的效果被移除，已获得的本局强化仍然保留。

`base_stats` 可以只写有变化的属性，没写的使用 `stats.json` 默认值。生命是生命上限，受伤后的当前生命单独保存在局内，不写回配置。

角色 `enabled: false` 表示选人页能看到但不能选择。复制一个角色、换唯一 id 并设置 enabled=true，就能加入角色列表；超过三个角色时选人页分页。当前角色外观统一使用原型图形。

## 属性和强化

当前已实现的属性：`max_hp`、`damage`、`fire_interval`、`speed`、`projectiles`、`pierce`、`armor`、`magnet`、`range`、`bullet_speed`、`spread_angle`、`dash_speed`、`dash_duration`、`dash_cooldown`。

- `armor` 为比例：0.08 表示减伤 8%，上限必须小于 1。
- `fire_interval` 为秒，减小意味着攻击更快。
- `projectiles`、`pierce` 是整数，其他属性可用小数。
- `spread_angle` 为相邻弹丸的夹角，单位弧度。
- 距离和速度采用游戏画布的像素单位；时间采用秒。
- `effects` 中 `op: add` 表示加值，`multiply` 表示乘数；乘数必须大于 0。
- `cap` 可选，限制这项正向效果的上限；已到达该上限时不会把更高的现有属性压低。
- `heal_on_apply` 为领取时的即时治疗量，和增加生命上限分开配置。

例如一项同时加伤害、降低移速的强化：

```json
{
  "id": "UPG009",
  "name": "超载组件",
  "enabled": true,
  "tag": "超载",
  "description": "伤害 +40%\n移动速度 -10%",
  "effects": [
    { "stat": "damage", "op": "multiply", "value": 1.4 },
    { "stat": "speed", "op": "multiply", "value": 0.9 }
  ],
  "heal_on_apply": 0,
  "price": 35
}
```

把它追加到 `upgrades.json` 的 items 后，还需要创建奖励并加入奖励池。只添加一项强化定义不会自动让它出现。

## 奖励与奖励池

在 `rewards.json` 添加：

```json
{
  "id": "RWD_UPG009",
  "name": "超载组件",
  "enabled": true,
  "kind": "upgrade",
  "upgrade_id": "UPG009"
}
```

然后在想出现的 `reward_pools.json` 池的 entries 中追加：

```json
{ "reward_id": "RWD_UPG009", "weight": 2 }
```

权重是相对值：在其他条件相同时，2 比 1 更容易抽到。按权重抽取，单次三选一不重复；不同奖励编号指向同一内容也不会占两张卡。属性已达到上限、满血时的治疗、角色禁止的武器、已拥有的唯一物品会被筛掉。可用奖励少于三个时显示实际数量，没有可用奖励时提供继续探索按钮。

奖励 kind 的字段：

| kind | 必填引用/参数 | 发放方式 |
| --- | --- | --- |
| `upgrade` | `upgrade_id` | 永久作用于本局的属性修正 |
| `weapon` | `weapon_id` | 替换当前单把武器；不是多武器槽 |
| `containment` | `containment_id` | 领取 artifact 被动物品 |
| `scrap` | `amount` | 增加本局零件 |
| `heal` | `amount` | 立即恢复生命 |

奖励可以写 `price` 覆盖默认价格。强化奖励未写 price 时沿用强化的价格。name/description 可用于同一内容的不同包装。

默认三个池仍只包含原版八种强化。已经提供可直接加入池的例子：

- `RWD_WPN002`：扩散回收器，用来观察散射品类 buff。
- `RWD_WPN003`：脉冲发射器，用来观察能量品类 debuff。
- `RWD_CNT002`：静磁芯，被动增加吸取范围和减伤，唯一物品。

把对应 reward_id 加入 `POOL_SUPPLY` 或 `POOL_TREASURE` 即可参与抽取，无需修改玩法脚本。

## 怪物、收容物与房间

怪物的 `behavior` 是已实现的行为编号：`chaser` 追击、`shooter` 远程、`boss_radial_charge` 弹幕加预警冲刺。`visual` 是原型外观编号，支持 `chaser`、`shooter`、`tank`、`boss`。二者分开，例如重型怪物可以复用追击行为。

怪物 hp/speed 的本局成长是：`stats 基础值 + 已清除战斗房数 × scaling 中的 per_clear 数值`。掉落目前只支持引用 scrap 奖励。

收容物 kind 为 `hostile` 时引用 monster_id，核心房再通过 containment_id 引用它；kind 为 `artifact` 时使用 effects、heal_on_apply、unique，奖励通过 containment_id 引用它。unique=true 的物品领取后不会再次抽到。

战斗房的 `waves.monster_cycle` 是循环刷怪列表，可以重复编号提高该种怪物的数量。每波数量为：

`base_count + min(已清房数, clear_bonus_cap) × extra_per_clear + 当前波次 × extra_per_wave`

当前波次从 1 开始。count 控制波数，initial_delay/between_delay 控制间隔。

坐标放在 `floors.json`，上下左右差 1 的两个坐标是相邻房间。新增已有房型只需添加 position/room_id 条目。当前仍是单层流程，恰好一个核心房，起点必须是 start 房型。房间须连通，且核心门禁之前能到达的战斗房数量要满足解锁要求。小地图会根据坐标范围缩放。

当前奖励选择和补给界面支持 1–3 个栏位；更高数量要先扩展界面。新增房型、激光/近战等全新攻击行为、触发型被动、多层流程仍需程序实现，不能只填一个陌生 behavior 名称。

## 错误与导出

读取器检查文件格式、schema_version、必填类型、重复编号、引用存在性、部分数值边界、品类规则冲突、初始武器资格、地图连通性与门禁可达性。错误在游戏的配置错误页和 Godot 输出中显示。修正后可点击“修改后重试”。它不替代完整编辑器或正式 JSON Schema 工具。

已提供 macOS 导出预设，`include_filter="configs/*.json"` 让原始 JSON 随包导出，以便 FileAccess 读取；新增其他平台预设时也要设置此过滤条件。`work/` 是旧版备份和一次性迁移资料，排除在导出之外。没有执行导出，也没有安装或运行导出模板。

读取方式的官方说明：[JSON](https://docs.godotengine.org/en/stable/classes/class_json.html)、[FileAccess](https://docs.godotengine.org/en/stable/classes/class_fileaccess.html)。本次按要求只改写文件与静态检查，没有启动引擎或运行测试。
