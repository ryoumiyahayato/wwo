# R41 可编辑模型源

四份 `.blend` 对应 `assets/landmarks/*_r41.glb`。`model_counts.json` 为导出器读取的 Mesh/面数，不是运行性能数据。

重新制作：

```powershell
& 'D:/Tools/blender.exe' --background --factory-startup --python tools/map/build_historical_landmarks_r41.py
& 'C:/Users/agcrf/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' tools/map/install_historical_scenes_r41.py
```

生成器可附加 `-- --render` 保存建模视图到 `local-artifacts/`；它不会启动游戏。两个 LOD 均在 GLB 中，游戏按命名节点切换。Blender 源的远档默认隐藏，便于编辑近档。

来源、原创许可、历史示意范围与桥位限制见 `assets/landmarks/R41_SOURCE_AND_USAGE.md`。不要把示意尺寸、拱券分段或高架孔数作为新的历史测绘事实。

R41扩展：`cloud_adaptations/*.blend`为7件内部云盘古迹适配源；`shared_facilities.blend`为4类原创设施的近远档。重制依次运行`adapt_drive_landmarks_r41.py`、`install_landmark_expansion_r41.py`、`build_shared_facilities_r41.py`。前两项依赖已下载且保留的指定原件，不会重新下载全库。各自的`model_counts.json`和`shared_facilities_counts.json`记录结构。第三方素材限制及淘汰候选见`assets/landmarks/internal_preview_r41/SOURCE_AND_USAGE.md`。

桥梁/车站生成器逐件移除全部Blender对象，包含隐藏远档；避免遗留对象占用`Far`名称导致导出为`Far.001`。

共享设施源还保留隐藏的`SOURCE_ONLY_DerrickAssembly`集合。固定支架、臂架、吊索、石料、绞盘按支点分件，供以后编辑或绑定；不是当前机械动画。导出选集仍只有8个近远档静态Mesh，不导出这5个编辑部件。
