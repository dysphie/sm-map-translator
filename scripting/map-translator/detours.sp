
int g_ActiveInstructor = -1;
int g_ActivePointText = -1;
int g_ActiveHudHint = -1;
int g_ActiveGameText = -1;

DynamicDetour instructorDetour;
DynamicDetour pointTextDetour;
DynamicDetour gameTextDetour;
DynamicDetour hudHintDetour;

void TryEnableDetours()
{
	GameData gamedata = new GameData("map-translator.games");
	if (!gamedata) 
	{
		LogMessage("Cannot load gamedata/map-translator.games, real-time learning of text entities and optimizations will be disabled.");
		return;
	}

	RegMessageDetour(gamedata, "CGameText::Display", 
		Detour_GameTextDisplayPre, Detour_GameTextDisplayPost, "game_text");

	RegMessageDetour(gamedata, "CEnvHudHint::InputShowHudHint", 
		Detour_HudHintShowPre, Detour_HudHintShowPost, "env_hudhint");

	if (g_Game == GAME_NMRIH)
	{
		RegMessageDetour(gamedata, "CPointMessageMultiplayer::SendMessage", 
			Detour_PointMessageMpPre, Detour_PointMessageMpPost, "point_message_multiplayer");

		RegMessageDetour(gamedata, "CEnvInstructorHint::InputShowHint", 
			Detour_InstructorHintShowPre, Detour_InstructorHintShowPost, "env_instructor_hint");
	}

	delete gamedata;
}

DynamicDetour RegMessageDetour(GameData gd, const char[] fnName, DHookCallback pre, DHookCallback post, const char[] entityName)
{
	DynamicDetour detour;
	detour = DynamicDetour.FromConf(gd, fnName);
	if (!detour) {
		LogMessage("Outdated gamedata for \"%s\". Some '%s' entities might not be translated. ", fnName, entityName);
	} else {
		detour.Enable(Hook_Pre, pre);
		detour.Enable(Hook_Post, post);
	}
	
	return detour;
}

MRESReturn Detour_GameTextDisplayPre(int gametext)
{
	g_ActiveGameText = gametext;
	return MRES_Ignored;
}

MRESReturn Detour_GameTextDisplayPost(int gametext)
{
	g_ActiveGameText = -1;
	return MRES_Ignored;
}

MRESReturn Detour_HudHintShowPre(int envhint)
{
	g_ActiveHudHint = envhint;
	return MRES_Ignored;
}

MRESReturn Detour_HudHintShowPost(int envhint)
{
	g_ActiveHudHint = -1;
	return MRES_Ignored;
}

MRESReturn Detour_PointMessageMpPre(int pointText)
{
	g_ActivePointText = pointText;
	return MRES_Ignored;
}

MRESReturn Detour_PointMessageMpPost(int pointText)
{
	g_ActivePointText = -1;
	return MRES_Ignored;
}

MRESReturn Detour_InstructorHintShowPre(int instructor)
{
	g_ActiveInstructor = instructor;
	return MRES_Ignored;
}

MRESReturn Detour_InstructorHintShowPost(int instructor)
{
	g_ActiveInstructor = -1;
	return MRES_Ignored;
}