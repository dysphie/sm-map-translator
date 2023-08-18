#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <dhooks>

#define DEBUG 1
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

#define PLUGIN_VERSION "1.4.13"

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
int g_Game = GAME_UNKNOWN;

#include "map-translator/ent-lump-parser.sp"
#include "map-translator/detours.sp"
#include "map-translator/md5.sp"

ConVar cvRunTimeLearn;

#include "map-translator/texts/point_message_multiplayer.sp"
#include "map-translator/texts/env_hudhint.sp"
#include "map-translator/texts/game_text.sp"
#include "map-translator/texts/env_instructor_hint.sp"
#include "map-translator/texts/nmrih_objective.sp"
#include "map-translator/texts/zps_objective.sp"

ConVar cvIgnoreNumerical;
ConVar cvTargetLangs;
ConVar cvDefaultLang;

bool g_Lateloaded;

char g_ClientLangCode[MAXPLAYERS+1][MAX_LANGCODE_LEN];

StringMap g_Translations;

void MO_UnloadTranslations()
{
	StringMapSnapshot snap = g_Translations.Snapshot();
	int maxTranslations = snap.Length;

	char md5[MAX_MD5_LEN];
	for (int i = 0; i < maxTranslations; i++)
	{
		snap.GetKey(i, md5, sizeof(md5));

		StringMap langs;
		g_Translations.GetValue(md5, langs);
		delete langs;
	}

	delete snap;
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
	return g_Translations.ContainsKey(md5);
}

bool MO_TranslateForClient(int client, const char[] md5, char[] buffer, int maxlen)
{
	StringMap langs;
	if (!g_Translations.GetValue(md5, langs) || !langs) {
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
	BuildMapTranslationFilePath(mapName, path, sizeof(path));

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
		LearnNMOFile(mapName, g_ExportQueue);
	}

	FlushQueue(path);
}

public void OnClientLanguageChanged(int client, int language)
{
	GetLanguageInfo(language, g_ClientLangCode[client], sizeof(g_ClientLangCode[]));
}

public void OnClientDisconnect(int client)
{
	g_ClientLangCode[client][0] = '\0';
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

	TryEnableDetours(); // Must always be after g_Game is computed

	Parser_OnPluginStart();

	CreateConVar("mt_version", PLUGIN_VERSION, "Map Translator by Dysphie.",
		FCVAR_NOTIFY | FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_REPLICATED);

	RegAdminCmd("mt_forcelang", Command_SetLang, ADMFLAG_ROOT,
		"Forces your perceived language to the given language code");

	if (g_Game == GAME_NMRIH) {
		RegAdminCmd("mt_bulk_learn_nmo", Command_LearnAll, ADMFLAG_ROOT);
	}

	RegAdminCmd("mt_force_export", Command_ForceExport, ADMFLAG_ROOT,
		"Force the plugin to export any learned translations right now");

	RegAdminCmd("mt_debug_clients", Command_DebugClients, ADMFLAG_ROOT,
		"Prints the currently perceived language code for each client");

	cvIgnoreNumerical = CreateConVar("mt_ignore_numerical", "1",
		"Don't translate or learn fully numerical messages such as codes, countdowns, etc.");

	cvTargetLangs = CreateConVar("mt_autolearn_langs", "en",
		"Space-separated list of language entries to include in auto generated translation files");

	cvDefaultLang = CreateConVar("mt_fallback_lang", "en",
		"Clients whose language is not translated will see messages in this language");

	cvRunTimeLearn = CreateConVar("mt_extended_learning", "0",
		"Whether the game will learn text entities that have been modified during gameplay. " ...
		"This can improve detection on maps with VScript, but it can also increase memory usage " ...
		"and the size of the generated translation file"
	);

	if (g_Game == GAME_NMRIH)
	{
		AutoExecConfig(true, "plugin.nmrih-map-translator"); // Bcompat

		HookUserMessage(GetUserMessageId("ObjectiveNotify"), UserMsg_ObjectiveNotifyOrUpdate, true);
		HookUserMessage(GetUserMessageId("ObjectiveUpdate"), UserMsg_ObjectiveNotifyOrUpdate, true);
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

Action Command_SetLang(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: mt_forcelang <language code>");
		return Plugin_Handled;
	}

	char langCode[MAX_LANGCODE_LEN];
	GetCmdArg(1, langCode, sizeof(langCode));

	int langId = GetLanguageByCode(langCode);
	if (langId == -1)
	{
		ReplyToCommand(client, "Invalid language code \"%s\"", langCode);
		return Plugin_Handled;
	}

	char langName[64];
	GetLanguageInfo(langId, g_ClientLangCode[client],
		sizeof(g_ClientLangCode[]), langName, sizeof(langName));

	ReplyToCommand(client, "Set language to %s", langName);
	return Plugin_Handled;
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
	if (!GetCurrentMap(buffer, sizeof(buffer)))
	{
		ReplyToCommand(client, "Can't force export queue flush, not playing a map");
		return Plugin_Handled;
	}

	BuildMapTranslationFilePath(buffer, buffer, sizeof(buffer));
	FlushQueue(buffer);

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

	char buffer[PLATFORM_MAX_PATH];

	maps.GetString(cursor, buffer, sizeof(buffer));

	ArrayStack temp = new ArrayStack(ByteCountToCells(MAX_USERMSG_LEN));
	if (LearnNMOFile(buffer, temp))
	{
		BuildMapTranslationFilePath(buffer, buffer, sizeof(buffer));
		FlushQueue(buffer);
	}
	delete temp;

	data.Reset();
	data.WriteCell(++cursor);
	RequestFrame(LearnMapsFrame, data);
}

Action Command_ReloadTranslations(int client, const char[] command, int argc)
{
	MO_UnloadTranslations();

	char mapName[PLATFORM_MAX_PATH];
	if (GetCurrentMap(mapName, sizeof(mapName)))
	{
		char path[PLATFORM_MAX_PATH];
		BuildPath(Path_SM, path, sizeof(path), "translations/_maps/%s.txt", mapName);
		MO_LoadTranslations(path);
	}

	ReplyToCommand(client, PREFIX ... "Reloaded translations");
	return Plugin_Continue;
}

public void OnMapEnd()
{
	char buffer[PLATFORM_MAX_PATH];
	GetCurrentMap(buffer, sizeof(buffer));
	BuildMapTranslationFilePath(buffer, buffer, sizeof(buffer));
	FlushQueue(buffer);
	MO_UnloadTranslations();
}

void BuildMapTranslationFilePath(const char[] mapName, char[] path, int maxlen)
{
	BuildPath(Path_SM, path, maxlen, "translations/_maps/%s.txt", mapName);
}

bool IsNumericalString(const char[] str)
{
	int value;
	return StringToIntEx(str, value) == strlen(str);
}

void FlushQueue(const char[] path)
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

	int numLangs = 0;

	while (!g_ExportQueue.Empty)
	{
		g_ExportQueue.PopString(buffer, sizeof(buffer));

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
				kv.GoBack();
			}
			else
			{
				kv.SetString(langCodes[i], buffer);
			}

			numLangs++;
		}

		count++;
		kv.GoBack();
	}

	if (numLangs == 0 && count > 0)
	{
		LogMessage("Found %d texts to translate but mt_autolearn_langs contains no valid language codes", count, numLangs);
	}
	else
	{
		kv.Rewind();
		kv.ExportToFile(path);
	}

	g_ExportQueue.Clear();
	delete kv;
}

void SeekFileTillChar(File file, char c)
{
	int i;
	do {
		if (!file.ReadInt8(i))
		{
			LogError("ReadInt8 failed at position %d", file.Position);
			break;
		}
	}
	while (i != c);
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

void LearnNewText(const char[] text)
{
	#if DEBUG
		PrintToServer("LearnNewText: \"%s\"", text);
	#endif

	char md5[MAX_MD5_LEN];
	Crypt_MD5(text, md5, sizeof(md5));

	g_Translations.SetValue(md5, INVALID_HANDLE);
	g_ExportQueue.PushString(text);
}