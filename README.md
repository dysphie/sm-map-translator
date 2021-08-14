# [NMRiH/ZPS] Map Translator


Provides a way to translate maps via translation files, allowing players to see messages in their preferred language. 

The following are supported:

| Objectives | Game text | HUD Hints |
|------------|-----------|-----------|
| ![image](https://user-images.githubusercontent.com/11559683/127247238-c190ae46-24ac-453f-9e59-983bf2e5ba2f.png)<br />![image](https://user-images.githubusercontent.com/11559683/128650387-7bfd2a74-5546-4f26-b63f-5af802d8666a.png) | ![image](https://user-images.githubusercontent.com/11559683/127247367-37e055ee-9c63-42c8-948d-ec4aeae1166f.png)<br />![image](https://user-images.githubusercontent.com/11559683/128650505-3c7aa042-121d-43f9-82a8-2614b9074418.png)       | ![image](https://user-images.githubusercontent.com/11559683/127247508-0e1fd033-9414-47f8-879c-d5bbd6336fec.png)       |



## Installation

- Install [DHooks2](https://github.com/peace-maker/DHooks2#installation).
- Grab the latest [release ZIP](https://github.com/dysphie/sm-map-translator/releases) and extract to `addons/sourcemod`.
- Reload the server to reflect the changes.

## Usage

- Navigate to `cfg/sourcemod` and open `plugin.map-translator.cfg` with a text editor.
- Set `mt_autolearn_langs` to a space-separated list of language codes you wish to generate translations for. 

	```cpp
	// Example for English, Spanish and Korean
	mt_autolearn_langs "en es ko"
	```
	
	<sup>Note: You can see the full list of language codes at `addons/sourcemod/configs/languages.cfg`</sup>


- The plugin will now learn maps as they're played, and dump translatable content to `addons/sourcemod/translations/_maps/mapname.txt`:

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

- You can then edit these files to change the message printed for each language.

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
	
	<sup>Note: Some maps might require multiple playthroughs to be fully learned.</sup>


## Helper Command

- `mt_bulk_learn_nmo`
	- You can use this command to speed up the learning process and generate translation files for every map on the server without loading them in. The generated files will only include objective messages.


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
- You are not expected to manually add new entries, only edit existing — if a specific text is not getting picked up, please [file an issue](https://github.com/dysphie/nmrih-map-translator/issues). 
	However, nothing will break if you do, the section name (e.g. `edf566344eb9f2cb892e073e70c70181`) is just an [MD5 hash](https://www.md5hashgenerator.com) of the original text.

