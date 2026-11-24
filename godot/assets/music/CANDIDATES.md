# 关卡音乐候选（只收不需要署名的）

参考标准：Theme #02 是 120 BPM、F 小调、合成器铺底 + 拨弦琶音 + 808 底鼓、拍手在 2/4 拍、16 分踩镲的电子曲，约 60 秒。
规则：**只用 CC0**（公有领域，不用署名，可以随便改）。需要署名的已经移到 `candidates/_needs_credit/`，不要用在游戏里。

整理日期：2026-10-29。所有许可证都在 OpenGameArt 页面上逐个核对过。

## 1. 实测结果（`assets/music/candidates/`，14 首，全部 CC0）

用和 Theme #02 相同的流程测量。完整数据：`analysis/candidates_comparison.json`。
**相似度** = 35% 速度接近 120 + 25% 鼓型相关 + 20% 音色相近 + 10% 调性距离 + 10% 是否小调，满分 1。

| 排名 | 文件 | 曲目 / 作者 | 实测 BPM | 节拍 | 调性 | 时长 | 鼓型 | 相似度 |
|---|---|---|---|---|---|---|---|---|
| 1 | `level_theme.wav` | Level & Battle Theme · 关卡曲（muPlumusLand）/ Trex0n | **120** | 稳定 | D 小调 | 1:56 | 0.48 | **0.68** |
| 2 | `future_power.ogg` | Future Power BGM | 127 | 很稳 | C 小调 | 2:31 | 0.44 | 0.66 |
| 3 | `electric_loop_song.mp3` | Electric Loop song / omfgdude | 100 | 节拍弱 | C 小调 | 0:38 | **0.82** | 0.64 |
| 4 | `synthwave_house_loop.ogg` | Synthwave House Loop / Fupi | 114 | 稳定 | C 大调 | 0:51 | 0.74 | 0.63 |
| 5 | `rgp_lost_utopia.wav` | Lost Utopia / tricksntraps | 127 | 稳定 | B♭ 大调（把握低） | 3:07 | 0.42 | 0.62 |
| 6 | `synth_wave.mp3` | Synth Wave / Pro Sensory | 约 107 | 不稳（80/107 摇摆） | C 小调 | 3:12 | 0.66 | 0.62 |
| 7 | `boss_theme.mp3` | Level & Battle Theme · Boss 曲 / Trex0n | **120** | 很稳 | A 小调 | 1:44 | 0.23 | 0.61 |
| 8 | `rgp_starting_over.wav` | Starting Over / tricksntraps | 122 → 125 | 中途变速 | C 大调 | 4:49 | 0.49 | 0.57 |
| 9 | `space_city.ogg` | Space City / MintoDog | 115 | 很稳 | E♭ 小调 | 1:57 | 0.24 | 0.56 |
| 10 | `eastern_arctic_dubstep.mp3` | Eastern Arctic Dubstep | 110 | 稳定（开头约 15 秒不稳） | C 大调 | 5:14 | 0.58 | 0.55 |
| 11 | `rgp_flying_temple.wav` | Flying Temple / tricksntraps | 128 | 稳定 | C 大调（把握低） | 2:17 | 0.33 | 0.48 |
| 12 | `a_start_to_space.ogg` | A start to space / Centurion_of_war | 90 | 稳定 | E 小调 | 1:04 | 0.44 | 0.35 |
| 13 | `electronic_music_loop.ogg` | Electronic Music Loop / Rami99 | 170（或 85） | 稳定 | A 小调 | 0:57 | 0.30 | 0.33 |
| 14 | `calm_relax_1.mp3` | Calm Relax 1 / cynicmusic | – | 没有清晰节拍 | C 大调 | 7:54 | 0.31 | 0.29 |

结论：

- **最合适的是 Level & Battle Theme 那两首**：都正好 120 BPM，节拍稳，都是小调，而且两首用同一个旋律动机，适合“关卡 + Boss”配对。
- **Future Power** 是 127 BPM、C 小调，调性判断把握很高，是第二好的选择。
- **Electric Loop song 的鼓型和音色最像 Theme**，但节拍弱、只有 38 秒，适合做短的过渡关或彩蛋关。
- 小调曲子（Level Theme、Future Power、Synth Wave、Space City）和 Theme 的暗色氛围最搭；大调曲子可以放在“明亮”主题的关卡。

## 2. 关卡分配（2026-10-29 定稿：THAT · 4 个训练关 + Theme 最终关）

前 4 关的音乐名字首字母拼成 **THAT**，各训练 Theme 的一个段落，片段不超过 50 秒。4 首都是 OpenGameArt 的 CC0：不用署名，没有 Content ID。
切好的音频和转写 MIDI 在 `assets/music/levels/`，原曲在 `candidates/round3_that/`。
6 个小关和选好的关卡元素见 `design/小关映射表_THAT_v4.xlsx`（「你的选择」页），事件数据（每个事件都标了小关 / 分支）在 `analysis/training_levels_events.json`，图谱是 `analysis/training_levels_chart.html`。

| 关卡 | 字母 | 训练的 Theme 段落 | 音乐（片段） | BPM | 调性 | 时长 | 风格分 | 覆盖 Theme 这一段的分支 |
|---|---|---|---|---|---|---|---|---|
| 第 1 关 | **T** | 前奏 | [Tuesday Morning](https://opengameart.org/content/tuesday-morning)（Pro Sensory），1.2–49.2 s | 120 | E 小调 | 48.0 s | 0.70 | 7 / 8 |
| 第 2 关 | **H** | 主歌 A | [Hypnotic Chill (Extended 4 minute mix)](https://opengameart.org/content/hypnotic-chill-extended-4-minute-mix)（The Cynic Project），0.0–48.0 s | 125 | B 小调 | 48.0 s | 0.51 | 10 / 11 |
| 第 3 关 | **A** | 副歌 B1 | [April's Finale v2 (loop) Electronic](https://opengameart.org/content/aprils-finale-v2-loop-electronic)（Pro Sensory），48.1–96.1 s | 120 | C 小调 | 48.0 s | 0.68 | 12 / 14 |
| 第 4 关 | **T** | 副歌 B2 | [The Moon Synth](https://opengameart.org/content/the-moon-synth)（Pro Sensory），31.6–79.6 s | 120 | C 小调 | 48.0 s | 0.69 | 14 / 14 |
| 第 5 关 | — | 全曲 | **Theme #02** | 120 | F 小调 | 60 s | — | — |

第 1 关 2026-11-04 从 38 秒延长到 48 秒（到第 24 小节，正好一个乐句结束）：前 36 秒的事件和数据没变，只把 6e 结尾从 36 秒移到 46 秒。`analysis/training_levels_events.json` 里仍是 38 秒的旧切法，风格分和覆盖也是按旧切法测的。

风格分 = 和 Theme 比（满分 1）。“覆盖”= Theme 对应段落里出现的小关分支，这首片段里有几种。
缺口：第 1 关没有开头弱起；第 2 关没有加花；第 3 关没有切分底鼓、抢拍底鼓。
第 2 关原来用 Hunter-class Lifeform（E 大调、开头带上一段鼓的尾巴），听感不好，换成了 Hypnotic Chill：全程没有底鼓、留白和长音多，最像 Theme 主歌 A，所以第 2 关只有 5 个小关（没有 2-1 底鼓落点，Theme 主歌 A 也没有底鼓）。它的风格分偏低主要是因为没有副歌那种鼓型，对主歌来说正合适。

第二轮的 4 首（Nightfall、Chill Trap Beat、chill wave friday、Dimly lit）已经不用了，原曲还在 `candidates/round2/`。

### 2c. 第三轮：按 T / H / A 首字母找的 CC0 候选（2026-10-29 实测）

都来自 OpenGameArt、CC0、不是 AI 生成。只把选中的 4 首放进了项目，其余在会话临时目录里，需要的话可以重新下载。

| 字母 | 曲目（风格分） |
|---|---|
| T | **Tuesday Morning 0.70**、**The Moon Synth 0.69**、Trace Agent 0.65（120 BPM，前 14 小节没有鼓）、The lonely route 0.62、Trance / trap / electronic 0.59、Through The Universe 0.59、The Projects 0.57、Tense Future Loop 0.56、The Stalker 0.54 |
| H | **Hypnotic Chill 0.51**（主歌覆盖 10 / 11）、Heavy Rain 0.62（Pro Sensory，D♭ 小调 125 BPM，但全程同一个鼓型、没有段落变化，覆盖 8 / 11）、Hiryuti 0.60（覆盖 7 / 11）、Hunter-class Lifeform 0.58（已换掉）、Hyperspace 0.54（95 BPM）、happy lofi day 0.46、Headspin 0.45 |
| A | **April's Finale v2 Electronic 0.68**、Approach 0.60、After midnight 0.58、A Chill Fever 0.56、A slow day remixed 0.48 |

H 开头又像 Theme 的曲子最少。如果 Hypnotic Chill 也不合适，下一个选择是 Heavy Rain（和其他 3 关同一个作者，但鼓一直很满，不太像主歌）。

缺口：还没有测过 130 BPM 以上又适合做高难度关的 CC0 曲子。Free Rhythm Game Music Pack 1 里还有 Ascend 130、The Lab 144、Vessel of Eternity 150、Bow For Me 157 等（都是 CC0），需要的话再下载测量。

## 2b. 第二轮候选：风格更接近 Theme（2026-10-29，还没下载）

第一轮的曲子和 Theme 风格不搭。Theme 的特征：小调、偏暗，低频很重（808），第 2、4 拍拍手 + 16 分踩镲，温暖铺底 + 拨弦琶音，约 120 BPM。按 future bass / chill trap / melodic trap 重新找。

**Pixabay**（Pixabay Content License：不用署名；和游戏组合成新作品不算“单独分发”，可以用；禁止批量抓取）

| 曲目 | 作者 | 时长 | 情绪 / 描述 | Content ID | 备注 |
|---|---|---|---|---|---|
| [Nightfall / Future Bass Music](https://pixabay.com/music/future-bass-nightfall-future-bass-music-228100/) | SoulProdMusic | 2:22 | 慵懒、梦幻；旋律合成器 + 人声切片 + 重低音 | 已登记 | |
| [Dark Trap Beat Atmosphere](https://pixabay.com/music/trap-dark-trap-beat-atmosphere-583431/) | echoes_of_lumen | 2:28 | 暗、808 | 已登记 | |
| [Chill Trap Beat](https://pixabay.com/music/trap-chill-trap-beat-349227/) | Tunetank | 2:04 | 梦幻、慵懒；合成器旋律 + 808 | 已登记 | |
| [Chill Trap Promo](https://pixabay.com/music/beats-chill-trap-promo-160991/) | SunSides | 2:26 | 慵懒；合成器 + 808 | 已登记 | |
| [Future Bass](https://pixabay.com/music/future-bass-future-bass-545515/) | alex-morgan | 2:19 | 明亮、有能量 | 已登记 | 偏亮，可能不如前几首暗 |
| [Melodic Type Beat · Dark Type Beat](https://pixabay.com/music/beats-melodic-type-beat-dark-type-beat-rap-trap-beat-instrumental-312497/) | zharovbeatz | 2:04 | 忧郁旋律 + 808 | 未注明 | **AI 生成** |
| [Trap Lofi](https://pixabay.com/music/beats-trap-lofi-592645/) | ZephiraMusic | 2:22 | chill lofi trap | 已登记 | **AI 生成** |

Content ID 已登记 = 以后把带这首音乐的游戏视频传到 YouTube 可能被自动认领（可以申诉，但麻烦）。很多 game jam 禁止 AI 生成素材，标了 AI 的先别用。

**OpenGameArt**（CC0）

| 曲目 | 描述 | 文件 | 大小 |
|---|---|---|---|
| [Mystery Go Brrrr](https://opengameart.org/content/mystery-go-brrrr) | 神秘、紧张的合成器贝斯 + trap 节奏 | mysterygobrrrrr.ogg | 3.5 MB |
| [Melancholic Void](https://opengameart.org/content/melancholic-void) | 忧郁的合成器流行 | melancholic_void.mp3 | 3.5 MB |
| [The Bass of the Future](https://opengameart.org/content/the-bass-of-the-future) | 作者自称的 future bass，带 8-bit 味 | the_bass_of_the_future.wav | 29.8 MB |
| [All Night Road](https://opengameart.org/content/all-night-road) | lo-fi 合成器流行，可循环 | allnightroad.mp3 | 7.0 MB |
| [Dimly lit](https://opengameart.org/content/dimly-lit) | lo-fi 电子，可循环 | dimlylit.mp3 | 4.1 MB |
| [chill wave friday sept 17](https://opengameart.org/content/chill-wave-friday-sept-17) | chillwave | chill_wave.mp3 | 2.7 MB |
| [Undefined Emotion](https://opengameart.org/content/undefined-emotion) | 合成器 | undefined_emotion.mp3 | 2.8 MB |

## 3. 来源（都是 CC0，不需要署名）

| 文件 | 页面 |
|---|---|
| level_theme.wav、boss_theme.mp3 | [Level & Battle Theme (Loops)](https://opengameart.org/content/level-battle-theme-loops)（zip 里的 muPlumusLand.wav、muBossFight.mp3） |
| future_power.ogg | [Future Power BGM](https://opengameart.org/node/120356) |
| electric_loop_song.mp3 | [Electric Loop song](https://opengameart.org/content/electric-loop-song) |
| synthwave_house_loop.ogg | [Synthwave House Loop](https://opengameart.org/content/synthwave-house-loop) |
| synth_wave.mp3 | [Synth Wave](https://opengameart.org/content/synth-wave) |
| space_city.ogg | [Space City](https://opengameart.org/content/space-city) |
| eastern_arctic_dubstep.mp3 | [Eastern Arctic Dubstep](https://opengameart.org/content/eastern-arctic-dubstep) |
| calm_relax_1.mp3 | [Calm Relax 1 (Synthwave 421k)](https://opengameart.org/content/calm-relax-1-synthwave-421k) |
| electronic_music_loop.ogg | [Electronic Music Loop](https://opengameart.org/content/electronic-music-loop) |
| a_start_to_space.ogg | [A start to space](https://opengameart.org/node/117952) |
| rgp_*.wav | [Free Rhythm Game Music Pack 1](https://opengameart.org/content/free-rhythm-game-music-pack-1) |

Level & Battle Theme 和 Future Power 的作者在页面上“希望”被署名，但 CC0 在法律上不要求，不写也可以。

## 4. 不用的

- 需要署名，已移到 `candidates/_needs_credit/`：Assembly Not Required（CC-BY 4.0）、Retro Synthwave Loops 的 5 段（CC-BY 4.0）。
- 不是 CC0：The Most Beautiful 120 BPM（CC-BY 3.0）、Alcodonj（CC-BY-SA 4.0）、Fat Groove Loops（CC-BY-SA 3.0）。
- Fat Groove Drums 是 CC0，但只有一段鼓，不是完整曲子。
- itch.io 上的几个合成器包：有机器人验证打不开，许可证没法核实。
