#define MAX_HUDNOTIFY_LEN 255	 // TODO: shorten

Action UserMsg_HudNotifyCustom(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	// Ignore texts that weren't shown by CTFHudNotify::Display, if we can
	if (gameTextTfDetour && g_ActiveGameTextTf == -1)
	{
		return Plugin_Continue;
	}

	char text[MAX_HUDNOTIFY_LEN];
	if (msg.ReadString(text, sizeof(text)) <= 0)
	{
		return Plugin_Continue;
	}

	char md5[MAX_MD5_LEN];
	Crypt_MD5(text, md5, sizeof(md5));

	if (!MO_TranslationPhraseExists(md5))
	{
		if (gameTextTfDetour && cvRunTimeLearn.BoolValue)
		{
			LearnNewText(text);
		}

		return Plugin_Continue;
	}

	char icon[255];
	msg.ReadString(icon, sizeof(icon));

	int			team	 = msg.ReadByte();

	DataPack	data = new DataPack();

	data.WriteString(text);
	data.WriteString(md5);
	data.WriteString(icon);
	data.WriteCell(team);

	data.WriteCell(playersNum);
	for (int i; i < playersNum; i++)
		data.WriteCell(GetClientSerial(players[i]));

	RequestFrame(Translate_HudNotifyCustom, data);
	return Plugin_Handled;
}

void Translate_HudNotifyCustom(DataPack data)
{
	data.Reset();

	char  original[MAX_HUDNOTIFY_LEN];
	data.ReadString(original, sizeof(original));

	char md5[MAX_MD5_LEN];
	data.ReadString(md5, sizeof(md5));

	char icon[255];
	data.ReadString(icon, sizeof(icon));

	int	  team	   = data.ReadCell();
	int playersNum = data.ReadCell();

	int[] userids  = new int[playersNum];
	for (int i; i < playersNum; i++)
	{
		userids[i] = data.ReadCell();
	}

	delete data;

	char translated[MAX_HUDNOTIFY_LEN];

	for (int i; i < playersNum; i++)
	{
		int client = GetClientFromSerial(userids[i]);
		if (!client)
			continue;

		bool	didTranslate = MO_TranslateForClient(client, md5, translated, sizeof(translated));

		Handle	msg			 = StartMessageOne("HudNotifyCustom", client, USERMSG_BLOCKHOOKS);
		BfWrite bf			 = UserMessageToBfWrite(msg);

		bf.WriteString(didTranslate ? translated : original);
		bf.WriteString(icon);
		bf.WriteByte(team);
		EndMessage();
	}
}