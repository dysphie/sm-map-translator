# [NMRiH] Map Translator


Provides a way to translate maps via translation files, allowing players to see messages in their preferred language. 

The following are supported:

| Objectives | Game text | HUD Hints |
|------------|-----------|-----------|
| ![image](https://user-images.githubusercontent.com/11559683/127247238-c190ae46-24ac-453f-9e59-983bf2e5ba2f.png)        | ![image](https://user-images.githubusercontent.com/11559683/127247367-37e055ee-9c63-42c8-948d-ec4aeae1166f.png)       | ![image](https://user-images.githubusercontent.com/11559683/127247508-0e1fd033-9414-47f8-879c-d5bbd6336fec.png)       |



The plugin will learn maps as they're played, and dump translatable content to `translations/_maps/<mapname>.txt`. Example:

```cpp
"Phrases"
{
	"edf566344eb9f2cb892e073e70c70181"
	{
		"en"		"Destroy the puppet"
		"es"		"Destroy the puppet"
		"ko"		"Destroy the puppet"
	}
}
```

You can then edit the text shown for that specific language code.

```cpp
"Phrases"
{
	"edf566344eb9f2cb892e073e70c70181"
	{
		"en"		"Destroy the puppet please it's scary"
		"es"		"Destruye la marioneta"
		"ko"		"꼭두각시를 파괴"
	}
}
```

Some maps might require multiple playthroughs to be fully learned.

### ConVars

Configs are saved to `cfg/sourcemod/plugin.nmrih-map-translator.cfg` (Autogenerated when the plugin is first loaded)

- `mt_autolearn_langs` (Default: None) 
  - Space-separated list of language codes to include in the autogenerated files. For example `en es ko` would produce the file shown above.

- `mt_fallback_lang` (Default: "en")
  - Fallback language to show to clients whose preferred language has not been translated

- `mt_ignore_numerical` (Default: 1)
  - If set to 1, plugin won't attempt to translate and learn fully numerical messages (e.g. "9247")

### Commands

- `mt_bulk_learn_nmo` 
  - Learn objective messages for every map on the server without loading them in. This will NOT override existing translation entries, it will only append new ones. In other words, you're free to run this as many times as you want.

### Requirements
- Sourcemod 1.11 Build 6646 or higher
- [DHooks2](https://github.com/peace-maker/DHooks2/releases)

### Notes


- If you want to use double quotes in a translation phrase, you must escape them, e.g `"en" "Destroy \"Robert\" the puppet"`
- Linux support is included but untested.
- This plugin is incompatible with [Multilingual Objectives](https://forums.alliedmods.net/showthread.php?p=2678257) and [Multilingual Objective Beta](https://forums.alliedmods.net/showthread.php?p=2305894).

