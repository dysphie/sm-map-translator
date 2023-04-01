Action UserMsg_KeyHintText(UserMsg msg, BfRead bf, const int[] players, int playersNum, bool reliable, bool init)
{
	if (hudHintDetour && g_ActiveHudHint == -1) {
		return Plugin_Continue;
	}

	int dunnoByte = bf.ReadByte(); // I dunno..
	
	static char text[MAX_KEYHINT_LEN];
	if (bf.ReadString(text, sizeof(text)) <= 0) {
		return Plugin_Continue;
	}

	static char md5[MAX_MD5_LEN];

	Crypt_MD5(text, md5, sizeof(md5));

	if (!MO_TranslationPhraseExists(md5)) {

		if (hudHintDetour) {
			LearnNewText(text);
		}
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