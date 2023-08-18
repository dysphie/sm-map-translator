


Action Event_InstructorHintCreate(Event event, const char[] name, bool dontBroadcast)
{
	// Ignore texts that weren't shown by CEnvInstructorHint::InputShowHint, if we can
	if (instructorDetour && g_ActiveInstructor == -1) {
		return Plugin_Continue;
	}

	// Instructor has 2 texts, one specific to the !activator
	// and one to everyone else.

	char baseText[MAX_USERMSG_LEN];
	event.GetString("hint_caption", baseText, sizeof(baseText));
	char baseMd5[MAX_MD5_LEN];
	Crypt_MD5(baseText, baseMd5, sizeof(baseMd5));

	bool doRuntimeLearning = cvRunTimeLearn.BoolValue;

	bool missingBaseHint = false;
	if (!MO_TranslationPhraseExists(baseMd5))
	{
		if (instructorDetour && doRuntimeLearning) {
			LearnNewText(baseText);
		}

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
		if (instructorDetour && doRuntimeLearning) {
			LearnNewText(activatorText);
		}

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
	return Plugin_Continue;
}
