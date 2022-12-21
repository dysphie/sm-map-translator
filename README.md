# [NMRiH/ZPS] Map Translator

Translates map texts via translation files, allowing players to see messages in their preferred language. 

The following texts are supported:

- [game_text](https://developer.valvesoftware.com/wiki/Game_text)
- [env_hudhint](https://developer.valvesoftware.com/wiki/Env_hudhint)
- Objectives (**NMRiH** and **ZPS** only)
- point_message_multiplayer (**NMRiH** only)





## Installation

- Install [Sourcemod 1.11.6924 or higher](https://www.sourcemod.net/downloads.php?branch=stable).
- Grab the latest [release ZIP](https://github.com/dysphie/sm-map-translator/releases) and extract to `addons/sourcemod`.
- Refresh your plugins (`sm plugins refresh` in server console)

## Usage

- Navigate to `cfg/sourcemod` and open `plugin.map-translator.cfg` (`plugin.nmrih-map-translator.cfg` in NMRiH)
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

- `mt_bulk_learn_nmo`
	- Learns objective messages for every map without loading them in.


## Optional CVars

CVars are always read from `cfg/sourcemod/plugin.map-translator.cfg`

- `mt_fallback_lang` (Default: `en`)
  - Fallback language to show to clients whose preferred language has not been translated.

- `mt_ignore_numerical` (Default: `1`)
  - Whether to attempt to translate and learn fully numerical messages (e.g. "9247").


## Notes

- You must escape quotes with a backslash (`\`) to prevent parsing errors.

	```cpp
	// Example 
	"en" "Destroy \"Robert\" the puppet"
	```

- This plugin is incompatible with [Multilingual Objectives](https://forums.alliedmods.net/showthread.php?p=2678257) and [Multilingual Objective Beta](https://forums.alliedmods.net/showthread.php?p=2305894).
- You are not expected to manually add new entries, only edit existing — if a specific text is not getting picked up, please [create an issue](https://github.com/dysphie/nmrih-map-translator/issues). 
	However, nothing will break if you do, the section name (e.g. `edf566344eb9f2cb892e073e70c70181`) is just an [MD5 hash](https://www.md5hashgenerator.com) of the original text.

