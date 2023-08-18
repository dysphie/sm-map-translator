
Action UserMsg_HudMsg(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	// Ignore texts that weren't shown by CGameText::Display, if we can
	if (gameTextDetour && g_ActiveGameText == -1) {
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
	if (msg.ReadString(text, sizeof(text)) <= 0) {
		return Plugin_Continue;
	}

	static char md5[MAX_MD5_LEN];
	Crypt_MD5(text, md5, sizeof(md5));

	if (!MO_TranslationPhraseExists(md5))
	{
		if (gameTextDetour && cvRunTimeLearn.BoolValue) {
			LearnNewText(text);
		}

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