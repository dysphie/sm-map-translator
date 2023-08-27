
![4150650 (1)](https://github.com/dysphie/sm-map-translator/assets/11559683/11b2fcea-0a83-42cd-93ac-848407288f47)

# [SM] Map Translator

Translates map texts via translation files, allowing players to see messages in their preferred language. 

The following texts are supported:

- [ANY] [game_text](https://developer.valvesoftware.com/wiki/Game_text)
- [ANY] [env_hudhint](https://developer.valvesoftware.com/wiki/Env_hudhint)
- [ZPS] Objective text
- [NMRiH] Objective text
- [NMRiH] point_message_multiplayer
- [TF2] [game_text_tf](https://developer.valvesoftware.com/wiki/Game_text_tf)





## Installation

- Install [Sourcemod 1.11.6924 or higher](https://www.sourcemod.net/downloads.php?branch=stable).
- Grab the latest [release ZIP](https://github.com/dysphie/sm-map-translator/releases) and extract to `addons/sourcemod`.
- Refresh your plugins (`sm plugins refresh` in server console)

## Usage

- Navigate to `cfg/sourcemod` and open `plugin.map-translator.cfg` 

	<sup>Note: it's `plugin.nmrih-map-translator.cfg` in NMRiH for backward compatibility</sup>
- Set `mt_autolearn_langs` to a space-separated list of language codes you wish to generate translations for. 

	```cpp
	// Example for English, Spanish and Korean
	mt_autolearn_langs "en es ko"
	```
	
	<sup>Note: You can see the full list of language codes at `addons/sourcemod/configs/languages.cfg`</sup>


- The plugin will now create translation files for maps as they're loaded. 
They're stored in `addons/sourcemod/translations/_maps`

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

	You can then edit these files to change the message printed for each language.

	```cpp
	"Phrases"
	{
		"edf566344eb9f2cb892e073e70c70181"
		{
			"en"		"Get rid of the puppet"
			"es"		"Destruye la marioneta"
			"ko"		"인형을 파괴해"
		}
	}
	```
	

## Helper Command

| Command                | Description                                           | Required Flags      |
|------------------------|-------------------------------------------------------|----------------------|
| `mt_forcelang`         | Forces perceived language to a given language code.   | `ADMFLAG_ROOT`       |
| `mt_bulk_learn_nmo`    | Generate translations for all .nmo files in NMRiH without loading the maps.               | `ADMFLAG_ROOT`       |
| `mt_force_export`      | Force export learned translations immediately.        | `ADMFLAG_ROOT`       |
| `mt_debug_clients`     | Print perceived language code for each client.        | `ADMFLAG_ROOT`       |

## CVars

CVars are read from `cfg/sourcemod/plugin.map-translator.cfg`

| ConVar | Description | Default Value |
| --- | --- | --- |
| `mt_ignore_numerical` | Don't translate or learn fully numerical messages such as codes, countdowns, etc. | 1 |
| `mt_autolearn_langs` | Space-separated list of language entries to include in auto generated translation files, for example: `en es ko` | en |
| `mt_fallback_lang` | Clients whose language is not translated will see messages in this language | en |
| `mt_extended_learning` | Whether the game will learn text entities that have been modified during gameplay. This can improve detection on maps with VScript, but it can also increase memory usage and the size of the generated translation file | 0 |


## Notes

- You must escape quotes with a backslash (`\`) to prevent parsing errors.

	```cpp
	// Example 
	"en" "Destroy \"Robert\" the puppet"
	```

- This plugin is incompatible with [Multilingual Objectives](https://forums.alliedmods.net/showthread.php?p=2678257) and [Multilingual Objective Beta](https://forums.alliedmods.net/showthread.php?p=2305894).
- You are not expected to manually add new entries, only edit existing — if a specific text is not getting picked up, please [create an issue](https://github.com/dysphie/nmrih-map-translator/issues). 
	However, nothing will break if you do, the section name (e.g. `edf566344eb9f2cb892e073e70c70181`) is just an [MD5 hash](https://www.md5hashgenerator.com) of the original text.

