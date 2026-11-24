# 酒馆场景与备份版融合

`index.html` 是网页入口。`slime-pub-cover.js` 绘制站在吧台后的淡蓝色酒保，`tavern-ui.js` 处理首页按钮、故事文字、对话和唱片选择。`midi-runner.html` 在内嵌页面运行 Godot。`godot/scripts/core/web_tavern_bridge.gd` 通知网页何时进入酒馆，并把播放唱片的操作传给 Godot。关卡进度由 Godot 管理。

`godot/scenes/tavern.tscn` 和 `godot/scripts/tavern_scene.gd` 实时生成酒馆画面，序章和通关返回都复用这个场景。`godot/data/tavern_commands.json` 保存桌椅和酒馆几何指令，`godot/scripts/tavern_layer.gd` 绘制角色、唱片和唱片机光晕。首页和酒馆的酒保造型都来自 `godot/data/bartender.json`。两只史莱姆持续做挤压伸展动画，唱片持续旋转。

备份版的关卡视觉效果已进入 `godot/shaders/`：洞穴背景、平台表面、史莱姆形状与材质。酒馆的独立像素处理 `godot/shaders/tavern_post.gdshader` 沿用当前版本，因此关卡视觉改动不会改写酒馆画风。

网页流程是：首页 → 酒馆序章 → 酒馆对话 → 唱片选择 → 唱片机特写及落针动画 → 当前关卡。第 1 至 4 关通关后按空格回酒馆，椅子上的史莱姆按下一关的颜色显示；第 5 关结算后按空格回酒馆，椅子恢复第 1 关的粉色，下次从第 1 关重开。Godot 单独运行时，在酒馆点击唱片机或按空格即可播放落针动画并进入关卡。

酒馆形状的原始绘图代码在 `tools/render_slime_tavern.py`。修改酒馆或酒保的几何数据后，用 `tools/export_tavern_commands.py` 更新 `godot/data/tavern_commands.json`，再重新导出网页用的 `index.pck`。根目录的 `tavern_scene.js` 和 `tavern_commands.js` 供先前的网页原型使用。`tavern_upheavtt.ttf` 为首页提供 Upheaval 字体。用户放进仓库的 `Group6666-backup-20261119-111006/` 原样保留为本地参考文件夹，并由根目录 `.gitignore` 排除。

首页背景由 `tools/render_slime_pub_room.py` 用 Blender 几何体和灯光生成。用 `tools/pixelate_slime_pub_room.py` 将渲染结果转换成 480 × 270 的 `slime-pub-room.png`。像素处理使用最近邻取样、16 阶亮度和仅用于渐变的 4 × 4 Bayer 抖动。

```shell
blender --background --python tools/render_slime_pub_room.py -- slime_pub_room_raw.png
python tools/pixelate_slime_pub_room.py slime_pub_room_raw.png
```
