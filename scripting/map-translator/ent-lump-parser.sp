#include <sourcemod>
#include <regex>
#include <entitylump>

StringMap g_TextEntKeys;		// Keyvalues we should translate for this entity
StringMap g_TextEntInputs;	// Inputs that make this entity change its text
StringMap g_TextEnts;

void RegisterTextEntity(const char[] classname, ArrayList keyvalues, ArrayList inputs)
{
	//PrintToServer("%s: Registered %d keyvalues and %d inputs", classname, keyvalues.Length, inputs.Length);
	g_TextEntKeys.SetValue(classname, keyvalues);
	g_TextEntInputs.SetValue(classname, inputs);
	g_TextEnts.SetValue(classname, true);
}

public void Parser_OnPluginStart()
{
	// TODO: Clear when new map etc
	g_TextEntKeys = new StringMap();
	g_TextEntInputs = new StringMap();
	g_TextEnts = new StringMap();
	WalkConfig();
}

void WalkConfig()
{
	Regex expr = new Regex("[\\w]+"); // A space-separated list of words

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/map-translator.cfg");
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
		char classname[64];
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
	PrintToServer("Got %d exploded strings for %s", numStrings, key);
	for (int i = 0; i < numStrings; i++)
	{
		regex.GetSubString(i, buffer, sizeof(buffer));
		dest.PushString(buffer);
	}
}

public void OnMapInit()
{
	Regex regAddOutput = new Regex("(\\w+)\\s+(.*)"); // e.g. "message Whatever Here" // FIXME DELETE HANDLE
	StringMap nameToClass = new StringMap();

	int lumpLen = EntityLump.Length();

	for (int i; i < lumpLen; i++) 
	{
		EntityLumpEntry entry = EntityLump.Get(i);

		// Ignore entities without a classname, shouldn't happen!
		char classname[32]; 
		if (entry.GetNextKey("classname", classname, sizeof(classname)) == -1) 
		{
			delete entry;
			continue;
		}

		char targetname[32];
		entry.GetNextKey("targetname", targetname, sizeof(targetname));
		if (targetname[0])
		{
			nameToClass.SetString(targetname, classname);
		}

		// Get text keyvalues for this entity and add their values to the translatables list
		ArrayList keys;
		if (g_TextEntKeys.GetValue(classname, keys))
		{
			int maxKeys = keys.Length;
			char key[64];
			for (int keyIndex = 0; keyIndex < maxKeys; keyIndex++)
			{
				keys.GetString(keyIndex, key, sizeof(key));
				char value[1024];
				if (key[0] && entry.GetNextKey(key, value, sizeof(value)) != -1)
				{
					AddToTranslatables(value);
				}
			}
		}

		// Now find keyvalues that modify other text entities (e.g. "OnTrigger" "textent, AddOutput, message 123")
		int maxEntries = entry.Length;
		for (int j = 0; j < maxEntries; j++)
		{
			// We only care about outputs (TODO: do they always start with 'On'?)
			char key[3], outputString[1024];
			entry.Get(j, key, sizeof(key), outputString, sizeof(outputString));
			if (StrContains(key, "On") != 0) {
				continue;
			}

			char target[32], inputName[1024], variantValue[1024];
			float delay;
			int nFireCount;
			
			ParseEntityOutputString(outputString, target, sizeof(target),
					inputName, sizeof(inputName), variantValue, sizeof(variantValue),
					delay, nFireCount);
			
			// PrintToServer("target %s -> input %s (value %s, delay %.2f, refire %d)",
			// 			target, inputName, variantValue, delay, nFireCount);
			
			TrimString(inputName);

			// Check whether the output target is a text entity
			char targetClassname[64];
			if (nameToClass.GetString(target, targetClassname, sizeof(targetClassname)))
			{
				// If it is, check whether we're modifying its text via text-modifying inputs 
				// (e.g. 'SetCaption') or 'AddOutput <key> <value>' to it

				if (StrEqual(inputName, "AddOutput"))
				{
					TrimString(variantValue);
					if (regAddOutput.Match(variantValue) != -1)
					{
						char targetedKey[32];
						regAddOutput.GetSubString(1, targetedKey, sizeof(targetedKey));

						// Check if <key> is one of the entity's text keys
						ArrayList targetTextKeys; 
						if (g_TextEntKeys.GetValue(targetClassname, targetTextKeys) && 
							targetTextKeys.FindString(targetedKey) != -1)
						{
							// If it is, we save the <value> as another translatable message
							char newMessage[1024];
							regAddOutput.GetSubString(2, newMessage, sizeof(newMessage));
							AddToTranslatables(newMessage);
							continue;
						}
					}
				}
				else
				{
					// Check the rest of the inputs that can modify our target's text
					ArrayList targetTextInputs; 
					if (g_TextEntInputs.GetValue(target, targetTextInputs))
					{
						int maxTextInputs = targetTextInputs.Length;
						for (int inputIndex = 0; inputIndex < maxTextInputs; inputIndex++)
						{
							char textInput[64];
							targetTextInputs.GetString(inputIndex, textInput, sizeof(textInput));

							// Check if our output matches one of those inputs
							if (StrEqual(inputName, textInput))
							{
								AddToTranslatables(variantValue);
								continue;
							}
						} 
					}
				}
			}
		}

		delete entry;
	}

	delete nameToClass;
	delete regAddOutput;
}

void AddToTranslatables(const char[] text)
{
	//PrintToServer("Translatable: %s", text);
	g_ExportQueue.PushString(text);
}

// Taken from nosoop's repo
// https://github.com/nosoop/SMExt-EntityLump/blob/main/sourcepawn/entitylump_native_test.sp#L100
bool ParseEntityOutputString(const char[] output, char[] targetName, int targetNameLength,
		char[] inputName, int inputNameLength, char[] variantValue, int variantValueLength,
		float &delay, int &nFireCount) {
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
	
	nFireCount = StringToInt(output[delimiter]);
	
	return true;
}