#pragma semicolon 1
#pragma newdecls required

#include <smlib>
#include <dhooks>
#include <profiler>

#define MAX_USERMSG_LEN 255
#define MAX_OBJNOTIFY_LEN MAX_USERMSG_LEN 
#define MAX_KEYHINT_LEN MAX_USERMSG_LEN - 1
#define MAX_HUDMSG_LEN MAX_USERMSG_LEN - 34
#define MAX_MD5_LEN 33

#define MAX_LANGS 32
#define MAX_LANGCODE_LEN 10

#define GAME_UNKNOWN 0
#define GAME_NMRIH 1
#define GAME_ZPS 2

#define PLUGIN_VERSION "0.3.5"

#define PREFIX "[Map Translator] "

public Plugin myinfo = 
{
	name        = "[NMRiH/ZPS] Map Translator",
	author      = "Dysphie",
	description = "Translate maps via auto-generated configs",
	version     = PLUGIN_VERSION,
	url         = ""
};

ArrayStack exportQueue;

int activeEnvHint = -1;
int activeGameText = -1;
int game;

ConVar cvIgnoreNumerical;
ConVar cvTargetLangs;
ConVar cvDefaultLang;

char clientLang[MAXPLAYERS+1][MAX_LANGCODE_LEN];

StringMap translations;

void MO_UnloadTranslations()
{
	translations.Clear();
}

bool MO_LoadTranslations(const char[] path)
{
	KeyValues kv = new KeyValues("Phrases");
	kv.SetEscapeSequences(true);
	if (!kv.ImportFromFile(path) || !kv.GotoFirstSubKey())
	{
		delete kv;
		return;
	}

	do
	{
		char md5[MAX_MD5_LEN];
		kv.GetSectionName(md5, sizeof(md5));
		StrToLower(md5);

		// PrintToServer("Section: \"%s\"", md5);

		StringMap langs;

		if (kv.GotoFirstSubKey(false))
			langs = new StringMap();
		else
			continue;

		do
		{
			char code[MAX_LANGCODE_LEN], phrase[MAX_USERMSG_LEN];
			kv.GetSectionName(code, sizeof(code));
			StrToLower(code);
			kv.GetString(NULL_STRING, phrase, sizeof(phrase));
			langs.SetString(code, phrase);

			// PluginMessage("Keyvalue: \"%s\" \"%s\"", code, phrase);
		}
		while (kv.GotoNextKey(false));
		translations.SetValue(md5, langs);
		kv.GoBack();
	}
	while (kv.GotoNextKey());

	delete kv;
}

bool MO_TranslationPhraseExists(const char[] md5)
{
	StringMap value;
	return translations.GetValue(md5, value);
}

bool MO_TranslateForClient(int client, const char[] md5, char[] buffer, int maxlen)
{
	StringMap langs;
	if (!translations.GetValue(md5, langs))
		return false;
	
	if (langs.GetString(clientLang[client], buffer, maxlen))
		return true;

	static char fallback[MAX_LANGCODE_LEN];
	cvDefaultLang.GetString(fallback, sizeof(fallback));
	return langs.GetString(fallback, buffer, maxlen);
}

public void OnConfigsExecuted()
{
	AddCommandListener(Command_ReloadTranslations, "sm_reload_translations");

	char mapName[PLATFORM_MAX_PATH];
	if (!GetCurrentMap(mapName, sizeof(mapName)))
		return;	

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "translations/_maps/%s.txt", mapName);

	MO_LoadTranslations(path);

	// Do a quick scan and save any findings to the translation file
	// This won't pick up everything, but it's a good baseline
	// We'll also learn the map as it's played and save again in OnMapEnd

	if (game == GAME_ZPS)
		ZPS_LearnObjectives(exportQueue);
	else if (game == GAME_NMRIH)
		NMRiH_LearnObjectives(mapName, exportQueue);

	LearnTextEntity("game_text", exportQueue);
	LearnTextEntity("env_hudhint", exportQueue);

	FlushQueue(exportQueue, path);
}

public void OnPluginStart()
{
	LoadDetours();

	CreateConVar("mt_version", PLUGIN_VERSION, "Map Translator by Dysphie.",
		FCVAR_NOTIFY | FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_REPLICATED);

	RegAdminCmd("mt_bulk_learn_nmo", Command_LearnAll, ADMFLAG_ROOT);
	RegAdminCmd("mt_force_export", Command_ForceExport, ADMFLAG_ROOT,
		"Force the plugin to export any learned translations right now");

	cvIgnoreNumerical = CreateConVar("mt_ignore_numerical", "1", 
		"Don't translate or learn fully numerical messages such as codes, countdowns, etc.");

	cvTargetLangs = CreateConVar("mt_autolearn_langs", "",
		"Space-separated list of language entries to include in auto generated translation files");

	cvDefaultLang = CreateConVar("mt_fallback_lang", "en",
		"Clients whose language is not translated will see messages in this language");

	char path[PLATFORM_MAX_PATH];
	GetGameFolderName(path, sizeof(path));

	if (StrEqual(path, "nmrih"))
	{
		AutoExecConfig(true, "plugin.nmrih-map-translator"); // Backwards compat
		game = GAME_NMRIH;
		HookUserMessage(GetUserMessageId("ObjectiveNotify"), UserMsg_ObjectiveNotify, true);	
	}
	else
	{
		AutoExecConfig(true, "plugin.map-translator");

		if (StrEqual(path, "zps"))
		{
			game = GAME_ZPS;
			HookUserMessage(GetUserMessageId("ObjectiveState"), UserMsg_ObjectiveState, true);
		}
	}

	HookUserMessage(GetUserMessageId("KeyHintText"), UserMsg_KeyHintText, true);
	HookUserMessage(GetUserMessageId("HudMsg"), UserMsg_HudMsg, true);

	BuildPath(Path_SM, path, sizeof(path), "translations/_maps");
	if (!DirExists(path) && !CreateDirectory(path, 0o770))
		SetFailState("Failed to create required directory: %s", path);

	translations = new StringMap();
	exportQueue = new ArrayStack(ByteCountToCells(MAX_USERMSG_LEN));
}

public void OnClientConnected(int client)
{
	GetLanguageInfo(GetClientLanguage(client), clientLang[client], sizeof(clientLang[]));
}

public Action Command_LearnAll(int client, int args)
{
	if (game != GAME_NMRIH)
	{
		ReplyToCommand(client, "This command is only supported in No More Room in Hell");
		return Plugin_Handled;
	}

	if (!IsServerProcessing())
	{
		ReplyToCommand(client, "Can't build translations while server is hibernating.");
		return Plugin_Handled;
	}

	ArrayList maps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	ReadMapList(maps, .str="", .flags=MAPLIST_FLAG_NO_DEFAULT|MAPLIST_FLAG_MAPSFOLDER);

	DataPack data = new DataPack();
	data.WriteCell(0);
	data.WriteCell(maps);
	data.WriteCell(client);

	// Learning maps can take a while depending on hard drive speed
	// Enough to trigger the watchdog if done in a single frame
	RequestFrame(LearnMapsFrame, data);
	return Plugin_Handled;
}

public Action Command_ForceExport(int client, int args)
{
	char buffer[PLATFORM_MAX_PATH];
	GetCurrentMap(buffer, sizeof(buffer));
	BuildPath(Path_SM, buffer, sizeof(buffer), "translations/_maps/%s.txt", buffer);
	FlushQueue(exportQueue, buffer);
	
	ReplyToCommand(client, "Forced export queue flush");
	return Plugin_Handled;
}


void LearnMapsFrame(DataPack data)
{
	data.Reset();
	int cursor = data.ReadCell();
	ArrayList maps = data.ReadCell();
	int client = data.ReadCell();

	if (cursor >= maps.Length)
	{
		delete data;
		delete maps;
		ReplyToCommand(client, "Parsed %d maps", cursor-1);
		return;
	}

	static char buffer[PLATFORM_MAX_PATH];

	maps.GetString(cursor, buffer, sizeof(buffer));

	ArrayStack temp = new ArrayStack(ByteCountToCells(MAX_USERMSG_LEN));
	if (NMRiH_LearnObjectives(buffer, temp))
	{
		BuildPath(Path_SM, buffer, sizeof(buffer), "translations/_maps/%s.txt", buffer);
		FlushQueue(temp, buffer);
		// PrintToServer("Wrote: %s", buffer);
	}
	delete temp;
	
	data.Reset();
	data.WriteCell(++cursor);
	RequestFrame(LearnMapsFrame, data);
}

public Action Command_ReloadTranslations(int client, const char[] command, int argc)
{
	char mapName[PLATFORM_MAX_PATH];
	if (GetCurrentMap(mapName, sizeof(mapName)))
	{
		MO_UnloadTranslations();

		char path[PLATFORM_MAX_PATH];
		BuildPath(Path_SM, path, sizeof(path), "translations/_maps/%s.txt", mapName);
		MO_LoadTranslations(path);
		ReplyToCommand(client, PREFIX ... "Reloaded translations");
	}

	return Plugin_Continue;
}

public void OnMapEnd()
{
	char path[PLATFORM_MAX_PATH];
	GetCurrentMap(path, sizeof(path));
	BuildPath(Path_SM, path, sizeof(path), "translations/_maps/%s.txt", path);
	FlushQueue(exportQueue, path);

	MO_UnloadTranslations();
}

void LoadDetours()
{
	GameData gamedata = new GameData("map-translator.games");
	if (!gamedata)
		SetFailState("Failed to load gamedata");

	DynamicDetour detour;

	detour = DynamicDetour.FromConf(gamedata, "CGameText::Display");
	if (!detour)
		SetFailState("Failed to detour CGameText::Display");
	detour.Enable(Hook_Pre, Detour_GameTextDisplayPre);
	detour.Enable(Hook_Post, Detour_GameTextDisplayPost);
	delete detour;

	detour = DynamicDetour.FromConf(gamedata, "CEnvHudHint::InputShowHudHint");
	if (!detour)
		SetFailState("Failed to detour CEnvHudHint::InputShowHudHint");
	detour.Enable(Hook_Pre, Detour_HudHintShowPre);
	detour.Enable(Hook_Post, Detour_HudHintShowPost);
	delete detour;

	delete gamedata;
}


int LearnTextEntity(const char[] classname, ArrayStack stack)
{
	int count;
	char text[MAX_USERMSG_LEN];
	int e = -1;
	while ((e = FindEntityByClassname(e, classname)) != -1)
	{
		if (GetEntityHammerID(e) && GetEntPropString(e, Prop_Data, "m_iszMessage", text, sizeof(text)))
		{
			stack.PushString(text);
			count++;
		}
	}
	return count;
}

int ZPS_LearnObjectives(ArrayStack stack)
{
	int oblist = FindEntityByClassname(-1, "info_objective_list");
	if (oblist == -1)
		return 0;

	int count;
	char buffer[256];
	for (int i; i < 16; i++)
	{
		FormatEx(buffer, sizeof(buffer), "m_iszObjectiveMsg[%d]", i);
		if (!GetEntPropString(oblist, Prop_Data, buffer, buffer, sizeof(buffer)))
			continue;

		stack.PushString(buffer);
		count++;
	}
	return count;
}

int NMRiH_LearnObjectives(const char[] mapName, ArrayStack stack)
{
	// Open the .nmo file for reading
	char path[PLATFORM_MAX_PATH];
	FormatEx(path, sizeof(path), "maps/%s.nmo", mapName);

	// Starts here
	File f = OpenFile(path, "rb", true, NULL_STRING);
	if (!f)
		return 0;

	int header,version;
	f.ReadInt8(header);
	f.ReadInt32(version);

	if (header != 'v' || version != 1) 
	{
		delete f;
		return 0;
	}

	int objectivesCount;
	f.ReadInt32(objectivesCount);

	// skip antiObjectivesCount and extractionCount
	f.Seek(8, SEEK_CUR); 

	for (int o; o < objectivesCount; o++)
	{
		// Skip objective ID
		f.Seek(4, SEEK_CUR); 

		// Skip objective name
		SeekFileTillChar(f, '\0');
		
		char description[MAX_USERMSG_LEN];
		ReadFileString2(f, description, sizeof(description));

		if (description[0])
			stack.PushString(description);

		// Skip objective boundary name
		SeekFileTillChar(f, '\0');
		
		// Skip item names
		int itemCount;
		f.ReadInt32(itemCount);
		if (itemCount > 0)
			while (itemCount--)
				SeekFileTillChar(f, '\0');		

		// Skip objective links
		int linksCount;
		f.ReadInt32(linksCount);
		if (linksCount > 0) 
			f.Seek(linksCount * 4, SEEK_CUR);
	}

	delete f;
	return objectivesCount;
}

public MRESReturn Detour_GameTextDisplayPre(int gametext)
{
	activeGameText = gametext;
}

public MRESReturn Detour_GameTextDisplayPost(int gametext)
{
	activeGameText = -1;
}

public MRESReturn Detour_HudHintShowPre(int envhint)
{
	activeEnvHint = envhint;
}

public MRESReturn Detour_HudHintShowPost(int envhint)
{
	activeEnvHint = -1;
}

bool IsNumericalString(const char[] str)
{
	int value;
	return StringToIntEx(str, value) == strlen(str);
}

void FlushQueue(ArrayStack& stack, const char[] path)
{	
	char langCodes[MAX_LANGS][MAX_LANGCODE_LEN];
	char targetLangs[MAX_LANGS*MAX_LANGCODE_LEN];
	cvTargetLangs.GetString(targetLangs, sizeof(targetLangs));
	ExplodeString(targetLangs, " ", langCodes, sizeof(langCodes), sizeof(langCodes[]));

	KeyValues kv = new KeyValues("Phrases");
	kv.SetEscapeSequences(true);
	kv.ImportFromFile(path);

	char buffer[MAX_USERMSG_LEN], md5[MAX_MD5_LEN];
	while (!stack.Empty)
	{
		stack.PopString(buffer, sizeof(buffer));

		if (IsNumericalString(buffer) && cvIgnoreNumerical.BoolValue)
			continue;

		Crypt_MD5(buffer, md5, sizeof(md5));

		kv.JumpToKey(md5, true);

		for (int i; i < sizeof(langCodes); i++)
		{
			if (!langCodes[i][0])
				continue;

			// Don't override existing
			if (kv.JumpToKey(langCodes[i]))
			{
				// PrintToServer("key %s is already populated ignoring", langCodes[i]);
				kv.GoBack();
			}
			else
				kv.SetString(langCodes[i], buffer);
		}
		
		kv.GoBack();
	}

	kv.Rewind();
	kv.ExportToFile(path);
}

public Action UserMsg_ObjectiveState(UserMsg msg, BfRead bf, const int[] players, int playersNum, bool reliable, bool init)
{
	int dunnoByte = bf.ReadByte(); // I dunno..
	
	static char text[MAX_KEYHINT_LEN];
	if (bf.ReadString(text, sizeof(text)) <= 0)
		return Plugin_Continue;

	// PrintToServer("UserMsg_ObjectiveState: %d %s", dunnoByte, text);

	static char md5[MAX_MD5_LEN];
	Crypt_MD5(text, md5, sizeof(md5));

	if (!MO_TranslationPhraseExists(md5))
	{
		PrintToServer("Translation for \"%s\" not here", text);
		exportQueue.PushString(text);
		return Plugin_Continue;
	}

	DataPack data = new DataPack();
	data.WriteCell(dunnoByte);
	data.WriteString(text);
	data.WriteString(md5);
	data.WriteCell(playersNum);

	for(int i; i < playersNum; i++)
		data.WriteCell(GetClientSerial(players[i]));

	RequestFrame(Translate_ObjectiveState, data);
	return Plugin_Handled;
}

public Action UserMsg_KeyHintText(UserMsg msg, BfRead bf, const int[] players, int playersNum, bool reliable, bool init)
{
	if (activeEnvHint == -1 || !GetEntityHammerID(activeEnvHint))
	{
		// PrintToServer("Ignoring env_hudhint %d, no hammer ID", activeEnvHint);
		return Plugin_Continue;
	}

	int dunnoByte = bf.ReadByte(); // I dunno..
	
	static char text[MAX_KEYHINT_LEN];
	if (bf.ReadString(text, sizeof(text)) <= 0)
		return Plugin_Continue;

	// PrintToServer("UserMsg_KeyHintText: %s", text);

	static char md5[MAX_MD5_LEN];

	Crypt_MD5(text, md5, sizeof(md5));

	if (!MO_TranslationPhraseExists(md5))
	{
		exportQueue.PushString(text);
		return Plugin_Continue;
	}

	DataPack data = new DataPack();
	data.WriteCell(dunnoByte);
	data.WriteString(text);
	data.WriteString(md5);
	data.WriteCell(playersNum);

	for(int i; i < playersNum; i++)
		data.WriteCell(GetClientSerial(players[i]));

	RequestFrame(Translate_KeyHintText, data);
	return Plugin_Handled;
}

public Action UserMsg_ObjectiveNotify(UserMsg msg, BfRead bf, const int[] players, int playersNum, bool reliable, bool init)
{
	char text[MAX_OBJNOTIFY_LEN];
	if (bf.ReadString(text, sizeof(text)) <= 0)
		return Plugin_Continue;

	char md5[MAX_MD5_LEN];
	Crypt_MD5(text, md5, sizeof(md5));

	// Don't push anything to queue here, we learn objectives
	// thru the .nmo, not at runtime
	if (!MO_TranslationPhraseExists(md5))
		return Plugin_Continue;

	DataPack data = new DataPack();
	data.WriteString(text);
	data.WriteString(md5);
	data.WriteCell(playersNum);

	for(int i; i < playersNum; i++)
		data.WriteCell(GetClientSerial(players[i]));

	RequestFrame(Translate_ObjectiveNotify, data);
	return Plugin_Handled;
}

public Action UserMsg_HudMsg(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if (activeGameText == -1 || !GetEntityHammerID(activeGameText))
	{
		// PrintToServer("Ignoring game_text %d, no hammer ID", activeEnvHint);
		return Plugin_Continue;
	}

	int channel = msg.ReadByte();
	float x = msg.ReadFloat();
	float y = msg.ReadFloat();
	int effect = msg.ReadByte();
	int r1 = msg.ReadByte();
	int g1 = msg.ReadByte();
	int b1 = msg.ReadByte();
	int a1 = msg.ReadByte();
	int r2 = msg.ReadByte();
	int g2 = msg.ReadByte();
	int b2 = msg.ReadByte();	
	int a2 = msg.ReadByte();
	float fadeIn = msg.ReadFloat();
	float fadeOut = msg.ReadFloat();
	float holdTime = msg.ReadFloat();
	float fxTime = msg.ReadFloat();

	static char text[MAX_HUDMSG_LEN];
	if (msg.ReadString(text, sizeof(text)) <= 0)
		return Plugin_Continue;

	static char md5[MAX_MD5_LEN];
	Crypt_MD5(text, md5, sizeof(md5));

	if (!MO_TranslationPhraseExists(md5))
	{
		exportQueue.PushString(text);
		return Plugin_Continue;
	}
	
	DataPack data = new DataPack();

	data.WriteCell(channel);
	data.WriteFloat(x);
	data.WriteFloat(y);
	data.WriteCell(effect);
	data.WriteCell(r1);
	data.WriteCell(g1);
	data.WriteCell(b1);
	data.WriteCell(a1);
	data.WriteCell(r2);
	data.WriteCell(g2);
	data.WriteCell(b2);
	data.WriteCell(a2);
	data.WriteFloat(fadeIn);
	data.WriteFloat(fadeOut);
	data.WriteFloat(holdTime);
	data.WriteFloat(fxTime);
	data.WriteString(text);
	data.WriteString(md5);

	data.WriteCell(playersNum);
	for(int i; i < playersNum; i++)
		data.WriteCell(GetClientSerial(players[i]));

	RequestFrame(Translate_HudMsg, data);
	return Plugin_Handled;
}

void Translate_KeyHintText(DataPack data)
{
	data.Reset();
	int dunnoByte = data.ReadCell();

	char original[MAX_KEYHINT_LEN];
	data.ReadString(original, sizeof(original));

	char md5[MAX_MD5_LEN];
	data.ReadString(md5, sizeof(md5));

	char translated[MAX_KEYHINT_LEN];
	
	int playersNum = data.ReadCell();
	for (int i; i < playersNum; i++)
	{
		int client = GetClientFromSerial(data.ReadCell());
		if (!client)
			continue;

		bool didTranslate = MO_TranslateForClient(client, md5, translated, sizeof(translated));

		Handle msg = StartMessageOne("KeyHintText", client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);
		BfWrite bf = UserMessageToBfWrite(msg);
		bf.WriteByte(dunnoByte);
		bf.WriteString(didTranslate ? translated : original);
		EndMessage();
	}

	delete data;
}

void Translate_ObjectiveState(DataPack data)
{
	data.Reset();
	int dunnoByte = data.ReadCell();

	char original[MAX_KEYHINT_LEN];
	data.ReadString(original, sizeof(original));

	char md5[MAX_MD5_LEN];
	data.ReadString(md5, sizeof(md5));

	char translated[MAX_KEYHINT_LEN];
	
	int playersNum = data.ReadCell();
	for (int i; i < playersNum; i++)
	{
		int client = GetClientFromSerial(data.ReadCell());
		if (!client)
			continue;

		bool didTranslate = MO_TranslateForClient(client, md5, translated, sizeof(translated));

		Handle msg = StartMessageOne("ObjectiveState", client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);
		BfWrite bf = UserMessageToBfWrite(msg);
		bf.WriteByte(dunnoByte);
		bf.WriteString(didTranslate ? translated : original);
		EndMessage();
	}

	delete data;
}

void Translate_ObjectiveNotify(DataPack data)
{
	data.Reset();

	char original[MAX_OBJNOTIFY_LEN];
	data.ReadString(original, sizeof(original));

	char md5[MAX_MD5_LEN];
	data.ReadString(md5, sizeof(md5));

	int playersNum = data.ReadCell();

	for (int i; i < playersNum; i++)
	{
		int client = GetClientFromSerial(data.ReadCell());
		if(!client)
			continue;

		char translated[PLATFORM_MAX_PATH];
		bool didTranslate = MO_TranslateForClient(client, md5, translated, sizeof(translated));

		Handle msg = StartMessageOne("ObjectiveNotify", client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);
		BfWrite bf = UserMessageToBfWrite(msg);
		bf.WriteString(didTranslate ? translated : original);
		EndMessage();
	}

	delete data;
} 

void Translate_HudMsg(DataPack data)
{
	data.Reset();

	int channel = data.ReadCell();
	float x = data.ReadFloat();
	float y = data.ReadFloat();
	int r1 = data.ReadCell();
	int g1 = data.ReadCell();
	int b1 = data.ReadCell();
	int a1 = data.ReadCell();
	int r2 = data.ReadCell();
	int g2 = data.ReadCell();
	int b2 = data.ReadCell();
	int a2 = data.ReadCell();
	int effect = data.ReadCell();
	float fadeIn = data.ReadFloat();
	float fadeOut = data.ReadFloat();
	float holdTime = data.ReadFloat();
	float fxTime = data.ReadFloat();

	char original[MAX_HUDMSG_LEN];
	data.ReadString(original, sizeof(original));

	char md5[MAX_MD5_LEN];
	data.ReadString(md5, sizeof(md5));

	char translated[MAX_HUDMSG_LEN];

	int playersNum = data.ReadCell();
	for (int i; i < playersNum; i++)
	{
		int client = GetClientFromSerial(data.ReadCell());
		if (!client)
			continue;

		bool didTranslate = MO_TranslateForClient(client, md5, translated, sizeof(translated));

		Handle msg = StartMessageOne("HudMsg", client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);
		BfWrite bf = UserMessageToBfWrite(msg);

		bf.WriteByte(channel);
		bf.WriteFloat(x);
		bf.WriteFloat(y);
		bf.WriteByte(r1);
		bf.WriteByte(g1);
		bf.WriteByte(b1);
		bf.WriteByte(a1);
		bf.WriteByte(r2);
		bf.WriteByte(g2);
		bf.WriteByte(b2);
		bf.WriteByte(a2);
		bf.WriteByte(effect);
		bf.WriteFloat(fadeIn);
		bf.WriteFloat(fadeOut);
		bf.WriteFloat(holdTime);
		bf.WriteFloat(fxTime);
		bf.WriteString(didTranslate ? translated : original);
		EndMessage();
	}

	delete data;
}

int GetEntityHammerID(int entity)
{
	return GetEntProp(entity, Prop_Data, "m_iHammerID");
}

void SeekFileTillChar(File file, char c)
{
	int i;
	do {
		file.ReadInt8(i);
	} while (i != c);	
}

/* Similar to ReadFileString, but the file position always ends up at the 
 * null terminator (https://github.com/alliedmodders/sourcemod/issues/1430)
 */
void ReadFileString2(File file, char[] buffer, int maxlen)
{
	file.ReadString(buffer, maxlen, -1);

	// Ensure we've consumed the full string..
	file.Seek(-1, SEEK_CUR);
	SeekFileTillChar(file, '\0');
}

void StrToLower(char[] str)
{
	int i;
	while (str[i])
	{
		str[i] = CharToLower(str[i]);
		i++;
	}
}
