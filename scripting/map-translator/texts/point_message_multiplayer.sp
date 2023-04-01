
Action UserMsg_PointMessageMultiplayer(UserMsg msg, BfRead bf, const int[] players, int playersNum, bool reliable, bool init)
{
	// If we are detouring CPointMessageMultiplayer::SendMessage and it's not in scope
	// we can bail early and avoid computing the MD5 hash altogether
	if (pointTextDetour && g_ActivePointText == -1) {
		return Plugin_Continue;
	}

	static char text[MAX_POINTTEXTMP_LEN];
	if (bf.ReadString(text, sizeof(text)) <= 0) {
		return Plugin_Continue;
	}

	static char md5[MAX_MD5_LEN];
	Crypt_MD5(text, md5, sizeof(md5));

	if (!MO_TranslationPhraseExists(md5)) {

		// Only learn this if we are in CPointMessageMultiplayer::SendMessage
		// Ignore other plugin messages
		if (pointTextDetour) {
			LearnNewText(text);
		}

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
