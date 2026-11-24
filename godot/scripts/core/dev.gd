extends RefCounted
## The one switch for everything only the developer reaches (autoplay, the tune mode, choosing a level, the labels, ...): on
## in the editor's binary only, so an exported game can't have it on, whatever tuning.csv says (DEV_KEYS can also turn the
## keys off in the editor). --release-look, a user argument (after --), shows the editor's binary what a player gets.


static func on() -> bool:
	return OS.has_feature("editor") and not OS.get_cmdline_user_args().has("--release-look")
