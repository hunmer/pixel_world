# 生态配置说明

地图生成运行时读取 [`ecosystems.json`](./ecosystems.json)。配置分为三层：

- `generation`：全局地形生成参数。公共 Voronoi 地貌负责连续世界骨架，`biome_profiles` 可为特定气候叠加独立地形表现。
- `species`：稳定的物种 ID、资源目录、动画和行为；`ambient` 用于不占动物格的环境生物。
- `ecosystems`：一个格子属于什么生态，以及该生态允许生成哪些动植物和环境生物。

## 资源目录

```text
meowa_tiles/
  terrain/
  animals/<species_id>/
  plants/
  trees/
  decorations/
```

所有 tile 文件和目录统一使用英文小写 `snake_case`；稳定 species ID 尽量与文件名一致。乔木放在 `trees/`，活体灌木、草本、花卉、仙人掌和水生植物放在 `plants/`，树桩、石块等非生长性自然物件放在 `decorations/`。

每个静态生态对象必须声明 `layer`：

- `tree`：乔木和大型枯树，保持较低密度。
- `ground_cover`：草丛、野花、低矮灌木和水生植物，可高密度散布。
- `decoration`：树桩、石块、仙人掌和龙舌兰等视觉地标，通常比地被稀少。

每种动物使用独立目录。`actions` 中的 `file` 是相对于该动物 `directory` 的路径；静态图片省略 `frame_size`，图集动画则配置 `frame_size`、`columns`、`frames`、`fps` 和 `loop`。

`foot_offset_y` 用于补偿图集单帧底部的透明留白，使实体脚底仍然落在地表脚点；没有留白时省略或设为 `0`。

`movement` 决定地图移动时播放哪个动作：

- `idle_action`：停止时播放的动作。
- `move_action`：移动时播放的动作。
- `duration`：正常移动一格的秒数；逃跑会在此基础上加速。
- `move_steps`：一次行动段连续移动的最少/最多格数；普通动物走完整段才回到 idle。
- `step_pause_seconds`：同一行动段相邻两格间的短暂停顿范围，期间保持 move 动作且不重播首帧。
- `sort_switch_progress`：可选。跳跃类动物在该进度从起点地块的遮挡值切换到目标地块；不配置时平滑插值。

`behavior` 当前支持：

- `wander`：自由漫游。
- `near_water`：倾向水域，但只在陆地岸边漫游，不会进入水格。
- `avoid_snow`：漫游时远离雪地。
- `prefer_snow`：倾向留在雪地；逃离玩家时仍可短暂越过生态边缘。

## 生态匹配

`ecosystems` 是有序数组，按从上到下的顺序匹配，第一个命中的生态生效。因此更具体的 `water`、`shore` 等规则应放在普通陆地规则之前。没有规则命中时使用根节点的 `default_ecosystem`。

沙漠进一步区分核心、泥土过渡带及各自的水域/岸边规则。`desert_water`、`desert_transition_water`、`desert_shore`、`desert_transition_shore` 必须排在对应的通用 `water`、`shore` 规则前，避免绿洲和缓冲区长出温带荷叶、柳树、樱花和紫花。

`match` 支持：

- `water`、`shore`
- `biome`：`plains`、`desert`、`desert_transition`、`snow`
- `landform`：单个 ID 或 ID 数组
- `minimum_level`、`maximum_level`

每个生态的 `flora`、`fauna` 和 `ambient` 都是生成规则数组。`flora` 规则必须声明与物种一致的 `layer`；规则中的 `species` 引用 `species` 下的稳定 ID，数组顺序和重复项都参与物种权重，重复项不要随意去重。

`fauna.distribution` 把动物按社会单元生成，而不是逐格独立散布：

- `anchor_spacing`：群落领地粗网格间距；每个领地最多一个确定性锚点，是控制总体密度的主要参数。
- `anchor_jitter`：锚点在领地中央可抖动的比例。
- `anchor_search_radius`：可选。仅用于河流等狭窄生境，在领地锚点附近确定性寻找最近的合法格；不会退化为逐格随机生成。
- `count`、`radius`：一个社会单元的数量范围与出生半径。狗、狐狸使用 `[1,1]`，猪和青蛙为小群，狼为 7–8 只狼群。
- `single_species`：可选。先按权重为整个群体选择一种主物种，再填满成员；当前金鱼群用它保证一群鱼保持同一品种，而不同水域仍有品种变化。
- `social_radius`：漫游时允许群成员自然散开的半径，越界后会温和趋回当前群心；逃离玩家时该约束暂时让位。
- `same_ecosystem`：群成员是否必须落在与锚点相同的生态内。
- `requires_water_within`：可选。青蛙群锚点附近必须存在水域。
- `substitution`：可选。在不增加群总数的前提下替换少量成员；当前狼群最多用一只哈士奇替换一只狼。

群体会等当前流式窗口的地形、树木和装饰全部生成后再原子放置；可用位置不足最小数量时整群跳过，避免半支狼群或动物与植物重叠。群锚点、成员位置和替换关系都由世界种子确定。
已经完整加载过的领地会同时缓存“生成成功”和“确定不生成”的规划结果，并由有界 LRU 淘汰；角色每移动一格时不会重复扫描同一个无效水域领地。

水域动物使用同一套 fauna 与行为系统，但必须显式声明 `allowed_surfaces: ["water"]`。当前温带 1–3 层浅水生成 2–3 条同品种金鱼，温带 1–5 层水域仅低频生成 2–3 条鲫鱼，寒冷 2–5 层水域生成 2–4 条鲑鱼。鱼只有一个持续循环的 `swim` 动作，停留和移动期间都不会切换姿态。鱼素材通过 `source_faces_right: true` 声明原图朝右，向左游时会在起步前镜像；较长的 `move_steps` 与 `direction_persistence` 让同一行动段持续游动并优先保持原方向。`minimum_water_clearance: 1` 与同名行为约束保证出生和漫游位置的四个正交邻格也都是水；鱼不会贴岸或游上陆地。鱼群仍按稀疏领地生成，因此连续水域覆盖的领地越多，鱼群自然越多，小池塘则只有少量甚至没有鱼。鱼身使用水线分段的前景水层 shader：背部和鱼鳍仍能辨认，主体随水深受到更强的蓝色遮挡。

三层分别使用 `tree_placement`、`ground_cover_placement`、`decoration_placement` 噪声。树木保留原植被噪声的 seed 和频率；草花使用更高频率形成细碎自然斑块；装饰物使用中尺度噪声。每层的 `dominant_chance` 独立控制局部优势种：树木保持明显群落，地被降低优势种比例以避免同一草丛或花朵铺满画面。每条规则还可用 `noise_above` 覆盖该层的默认阈值，再由 `chance` 控制斑块内部密度。

同一格允许三层分别产生候选，但运行时会按 `generation.flora.conflict_seed` 做一次确定性随机选择，最终最多摆放一个静态生态对象。候选会先稳定排序，因此相同世界种子在流式卸载、重载后仍得到同一结果；可选的 `conflict_weight` 默认是 `1.0`。

当前耐旱植物中，两种龙舌兰和多种仙人掌主要分布在沙漠核心，绿洲外围只保留少量花仙人掌和小型龙舌兰；新增的棕榈只进入极低频的沙漠岸边树木池，干枯草甸和枯树变体进入沙漠、过渡带及绿洲对应池。`dry_shrub_small` 在干裂土过渡带权重更高，`twisted_dead_tree` 是稀有沙漠树木。偏黄色的 `mossy_boulder_large` 只作为低频沙漠岩石出现，干裂土过渡带更少；温带岸边与湿地只使用更小的 `mossy_boulder_small`。

温带树木按习性拆成阔叶、针叶和枯树规则：枫树、苹果树、细白桦和小樱花补充阔叶变化，新松树与小蓝杉补充丘陵针叶变化，枯树在普通平原仍极罕见、在湿地略多。普通青草和野花分别使用较低概率散布；蘑菇只加入原本低频的温带湿润地被池，并通过物种 `habitat` 要求周围 9×9 逻辑格内存在最终树木候选。三种成簇蘑菇的权重高于单株松茸，避免小范围内只反复看到同一种；空旷处原本抽中的蘑菇会确定性替换为同层圆草丛，不删除候选、不改变冲突权重或地被总密度。雪原新增三种雪松和两种雪草变体，但仍复用既有低密度树木/地被规则；两种雪地树桩只进入低密度装饰层。

扩充物种时只调整既有规则的 `species` 数组，不新增生成规则，也不修改 `chance`、`noise_above`、`placement_seed`、分层噪声或冲突权重。生态契约固定校验 seed 42、半径 256 下的三层对象总量与温带子集计数，确保新增视觉变体不会改变已经调好的疏密度。

萤火虫属于 `ambient`，不会占用动物格或进入漫游系统。当前只在温带岸边，以及确实生成了地面植物的温带/沼泽格出现；雪原、沙漠、高山和水格不会生成。`max_visible` 限制可见虫数，`max_lights` 单独限制共享环境光数量；每个生态簇最多使用一个动态光源，不会给每只萤火虫都创建灯光。

鸟也属于独立的 `ambient` renderer：温带陆地群落只提供稀疏候选，模块自行播放地面 `walk`、处理玩家靠近后的 `fly` 起飞、飞出视窗回收，以及 20–45 秒间隔的单鸟/2–4 只小群飞越。惊飞后的出生格在流式移出前保持 dismissed，避免刚飞走就原地重生。空中鸟使用屏幕生命周期，地面鸟仍绑定地块列的排序关系。

## 音频配置

[`audio.json`](./audio.json) 控制昼夜音乐、天气环境音与动物叫声。白天、夜晚音乐使用两个低音量循环播放器，并根据昼夜强度做等功率交叉淡化。雨声使用独立循环播放器，基础音量低于 BGM，并在进入或离开雨天时平滑淡入淡出。`species.animals` 中未声明 `metadata.silent: true` 的动物必须在 `animal_sounds.species` 中配置叫声；启动时会校验完整性，允许多个物种复用同一个资源（例如哈士奇复用狗叫）。鱼类当前显式声明为静音，不会为了通过校验而错误复用陆生动物叫声。首次进入 `trigger_radius` 会立即叫一次。若动物持续因玩家追逐而逃跑，则按 `chase_interval_seconds`（当前约 1 秒）重新触发；脱离追逐后恢复独立随机冷却与全局间隔控制的偶发叫声。`polyphony_group` 与 `polyphony_limit` 控制同组声源叠加，当前狼群最多可让 4 只不同的狼同时嚎叫，其他动物仍只保留一路。玩家走远、动物隐藏或流式卸载时会立即停止该声源。

植物 `placement` 支持：

- `ground`：地表。
- `lakebed`：湖底。
- `water_surface`：统一水面高度。

`chance` 可以是 `0..1` 的数字，也可以按 `default`、`mountain_or_rock`、`swamp`、`hills` 分别配置。`noise_above` 的范围是 `-1..1`，值越低，该层允许生成对象的噪声区域越大。

## 沙漠地形模块

`generation.biome_profiles.desert` 不另建一套 Voronoi 地貌，而是在公共连续地貌上叠加一块大型沙漠区域。`desert_regions` 使用单 octave 超低频噪声，只负责形成约百格尺度的连片核心；`desert_edges` 只在边缘加入中尺度形变，让轮廓保持连片但不再是等宽光滑环。

- `region.transition_threshold`：进入泥土缓冲区的区域分数。
- `region.core_threshold`：从泥土缓冲区进入沙漠核心的区域分数。
- `region.edge_amplitude`：沙漠边界受 `desert_edges` 扰动的幅度，只作用于边缘窗口。
- `surface.transition_grass_fraction`：只有缓冲区靠草原的这部分范围允许出现稀草泥土。
- `surface.transition_grass_chance`：允许范围内每格独立、确定性随机出现小草的概率；其余仍以干裂土为底。
- `surface.transition_sand_enter`：沙丘连续形状从核心伸入干裂土的起始分数。
- `surface.transition_rock_noise_above`：过渡带外缘形成岩石露头所需的噪声阈值，向核心逐步收敛到 `rock_noise_above`。
- `surface.rock_noise_above`：沙漠核心内成片岩石露头的阈值。
- `surface.rock_level`：沙漠进入完整岩层的高度；低于此高度时只生成连续岩石露头。
- `terrain.elevation_bias`：归一化高度偏移；正值会消除多数浅水，因此沙漠水域更少。
- `terrain.relief_scale`：压缩原地貌起伏，避免沙漠出现过密陡峰。
- `terrain.dune_amplitude`：独立沙丘噪声的振幅。
- `terrain.peak_scale`：沙漠对公共独立山峰层的保留比例。

区域场低于 `transition_threshold` 时，沙漠 profile 强度严格为零，因此缓冲区之外的公共地貌高度保持不变。阈值之间平滑抬升、压低起伏，进入核心时达到完整沙丘 profile。过渡带柱顶以 `parched_soil.png` 为主，柱体侧面仍使用普通土以避免重复砖墙；外缘保留少量稀草，沙丘与岩石遮罩会以连续斑块伸入干裂土，使草地 → 干裂土 → 沙地/岩石的边界互相穿插，而不是三条平行色带。

深海地貌仍可能穿过沙漠形成少量绿洲或盐湖；核心与过渡带的水格、岸边都有单独生态规则，不生成通用水草与温带岸生植物。沙漠核心的低地以 `sand.png` 为底，并由 `desert_rocks` 形成岩石斑块；达到沙漠岩层高度后整柱使用裸岩。浅水湖底从沙地取色后随水深衰减，高处裸岩不生成苔石。

## 固定种子兼容

以下字段参与确定性生成，修改后同一个世界种子会得到不同结果：

- noise field 的 `seed_offset`、`frequency` 和可选 `octaves`
- `generation.flora` 的层级阈值、`dominant_chance` 和 `conflict_seed`
- biome profile 的地形参数
- landform 数组顺序与 `weight`
- `placement_seed`
- fauna 的 `distribution`、领地间距与群体数量
- 物种池的顺序、长度和重复项
- `pool_id` / `selection_seed_key`

如果只想重命名 `pool_id` 而保持旧地图分布，可保留原来的 `selection_seed_key`。启动时会集中校验配置版本、资源路径、物种引用、行为、放置方式、概率和动画图集范围；错误配置不会进入地图生成。

生态分层契约可用 Godot 直接运行：

```bash
godot --headless --path . --script tests/flora_layers_contract.gd
godot --headless --path . --script tests/terrain_generation_contract.gd
godot --headless --path . --script tests/animal_group_distribution_contract.gd
godot --headless --path . --script tests/audio_system_contract.gd
godot --headless --path . --script tests/depth_of_field_contract.gd
godot --headless --path . --script tests/weather_performance_contract.gd
```

这些契约分别验证生态分层与密度关系、seed 42 地形快照、动物社会单元与流式恢复、靠近/追逐叫声的时序与清理行为、景深/雨雪的渲染层级，以及雨粒子和水波的性能预算。

## 天气配置

[`weather.json`](./weather.json) 独立于地图生成，负责天气表现与切换节奏：

- `auto_interval_seconds`：自动天气决策间隔，默认 60 秒。
- `transition_seconds`：晴、雨、雪之间的平滑过渡时间。
- `manual_transition_seconds`：按快捷键测试天气时的快速过渡时间。
- `rain_start_chance` / `rain_continue_chance`：低海拔自动天气中开始下雨、继续下雨的概率。
- `snow_exit_hysteresis_levels`：离开高海拔雪天时的高度滞回，避免在雪线边缘频繁闪烁。
- `rain_impact_attempts_per_second` / `snow_impact_attempts_per_second`：屏幕随机落点采样速率。只有命中真实水格时才会生成涟漪；雨天默认 24 次/秒，长帧最多补 3 次且不会积压追帧。

雪线高度直接复用 `ecosystems.json` 的 `generation.climate.snow.base_level`，不会建立第二套地形高度，也不会改变固定种子的地图。

雨雪主体使用世界空间 `GPUParticles2D`，放在跟随世界视口的独立 CanvasLayer 4：发射器覆盖相机视野，但已经发射的粒子保持世界坐标，因此人物移动不会让降水相对地面静止或加倍。粒子以 30 Hz 模拟并由 GPU 插值到显示帧率，雨线数量不变。该层位于景深之后、昼夜氛围之前，所以雨雪本身保持清晰并仍受夜色覆盖。屏幕空间 Shader 只保留环境色和雾感，并使用无三角函数的平滑云影；水面命中仍由真实水格采样生成涟漪。涟漪以 30 Hz 重绘、最多 18 段圆弧，避免为了小水波以显示帧率反复重建整根地块柱。

水陆接触边会记录四方向 `shore_edges`，只在真正朝向陆地的一侧绘制断续白浪。四帧岸浪通过 CanvasItem animation slice 在渲染端循环；没有雨滴涟漪时岸线地块不会进入 `_process()`，也不会为每格新增 Sprite 或材质。

运行时按 `T` 会在晴、雨、雪之间快速切换并进入手动测试模式；`Shift+T` 恢复一分钟一次的自动天气。也可用 `--weather clear|rain|snow|auto` 固定截图天气。

## 昼夜配置

[`day_night.json`](./day_night.json) 负责独立的昼夜循环，不会修改天气状态或地图生成：

- `cycle_seconds`：完整一天的现实秒数，默认 480 秒。
- `start_progress`：启动时刻，`0` 是午夜，`0.5` 是正午。
- `sunrise_start/end`、`sunset_start/end`：日出和日落的平滑过渡区间。
- `manual_transition_seconds`：测试快捷键切换昼夜时的淡入淡出时间。
- `night_overlay_opacity`：夜晚靛蓝氛围的最大强度。

夜晚使用带右上方冷月光区域和轻微暗角的屏幕空间 Shader，保留地形细节而不是压成纯黑。运行时按 `N` 会在手动夜晚/白天之间快速切换，第一次从自动白天按下会直接进入夜晚；`Shift+N` 恢复自动昼夜。也可用 `--time day|night|auto` 固定截图时刻。

## 移轴景深实验

[`depth_of_field.json`](./depth_of_field.json) 控制纯 2D 等距世界的移轴景深近似。由于 CanvasItem 没有真实 3D 深度缓冲，焦平面以玩家的实际屏幕高度为中心：玩家附近保持 nearest 像素锐度，上方远景轻度虚化，下方近景使用更强的 mipmap 模糊。相机缓动时会根据 `_player_visual_position`、相机位置和缩放实时更新焦点，不读取用于遮挡排序的 Sprite 坐标。

渲染顺序固定为：世界 `0` → 景深 `2` → 雨雪 `4` → 昼夜 `5` → 天气氛围 `10` → HUD/小地图 `100`。因此萤火虫等世界对象可自然形成散景，雨雪和界面仍保持清晰。关闭景深时整个后处理 CanvasLayer（包括 BackBufferCopy）会隐藏，避免持续产生屏幕复制开销。

- `focus_half_height`：玩家上下保持完全清晰的半带宽。
- `focus_feather`：从清晰带过渡到最大模糊的屏幕高度比例。
- `max_blur_lod`：最大 mipmap 模糊层级。
- `far_strength` / `near_strength`：上方远景和下方近景的独立强度。
- `vignette_strength`：仅在失焦区域生效的轻微暗角。

默认关闭，运行时按 `B` 可立即对比；自动截图可使用 `--dof on|off` 固定状态。
