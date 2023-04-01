Action UserMsg_ObjectiveNotifyOrUpdate(UserMsg msg, BfRead bf, const int[] players, int playersNum, bool reliable, bool init)
{
	char msgName[17];
	GetUserMessageName(msg, msgName, sizeof(msgName));

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
	data.WriteString(msgName);

	for(int i; i < playersNum; i++)
		data.WriteCell(GetClientSerial(players[i]));

	RequestFrame(TranslateObjectiveShared, data);
	return Plugin_Handled;
}

void TranslateObjectiveShared(DataPack data)
{
	data.Reset();

	char original[MAX_OBJNOTIFY_LEN];
	data.ReadString(original, sizeof(original));

	char md5[MAX_MD5_LEN];
	data.ReadString(md5, sizeof(md5));

	int playersNum = data.ReadCell();

	char msgName[32];
	data.ReadString(msgName, sizeof(msgName));

	for (int i; i < playersNum; i++)
	{
		int client = GetClientFromSerial(data.ReadCell());
		if(!client)
			continue;

		char translated[PLATFORM_MAX_PATH];
		bool didTranslate = MO_TranslateForClient(client, md5, translated, sizeof(translated));

		Handle msg = StartMessageOne(msgName, client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);
		BfWrite bf = UserMessageToBfWrite(msg);
		bf.WriteString(didTranslate ? translated : original);
		EndMessage();
	}

	delete data;
} 


int LearnNMOFile(const char[] mapName, ArrayStack stack)
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