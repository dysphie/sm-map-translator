Action UserMsg_ObjectiveState(UserMsg msg, BfRead bf, const int[] players, int playersNum, bool reliable, bool init)
{
	int dunnoByte = bf.ReadByte(); // I dunno..
	
	static char text[MAX_KEYHINT_LEN];
	if (bf.ReadString(text, sizeof(text)) <= 0) {
		return Plugin_Continue;
	}

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