#include <sourcemod>
#include <regex>
#include <entitylump>

#define MAX_CLASSNAME 96
#define MAX_KEY 64
#define MAX_VALUE 1024

StringMap g_TextEntKeys;		// Keyvalues we should translate for this entity
StringMap g_TextEntInputs;	// Inputs that make this entity change its text

void RegisterTextEntity(const char[] classname, ArrayList keyvalues, ArrayList inputs)
{
	//PrintToServer("%s: Registered %d keyvalues and %d inputs", classname, keyvalues.Length, inputs.Length);
	g_TextEntKeys.SetValue(classname, keyvalues);
	g_TextEntInputs.SetValue(classname, inputs);
}

public void Parser_OnPluginStart()
{
	// TODO: Clear when new map etc
	g_TextEntKeys = new StringMap();
	g_TextEntInputs = new StringMap();
	WalkConfig();
}

void WalkConfig()
{
	Regex expr = new Regex("[\\w]+"); // A space-separated list of words

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "data/map-translator.cfg");
	KeyValues kv = new KeyValues("MapTranslator");

	if (!kv.ImportFromFile(path))
	{
		SetFailState("Couldn't open required file: %s", path);
	}

	if (!kv.GotoFirstSubKey())
	{
		delete kv;
		return;
	}

	do
	{
		char classname[MAX_CLASSNAME];
		kv.GetSectionName(classname, sizeof(classname));

		ArrayList keyvalues = new ArrayList(ByteCountToCells(64));
		ArrayList inputs = new ArrayList(ByteCountToCells(64));

		KvGetStringArray(kv, "keyvalues", keyvalues, expr);
		KvGetStringArray(kv, "inputs", inputs, expr);
		
		RegisterTextEntity(classname, keyvalues, inputs);
	}
	while (kv.GotoNextKey());

	delete kv;
	delete expr;
}

void KvGetStringArray(KeyValues kv, const char[] key, ArrayList dest, Regex regex)
{
	char buffer[1024];
	kv.GetString(key, buffer, sizeof(buffer));
	
	int numStrings = regex.MatchAll(buffer);
	for (int i = 0; i < numStrings; i++)
	{
		regex.GetSubString(i, buffer, sizeof(buffer));
		dest.PushString(buffer);
	}
}

/*
 * Scans the map lump for translatable content
 */
public void OnMapInit()
{
	Regex regAddOutput = new Regex("(\\w+)\\s+(.*)");
	StringMap textEntsByName = new StringMap();

	int lumpLen = EntityLump.Length();

	char key[64], value[1024];

	// First pass: Find text entities and save their default message fields
	for (int i; i < lumpLen; i++) 
	{
		EntityLumpEntry entry = EntityLump.Get(i);

		// Ignore empty classnames, should never happen..
		char classname[MAX_CLASSNAME]; 
		if (entry.GetNextKey("classname", classname, sizeof(classname)) == -1) 
		{
			delete entry;
			continue;
		}

		// Remember this targetname being a text entity, we'll need it for the second pass
		char targetname[32];
		entry.GetNextKey("targetname", targetname, sizeof(targetname));
		if (targetname[0])
		{
			textEntsByName.SetString(targetname, classname);
		}

		// Get the list of translatable text fields for this entity type
		// (defined in data/map-translator.cfg)
		ArrayList keys;
		if (g_TextEntKeys.GetValue(classname, keys))
		{
			int maxKeys = keys.Length;
			for (int keyIndex = 0; keyIndex < maxKeys; keyIndex++)
			{
				keys.GetString(keyIndex, key, sizeof(key));

				// If the field is present and has a value, save it
				if (key[0] && entry.GetNextKey(key, value, sizeof(value)) != -1 && value[0])
				{
					AddToTranslatables(value);
				}
			}
		}

		delete entry;
	}

	// Second pass: Find entities that modify our text entity fields, and save the modified fields
	// For example, a trigger might have "OnTrigger" -> "text_ent, AddOutput, message 123"
	for (int i; i < lumpLen; i++) 
	{
		EntityLumpEntry entry = EntityLump.Get(i);

		int maxKeyvalues = entry.Length;
		for (int j = 0; j < maxKeyvalues; j++)
		{
			// We only care about keyvalue pairs that are outputs
			// TODO: Figure out if they always start with 'On'
			entry.Get(j, key, sizeof(key), value, sizeof(value));
			if (StrContains(key, "On") != 0) {
				continue;
			}

			// Split value into individual fields 
			// "text_ent,Display,Hello,0,-1" -> "text_ent", "Display", "Hello", etc.
			float delay; int fireCount;
			char target[32], inputName[1024], variantValue[1024];

			ParseEntityOutputString(value, target, sizeof(target),
				inputName, sizeof(inputName), variantValue, sizeof(variantValue),
				delay, fireCount);

			TrimString(variantValue);
			TrimString(inputName);

			if (!inputName[0] || !variantValue[0]) {
				continue;
			}

			// Check whether the target entity is a text entity
			char targetClassname[MAX_CLASSNAME];

			// If the target entity is ourselves, verify we are a text entity
			if (StrEqual(target, "!self"))
			{
				if (entry.GetNextKey("classname", targetClassname, sizeof(targetClassname)) == -1) {
					continue;
				}

				if (!g_TextEntKeys.ContainsKey(targetClassname) && !g_TextEntInputs.ContainsKey(targetClassname)) {
					continue;
				}
			}
			// Else the target's name must've been caught in the first pass
			else if (!textEntsByName.GetString(target, targetClassname, sizeof(targetClassname))) {
				continue;
			}

			// There are 2 ways we could be modifying this entity:
			// 1. A named input, like 'SetCaption <value>'
			// 2. A raw keyvalue change via 'AddOutput <key> <value>' 

			if (StrEqual(inputName, "AddOutput"))
			{
				if (regAddOutput.Match(variantValue) != 3) { // Base + 2 capture groups
					continue;
				}
				
				char targetedKey[MAX_KEY];
				regAddOutput.GetSubString(1, targetedKey, sizeof(targetedKey));

				// Check if <key> is one of the entity's text keys
				ArrayList targetTextKeys; 
				if (g_TextEntKeys.GetValue(targetClassname, targetTextKeys) && 
					targetTextKeys.FindString(targetedKey) != -1)
				{
					// If it is, we save the <value> as another translatable message
					char newMessage[MAX_VALUE];
					regAddOutput.GetSubString(2, newMessage, sizeof(newMessage));
					AddToTranslatables(newMessage);
				}
			}
			else
			{
				// Get a list of text-modifying inputs for this entity type
				ArrayList targetTextInputs; 
				if (!g_TextEntInputs.GetValue(target, targetTextInputs)) {
					continue;
				}
				
				int maxTextInputs = targetTextInputs.Length;
				for (int inputIndex = 0; inputIndex < maxTextInputs; inputIndex++)
				{
					char textInput[64];
					targetTextInputs.GetString(inputIndex, textInput, sizeof(textInput));

					if (StrEqual(inputName, textInput))
					{
						AddToTranslatables(variantValue);
					}
				} 
			}
		}

		delete entry;
	}

	delete textEntsByName;
	delete regAddOutput;
}

void AddToTranslatables(const char[] text)
{
	//PrintToServer("Translatable: %s", text);
	g_ExportQueue.PushString(text);
}

// Thanks to nosoop for this snippet
// https://github.com/nosoop/SMExt-EntityLump/blob/main/sourcepawn/entitylump_native_test.sp#L100
bool ParseEntityOutputString(const char[] output, char[] targetName, int targetNameLength,
		char[] inputName, int inputNameLength, char[] variantValue, int variantValueLength,
		float &delay, int &fireCount) {
	int delimiter;
	char buffer[32];
	
	{
		// validate that we have something resembling an output string (four commas)
		int i, c, nDelim;
		while ((c = FindCharInString(output[i], ',')) != -1) {
			nDelim++;
			i += c + 1;
		}
		if (nDelim < 4) {
			return false;
		}
	}
	
	delimiter = SplitString(output, ",", targetName, targetNameLength);
	delimiter += SplitString(output[delimiter], ",", inputName, inputNameLength);
	delimiter += SplitString(output[delimiter], ",", variantValue, variantValueLength);
	
	delimiter += SplitString(output[delimiter], ",", buffer, sizeof(buffer));
	delay = StringToFloat(buffer);
	
	fireCount = StringToInt(output[delimiter]);
	
	return true;
}