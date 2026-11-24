# Group6666

Midi Runner 的 Godot 项目源码在 [`godot/`](godot/)。仓库根目录的 `index.html` 是网页入口，`midi-runner.html` 加载同目录的 `index.js`、`index.wasm` 和 `index.pck`。网页入口使用备份版的首页、故事文字、对话和唱片选择；酒馆本身始终由当前 Godot 脚本绘制。备份版的洞穴、平台和玩家视觉效果已合入关卡。

进入酒馆并选择唱片后，镜头拉近到唱片机，唱臂抬起、移向唱片并落针，随后进入对应关卡。每关结束后返回酒馆，椅子上的史莱姆显示接下来要玩的关卡颜色；第 5 关结算后从第 1 关重新开始，椅子也恢复第 1 关的粉色。

无需通关即可预览某关结束后的酒馆：打开本地游戏网址，在 `index.html` 后加 `?previewAfterLevel=1`。数字为刚完成的关卡；`1` 会显示下一关的椅子颜色与酒馆动画。去掉参数即可恢复正常首页。

酒馆的绘制方式和关卡切换逻辑见 [`TAVERN_SCENE.md`](TAVERN_SCENE.md)。本地编辑时用 Godot 4.7.2 打开 `godot/project.godot`。
