# 酒馆场景与备份版融合

`index.html` 是网页入口，借用了备份版的首页、故事文字、对话和唱片选择。`tavern-ui.js` 负责这些界面；`tavern.css` 保留备份版的界面布局。`midi-runner.html` 在内嵌页面运行当前 Godot 游戏。`godot/scripts/core/web_tavern_bridge.gd` 通知网页何时进入酒馆，并把播放唱片的操作传给 Godot。关卡进度由 Godot 管理。

酒馆画面仍由当前版本的 `godot/scenes/tavern.tscn` 和 `godot/scripts/tavern_scene.gd` 实时生成。`godot/data/tavern_commands.json` 保存桌椅和酒馆几何指令；`godot/scripts/tavern_layer.gd` 绘制两只史莱姆、老史莱姆制服、唱片以及紧贴唱片机长方体轮廓的黄色光晕；`godot/scripts/tavern_hud.gd` 绘制文字。两只史莱姆的挤压伸展与唱片旋转持续运行。备份版的 `tavern-art.js`、`tavern-sprites.json` 和整张酒馆 PNG 均未用于现行画面。序章借当前酒馆画面做镜头移动和文字过渡，也没有采用备份版的俯视美术。

备份版的关卡视觉效果已进入 `godot/shaders/`：洞穴背景、平台表面、史莱姆形状与材质。酒馆的独立像素处理 `godot/shaders/tavern_post.gdshader` 沿用当前版本，因此关卡视觉改动不会改写酒馆画风。

网页流程是：首页 → 酒馆序章 → 酒馆对话 → 唱片选择 → 唱片机特写及落针动画 → 当前关卡。第 1 至 4 关通关后按空格回酒馆，椅子上的史莱姆按下一关的颜色显示；第 5 关结算后按空格回酒馆，椅子恢复第 1 关的粉色，下次从第 1 关重开。Godot 单独运行时，在酒馆点击唱片机或按空格即可播放落针动画并进入关卡。

酒馆形状的原始绘图代码在 `tools/render_slime_tavern.py`。修改其几何形状后，用 `tools/export_tavern_commands.py` 更新 `godot/data/tavern_commands.json`。根目录的 `tavern_scene.js`、`tavern_commands.js` 和 `tavern_upheavtt.ttf` 是先前的网页原型，现行入口不加载它们。用户放进仓库的 `Group6666-backup-20261119-111006/` 原样保留为本地参考文件夹，并由根目录 `.gitignore` 排除。
