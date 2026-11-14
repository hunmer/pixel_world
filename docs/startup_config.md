# 调试启动配置

直接编辑项目内的 `config/startup.cfg`，然后运行项目（F5）：

```ini
[startup]

auto_open_last_scene=true
last_scene="res://scenes/MapEditor.tscn"
```

- `auto_open_last_scene`：是否启动时自动打开 `last_scene`。设为 `false` 时停在战场选择列表。
- `last_scene`：最后实际进入的场景，使用 `res://` 场景路径；可以手动指定，下次启动生效。切换场景时自动更新，即使关闭自动打开也仍会记录。

常用入口：

| 目标 | `last_scene` |
| --- | --- |
| 战场地图编辑器 | `res://scenes/MapEditor.tscn` |
| 生态世界 | `res://main.tscn` |
| 最近战斗 | `res://scenes/Battle.tscn` |
| 战场选择列表 | `res://scenes/Game.tscn` |
| 标题页 | `res://scenes/Title.tscn` |
| 3D 测试场景 | `res://scenes/Isometric3DTest.tscn` |

初始配置保持最近战斗入口。战斗不会裸启动 `Battle.tscn`，而是通过现有 `GameSession` 流程恢复最近战斗和所需参数。显式 `--battlefield` 或 `--reset-battle` 参数优先于此配置。

启动时经过的 `Game.tscn` 中转不算最近场景；真正返回并显示战场列表后才记录列表，避免下次启动又跳回战斗。F6 直接运行指定场景时也会记录该场景；自动跳转只发生在默认项目入口。世界内嵌战斗仍属于世界场景。

配置只恢复入口，不恢复地图编辑器未保存内容、编辑面板状态或世界中的位置。战斗进度继续由原有战斗存档负责。

非法或不存在的场景路径会给出警告并回到列表；解析失败的配置不会被自动覆盖。运行中手动修改的开关和其他配置项会在下一次记录时保留。自动保存由 Godot `ConfigFile` 完成，不保留配置注释。

编辑器和本机调试运行读写 `res://config/startup.cfg`。导出后的游戏读写 `user://startup.cfg`，避免写入只读资源包；没有该文件时采用相同的默认值。
