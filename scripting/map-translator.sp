#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <dhooks>

#define MAX_USERMSG_LEN 255
#define MAX_OBJNOTIFY_LEN MAX_USERMSG_LEN 
#define MAX_KEYHINT_LEN MAX_USERMSG_LEN - 1
#define MAX_HUDMSG_LEN MAX_USERMSG_LEN - 34
#define MAX_INSTRUCTOR_LEN MAX_USERMSG_LEN // TODO: Subtract other params
#define MAX_POINTTEXTMP_LEN MAX_USERMSG_LEN // TODO: Subtract other params

#define MAX_MD5_LEN 33

#define MAX_LANGS 32
#define MAX_LANGCODE_LEN 10

#define GAME_UNKNOWN 0
#define GAME_NMRIH 1
#define GAME_ZPS 2

#define PLUGIN_VERSION "1.3.11"

#define PREFIX "[Map Translator] "

public Plugin myinfo = 
{
	name        = "[NMRiH/ZPS] Map Translator",
	author      = "Dysphie",
	description = "Translate maps via auto-generated configs",
	version     = PLUGIN_VERSION,
	url         = "https://github.com/dysphie/sm-map-translator"
};

ArrayStack g_ExportQueue;

#include "map-translator/ent-lump-parser.sp"

int g_Game = GAME_UNKNOWN;

ConVar cvIgnoreNumerical;
ConVar cvTargetLangs;
ConVar cvDefaultLang;

bool g_Lateloaded;

char g_ClientLangCode[MAXPLAYERS+1][MAX_LANGCODE_LEN];

StringMap g_Translations;

void MO_UnloadTranslations()
{
	g_Translations.Clear();
}

void MO_LoadTranslations(const char[] path)
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
		g_Translations.SetValue(md5, langs);
		kv.GoBack();
	}
	while (kv.GotoNextKey());

	delete kv;
}

bool MO_TranslationPhraseExists(const char[] md5)
{
	StringMap value;
	return g_Translations.GetValue(md5, value);
}

bool MO_TranslateForClient(int client, const char[] md5, char[] buffer, int maxlen)
{
	StringMap langs;
	if (!g_Translations.GetValue(md5, langs)) {
		return false;
	}
	
	if (langs.GetString(g_ClientLangCode[client], buffer, maxlen)) {
		return true;
	}

	static char fallback[MAX_LANGCODE_LEN];
	cvDefaultLang.GetString(fallback, sizeof(fallback));
	return langs.GetString(fallback, buffer, maxlen);
}

public void OnConfigsExecuted()
{
	char mapName[PLATFORM_MAX_PATH];
	if (!GetCurrentMap(mapName, sizeof(mapName))) {
		return;	
	}

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "translations/_maps/%s.txt", mapName);

	MO_LoadTranslations(path);

	// Do a quick scan and save any findings to the translation file
	// This won't pick up everything, but it's a good baseline
	// We'll also learn the map as it's played and save again in OnMapEnd

	if (g_Game == GAME_ZPS)
	{
		ZPS_LearnObjectives(g_ExportQueue);
	}
	else if (g_Game == GAME_NMRIH)
	{
		NMRiH_LearnObjectives(mapName, g_ExportQueue);
	}

	FlushQueue(g_ExportQueue, path);
}

public void OnClientLanguageChanged(int client, int language)
{
	GetLanguageInfo(language, g_ClientLangCode[client], sizeof(g_ClientLangCode[]));
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_Lateloaded = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	AddCommandListener(Command_ReloadTranslations, "sm_reload_translations");

	char path[PLATFORM_MAX_PATH];
	GetGameFolderName(path, sizeof(path));
	if (StrEqual(path, "zps")) {
		g_Game = GAME_ZPS;
	} else if (StrEqual(path, "nmrih")) {
		g_Game = GAME_NMRIH;
	}

	Parser_OnPluginStart();

	CreateConVar("mt_version", PLUGIN_VERSION, "Map Translator by Dysphie.",
		FCVAR_NOTIFY | FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_REPLICATED);

	RegAdminCmd("mt_bulk_learn_nmo", Command_LearnAll, ADMFLAG_ROOT);
	RegAdminCmd("mt_force_export", Command_ForceExport, ADMFLAG_ROOT,
		"Force the plugin to export any learned translations right now");

	RegAdminCmd("mt_debug_clients", Command_DebugClients, ADMFLAG_ROOT,
		"Prints the currently perceived language code for each client");

	cvIgnoreNumerical = CreateConVar("mt_ignore_numerical", "1", 
		"Don't translate or learn fully numerical messages such as codes, countdowns, etc.");

	cvTargetLangs = CreateConVar("mt_autolearn_langs", "",
		"Space-separated list of language entries to include in auto generated translation files");

	cvDefaultLang = CreateConVar("mt_fallback_lang", "en",
		"Clients whose language is not translated will see messages in this language");

	if (g_Game == GAME_NMRIH)
	{
		AutoExecConfig(true, "plugin.nmrih-map-translator"); // Backwards compat
		HookUserMessage(GetUserMessageId("ObjectiveNotify"), UserMsg_ObjectiveNotify, true);
		HookUserMessage(GetUserMessageId("PointMessage"), UserMsg_PointMessageMultiplayer, true);
		HookEvent("instructor_server_hint_create", Event_InstructorHintCreate, EventHookMode_Pre);
	}
	else
	{
		AutoExecConfig(true, "plugin.map-translator");

		if (g_Game == GAME_ZPS)
		{
			HookUserMessage(GetUserMessageId("ObjectiveState"), UserMsg_ObjectiveState, true);
		}
	}

	HookUserMessage(GetUserMessageId("KeyHintText"), UserMsg_KeyHintText, true);
	HookUserMessage(GetUserMessageId("HudMsg"), UserMsg_HudMsg, true);

	BuildPath(Path_SM, path, sizeof(path), "translations/_maps");
	if (!DirExists(path) && !CreateDirectory(path, 0o770))
		SetFailState("Failed to create required directory: %s", path);

	g_Translations = new StringMap();
	g_ExportQueue = new ArrayStack(ByteCountToCells(MAX_USERMSG_LEN));

	if (g_Lateloaded)
	{
		for (int client = 1; client <= MaxClients; client++)
		{
			if (IsClientInGame(client))
			{
				OnClientLanguageChanged(client, GetClientLanguage(client));
			}
		}
	}
}

Action Command_DebugClients(int client, int args)
{
	int count = GetClientCount();
	if (!count) 
	{
		ReplyToCommand(client, "No clients found.");
		return Plugin_Handled;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			ReplyToCommand(client, "%N: %s", i, g_ClientLangCode[i]);
		}
	}

	return Plugin_Handled;
}
Action Command_LearnAll(int client, int args)
{
	if (g_Game != GAME_NMRIH)
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

Action Command_ForceExport(int client, int args)
{
	char buffer[PLATFORM_MAX_PATH];
	GetCurrentMap(buffer, sizeof(buffer));
	BuildPath(Path_SM, buffer, sizeof(buffer), "translations/_maps/%s.txt", buffer);
	FlushQueue(g_ExportQueue, buffer);
	
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

Action Command_ReloadTranslations(int client, const char[] command, int argc)
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
	FlushQueue(g_ExportQueue, path);

	MO_UnloadTranslations();
}

int ZPS_LearnObjectives(ArrayStack stack)
{
	int oblist = FindEntityByClassname(-1, "info_objective_list");
	if (oblist == -1) {
		return 0;
	}

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
	if (!f) {
		return 0;
	}

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

	int count = 0;
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
		
		count++;
		kv.GoBack();
	}

	kv.Rewind();
	kv.ExportToFile(path);

	delete kv;

	// PrintToServer("Exported %d phrases", count);
}

Action Event_InstructorHintCreate(Event event, const char[] name, bool dontBroadcast)
{
	// Instructor has 2 texts, one specific to the !activator
	// and one to everyone else.

	char baseText[MAX_USERMSG_LEN];
	event.GetString("hint_caption", baseText, sizeof(baseText));
	char baseMd5[MAX_MD5_LEN];
	Crypt_MD5(baseText, baseMd5, sizeof(baseMd5));

	bool missingBaseHint = false;
	if (!MO_TranslationPhraseExists(baseMd5))
	{
		missingBaseHint = true;
	}

	char activatorText[MAX_USERMSG_LEN];
	event.GetString("hint_activator_caption", activatorText, sizeof(activatorText));
	char activatorMd5[MAX_MD5_LEN];
	Crypt_MD5(activatorText, activatorMd5, sizeof(activatorMd5));

	bool missingActivatorHint = false;
	// TODO: This might create a duplicate hint if the activator is the same as the base
	if (!MO_TranslationPhraseExists(activatorMd5))
	{
		missingActivatorHint = true;
	}

	// If we are missing translation for both texts,
	// there's nothing for us to do here
	if (missingBaseHint && missingActivatorHint) {
		return Plugin_Continue;
	}

	char translatedBaseText[MAX_USERMSG_LEN];
	char translatedActivatorText[MAX_USERMSG_LEN];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		if (!missingBaseHint && MO_TranslateForClient(i, baseMd5, translatedBaseText, sizeof(translatedBaseText))) {
			event.SetString("hint_caption", translatedBaseText);
		} else {
			event.SetString("hint_caption", baseText);
		}

		if (!missingActivatorHint && MO_TranslateForClient(i, activatorMd5, translatedActivatorText, sizeof(translatedActivatorText))) {
			event.SetString("hint_activator_caption", translatedActivatorText);
		} else {
			event.SetString("hint_activator_caption", activatorText);
		}
		
		event.FireToClient(i);
	}

	// Eat the original event
	event.BroadcastDisabled = true;

	// FIXME: Do we need to call event.Cancel here?
	return Plugin_Continue;
}


Action UserMsg_ObjectiveState(UserMsg msg, BfRead bf, const int[] players, int playersNum, bool reliable, bool init)
{
	int dunnoByte = bf.ReadByte(); // I dunno..
	
	static char text[MAX_KEYHINT_LEN];
	if (bf.ReadString(text, sizeof(text)) <= 0) {
		return Plugin_Continue;
	}

	// PrintToServer("UserMsg_ObjectiveState: %d %s", dunnoByte, text);

	static char md5[MAX_MD5_LEN];
	Crypt_MD5(text, md5, sizeof(md5));

	if (!MO_TranslationPhraseExists(md5)) {
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

Action UserMsg_KeyHintText(UserMsg msg, BfRead bf, const int[] players, int playersNum, bool reliable, bool init)
{
	int dunnoByte = bf.ReadByte(); // I dunno..
	
	static char text[MAX_KEYHINT_LEN];
	if (bf.ReadString(text, sizeof(text)) <= 0) {
		return Plugin_Continue;
	}

	// PrintToServer("UserMsg_KeyHintText: %s", text);

	static char md5[MAX_MD5_LEN];

	Crypt_MD5(text, md5, sizeof(md5));

	if (!MO_TranslationPhraseExists(md5)) {
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

Action UserMsg_ObjectiveNotify(UserMsg msg, BfRead bf, const int[] players, int playersNum, bool reliable, bool init)
{
	char text[MAX_OBJNOTIFY_LEN];
	if (bf.ReadString(text, sizeof(text)) <= 0) {
		return Plugin_Continue;
	}

	char md5[MAX_MD5_LEN];
	Crypt_MD5(text, md5, sizeof(md5));

	// Don't push anything to queue here, we learn objectives
	// thru the .nmo, not at runtime
	if (!MO_TranslationPhraseExists(md5)) {
		return Plugin_Continue;
	}

	DataPack data = new DataPack();
	data.WriteString(text);
	data.WriteString(md5);
	data.WriteCell(playersNum);

	for(int i; i < playersNum; i++)
		data.WriteCell(GetClientSerial(players[i]));

	RequestFrame(Translate_ObjectiveNotify, data);
	return Plugin_Handled;
}

Action UserMsg_PointMessageMultiplayer(UserMsg msg, BfRead bf, const int[] players, int playersNum, bool reliable, bool init)
{
	static char text[MAX_POINTTEXTMP_LEN];
	if (bf.ReadString(text, sizeof(text)) <= 0) {
		return Plugin_Continue;
	}

	static char md5[MAX_MD5_LEN];
	Crypt_MD5(text, md5, sizeof(md5));

	if (!MO_TranslationPhraseExists(md5)) {
		return Plugin_Continue;
	}

	int entity = bf.ReadShort();
	int flags = bf.ReadShort();

	float coord[3];
	bf.ReadVecCoord(coord);

	float radius = bf.ReadFloat();

	char fontName[64];
	bf.ReadString(fontName, sizeof(fontName));

	int r = bf.ReadByte();
	int g = bf.ReadByte();
	int b = bf.ReadByte();
	
	DataPack data = new DataPack();
	data.WriteString(text);
	data.WriteString(md5);
	data.WriteCell(entity);
	data.WriteCell(flags);
	data.WriteFloat(coord[0]);
	data.WriteFloat(coord[1]);
	data.WriteFloat(coord[2]);
	data.WriteFloat(radius);
	data.WriteString(fontName);
	data.WriteCell(r);
	data.WriteCell(g);
	data.WriteCell(b);
	data.WriteCell(playersNum);

	for (int i; i < playersNum; i++)
	{
		data.WriteCell(GetClientSerial(players[i]));
	}

	RequestFrame(Translate_PointMessageMultiplayer, data);
	return Plugin_Handled;
}

Action UserMsg_HudMsg(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
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
	if (msg.ReadString(text, sizeof(text)) <= 0) {
		return Plugin_Continue;
	}

	static char md5[MAX_MD5_LEN];
	Crypt_MD5(text, md5, sizeof(md5));

	if (!MO_TranslationPhraseExists(md5)) {
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

void Translate_PointMessageMultiplayer(DataPack data)
{
	data.Reset();

	char original[MAX_POINTTEXTMP_LEN];
	data.ReadString(original, sizeof(original));

	char md5[MAX_MD5_LEN];
	data.ReadString(md5, sizeof(md5));

	int entity = data.ReadCell();
	int flags = data.ReadCell();
	float coord[3];
	
	coord[0] = data.ReadFloat();
	coord[1] = data.ReadFloat();
	coord[2] = data.ReadFloat();
	
	float radius = data.ReadFloat();
	
	char fontName[64];
	data.ReadString(fontName, sizeof(fontName));

	int r = data.ReadCell();
	int g = data.ReadCell();
	int b = data.ReadCell();

	int playersNum = data.ReadCell();

	int[] userids = new int[playersNum];
	for (int i; i < playersNum; i++)
	{
		userids[i] = data.ReadCell();
	}

	delete data;

	char translated[MAX_POINTTEXTMP_LEN];

	for (int i; i < playersNum; i++)
	{
		int client = GetClientFromSerial(userids[i]);
		if (!client)
			continue;

		bool didTranslate = MO_TranslateForClient(client, md5, translated, sizeof(translated));

		Handle msg = StartMessageOne("PointMessage", client, USERMSG_BLOCKHOOKS);
		BfWrite bf = UserMessageToBfWrite(msg);
		
		bf.WriteString(didTranslate ? translated : original);
		bf.WriteShort(entity);
		bf.WriteShort(flags);
		bf.WriteVecCoord(coord);
		bf.WriteFloat(radius);
		bf.WriteString(fontName);
		bf.WriteByte(r);
		bf.WriteByte(g);
		bf.WriteByte(b);
		
		EndMessage();
	}
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

	int playersNum = data.ReadCell();

	int[] userids = new int[playersNum];
	for (int i; i < playersNum; i++)
	{
		userids[i] = data.ReadCell();
	}

	delete data;

	char translated[MAX_HUDMSG_LEN];

	for (int i; i < playersNum; i++)
	{
		int client = GetClientFromSerial(userids[i]);
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

// MD5 stuff, taken from smlib

void Crypt_MD5(const char[] str, char[] output, int maxlen)
{
	int x[2];
	int buf[4];
	int input[64];
	int i, ii;

	int len = strlen(str);

	// MD5Init
	x[0] = x[1] = 0;
	buf[0] = 0x67452301;
	buf[1] = 0xefcdab89;
	buf[2] = 0x98badcfe;
	buf[3] = 0x10325476;

	// MD5Update
	int update[16];

	update[14] = x[0];
	update[15] = x[1];

	int mdi = (x[0] >>> 3) & 0x3F;

	if ((x[0] + (len << 3)) < x[0]) {
		x[1] += 1;
	}

	x[0] += len << 3;
	x[1] += len >>> 29;

	int c = 0;
	while (len--) {
		input[mdi] = str[c];
		mdi += 1;
		c += 1;

		if (mdi == 0x40) {

			for (i = 0, ii = 0; i < 16; ++i, ii += 4)
			{
				update[i] = (input[ii + 3] << 24) | (input[ii + 2] << 16) | (input[ii + 1] << 8) | input[ii];
			}

			// Transform
			MD5Transform(buf, update);

			mdi = 0;
		}
	}

	// MD5Final
	int padding[64] = {
		0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
	};

	int inx[16];
	inx[14] = x[0];
	inx[15] = x[1];

	mdi = (x[0] >>> 3) & 0x3F;

	len = (mdi < 56) ? (56 - mdi) : (120 - mdi);
	update[14] = x[0];
	update[15] = x[1];

	mdi = (x[0] >>> 3) & 0x3F;

	if ((x[0] + (len << 3)) < x[0]) {
		x[1] += 1;
	}

	x[0] += len << 3;
	x[1] += len >>> 29;

	c = 0;
	while (len--) {
		input[mdi] = padding[c];
		mdi += 1;
		c += 1;

		if (mdi == 0x40) {

			for (i = 0, ii = 0; i < 16; ++i, ii += 4) {
				update[i] = (input[ii + 3] << 24) | (input[ii + 2] << 16) | (input[ii + 1] << 8) | input[ii];
			}

			// Transform
			MD5Transform(buf, update);

			mdi = 0;
		}
	}

	for (i = 0, ii = 0; i < 14; ++i, ii += 4) {
		inx[i] = (input[ii + 3] << 24) | (input[ii + 2] << 16) | (input[ii + 1] << 8) | input[ii];
	}

	MD5Transform(buf, inx);

	int digest[16];
	for (i = 0, ii = 0; i < 4; ++i, ii += 4) {
		digest[ii] = (buf[i]) & 0xFF;
		digest[ii + 1] = (buf[i] >>> 8) & 0xFF;
		digest[ii + 2] = (buf[i] >>> 16) & 0xFF;
		digest[ii + 3] = (buf[i] >>> 24) & 0xFF;
	}

	FormatEx(output, maxlen, "%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
		digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
		digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]);
}


void MD5Transform_FF(int &a, int &b, int &c, int &d, int x, int s, int ac)
{
	a += (((b) & (c)) | ((~b) & (d))) + x + ac;
	a = (((a) << (s)) | ((a) >>> (32-(s))));
	a += b;
}

void MD5Transform_GG(int &a, int &b, int &c, int &d, int x, int s, int ac)
{
	a += (((b) & (d)) | ((c) & (~d))) + x + ac;
	a = (((a) << (s)) | ((a) >>> (32-(s))));
	a += b;
}

void MD5Transform_HH(int &a, int &b, int &c, int &d, int x, int s, int ac)
	{
	a += ((b) ^ (c) ^ (d)) + x + ac;
	a = (((a) << (s)) | ((a) >>> (32-(s))));
	a += b;
}

void MD5Transform_II(int &a, int &b, int &c, int &d, int x, int s, int ac)
{
	a += ((c) ^ ((b) | (~d))) + x + ac;
	a = (((a) << (s)) | ((a) >>> (32-(s))));
	a += b;
}

void MD5Transform(int[] buf, int[] input)
{
	int a = buf[0];
	int b = buf[1];
	int c = buf[2];
	int d = buf[3];

	MD5Transform_FF(a, b, c, d, input[0], 7, 0xd76aa478);
	MD5Transform_FF(d, a, b, c, input[1], 12, 0xe8c7b756);
	MD5Transform_FF(c, d, a, b, input[2], 17, 0x242070db);
	MD5Transform_FF(b, c, d, a, input[3], 22, 0xc1bdceee);
	MD5Transform_FF(a, b, c, d, input[4], 7, 0xf57c0faf);
	MD5Transform_FF(d, a, b, c, input[5], 12, 0x4787c62a);
	MD5Transform_FF(c, d, a, b, input[6], 17, 0xa8304613);
	MD5Transform_FF(b, c, d, a, input[7], 22, 0xfd469501);
	MD5Transform_FF(a, b, c, d, input[8], 7, 0x698098d8);
	MD5Transform_FF(d, a, b, c, input[9], 12, 0x8b44f7af);
	MD5Transform_FF(c, d, a, b, input[10], 17, 0xffff5bb1);
	MD5Transform_FF(b, c, d, a, input[11], 22, 0x895cd7be);
	MD5Transform_FF(a, b, c, d, input[12], 7, 0x6b901122);
	MD5Transform_FF(d, a, b, c, input[13], 12, 0xfd987193);
	MD5Transform_FF(c, d, a, b, input[14], 17, 0xa679438e);
	MD5Transform_FF(b, c, d, a, input[15], 22, 0x49b40821);

	MD5Transform_GG(a, b, c, d, input[1], 5, 0xf61e2562);
	MD5Transform_GG(d, a, b, c, input[6], 9, 0xc040b340);
	MD5Transform_GG(c, d, a, b, input[11], 14, 0x265e5a51);
	MD5Transform_GG(b, c, d, a, input[0], 20, 0xe9b6c7aa);
	MD5Transform_GG(a, b, c, d, input[5], 5, 0xd62f105d);
	MD5Transform_GG(d, a, b, c, input[10], 9, 0x02441453);
	MD5Transform_GG(c, d, a, b, input[15], 14, 0xd8a1e681);
	MD5Transform_GG(b, c, d, a, input[4], 20, 0xe7d3fbc8);
	MD5Transform_GG(a, b, c, d, input[9], 5, 0x21e1cde6);
	MD5Transform_GG(d, a, b, c, input[14], 9, 0xc33707d6);
	MD5Transform_GG(c, d, a, b, input[3], 14, 0xf4d50d87);
	MD5Transform_GG(b, c, d, a, input[8], 20, 0x455a14ed);
	MD5Transform_GG(a, b, c, d, input[13], 5, 0xa9e3e905);
	MD5Transform_GG(d, a, b, c, input[2], 9, 0xfcefa3f8);
	MD5Transform_GG(c, d, a, b, input[7], 14, 0x676f02d9);
	MD5Transform_GG(b, c, d, a, input[12], 20, 0x8d2a4c8a);

	MD5Transform_HH(a, b, c, d, input[5], 4, 0xfffa3942);
	MD5Transform_HH(d, a, b, c, input[8], 11, 0x8771f681);
	MD5Transform_HH(c, d, a, b, input[11], 16, 0x6d9d6122);
	MD5Transform_HH(b, c, d, a, input[14], 23, 0xfde5380c);
	MD5Transform_HH(a, b, c, d, input[1], 4, 0xa4beea44);
	MD5Transform_HH(d, a, b, c, input[4], 11, 0x4bdecfa9);
	MD5Transform_HH(c, d, a, b, input[7], 16, 0xf6bb4b60);
	MD5Transform_HH(b, c, d, a, input[10], 23, 0xbebfbc70);
	MD5Transform_HH(a, b, c, d, input[13], 4, 0x289b7ec6);
	MD5Transform_HH(d, a, b, c, input[0], 11, 0xeaa127fa);
	MD5Transform_HH(c, d, a, b, input[3], 16, 0xd4ef3085);
	MD5Transform_HH(b, c, d, a, input[6], 23, 0x04881d05);
	MD5Transform_HH(a, b, c, d, input[9], 4, 0xd9d4d039);
	MD5Transform_HH(d, a, b, c, input[12], 11, 0xe6db99e5);
	MD5Transform_HH(c, d, a, b, input[15], 16, 0x1fa27cf8);
	MD5Transform_HH(b, c, d, a, input[2], 23, 0xc4ac5665);

	MD5Transform_II(a, b, c, d, input[0], 6, 0xf4292244);
	MD5Transform_II(d, a, b, c, input[7], 10, 0x432aff97);
	MD5Transform_II(c, d, a, b, input[14], 15, 0xab9423a7);
	MD5Transform_II(b, c, d, a, input[5], 21, 0xfc93a039);
	MD5Transform_II(a, b, c, d, input[12], 6, 0x655b59c3);
	MD5Transform_II(d, a, b, c, input[3], 10, 0x8f0ccc92);
	MD5Transform_II(c, d, a, b, input[10], 15, 0xffeff47d);
	MD5Transform_II(b, c, d, a, input[1], 21, 0x85845dd1);
	MD5Transform_II(a, b, c, d, input[8], 6, 0x6fa87e4f);
	MD5Transform_II(d, a, b, c, input[15], 10, 0xfe2ce6e0);
	MD5Transform_II(c, d, a, b, input[6], 15, 0xa3014314);
	MD5Transform_II(b, c, d, a, input[13], 21, 0x4e0811a1);
	MD5Transform_II(a, b, c, d, input[4], 6, 0xf7537e82);
	MD5Transform_II(d, a, b, c, input[11], 10, 0xbd3af235);
	MD5Transform_II(c, d, a, b, input[2], 15, 0x2ad7d2bb);
	MD5Transform_II(b, c, d, a, input[9], 21, 0xeb86d391);

	buf[0] += a;
	buf[1] += b;
	buf[2] += c;
	buf[3] += d;
}