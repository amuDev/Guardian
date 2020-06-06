#include <sourcemod>
//#include <AC-Helper>
#include <sdktools>
#include <discord>
#include <sourcebanspp>

#pragma newdecls required
#pragma semicolon 1

// discord logging invite - https://discord.gg/N6TyCAC

#define WEBHOOK "https://discordapp.com/api/webhooks/718697989614469160/FTJOSRJ4zvVqyDRovA4PWpd7PfI7MVFPNmp20EN7vgRy1DGSWyrscNvAJrwEuZ1EIarn/slack"

#define STRAFED1 "Strafes Too Perfect"
#define STRAFED2 "Tick Difference Too Low"
#define STRAFED3 "Perfect Turn Rate"
#define STRAFED4 "Average Strafe Too Low"

#define STRAFE_SIZE 50

char g_szLogPath[PLATFORM_MAX_PATH]
	 , g_szBeepSound[PLATFORM_MAX_PATH];

ArrayList g_aStrafeHistory[MAXPLAYERS+1];

int g_iAbsTicks[MAXPLAYERS+1]
	, g_iCurrentStrafe[MAXPLAYERS+1]
	, g_iPerfAngleStreak[MAXPLAYERS+1]
	, g_iPreviousButtons[MAXPLAYERS+1]
	, g_iKeyTransitionTick[MAXPLAYERS+1]
	, g_iAngleTransitionTick[MAXPLAYERS+1]
	, g_iBashTriggerCountdown[MAXPLAYERS+1]
	, g_iCurrentJump[MAXPLAYERS+1];

float g_fPreviousAngle[MAXPLAYERS+1]
		, g_fPreviousDeltaAngle[MAXPLAYERS+1]
		, g_fPreviousDeltaAngleAbs[MAXPLAYERS+1]
		, g_fPreviousOptimizedAngle[MAXPLAYERS+1];

bool g_bKeyChanged[MAXPLAYERS+1]
	 , g_bLeftThisJump[MAXPLAYERS+1]
	 , g_bRightThisJump[MAXPLAYERS+1]
	 , g_bDirectionChanged[MAXPLAYERS+1];

enum {
	T_LOW,
	T_MED,
	T_HIGH,
	T_DEF,
	T_TEST
}

public Plugin myinfo = {
	name = "Guardian-Strafe",
	author = "hiiamu",
	description = "",
	version = "2.1.6",
	url = "/id/hiiamu"
}

public void OnPluginStart() {
	RegAdminCmd("sm_strafes", Client_PrintStrafeStats, ADMFLAG_ROOT);
	LoadTranslations("common.phrases");

	BuildPath(Path_SM, g_szLogPath, PLATFORM_MAX_PATH, "logs/AC-Strafe.log");

	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i))
			OnClientPutInServer(i);
	}
}

public void OnMapStart() {
	Handle hConfig = LoadGameConfigFile("funcommands.games");
	if(GameConfGetKeyValue(hConfig, "SoundBeep", g_szBeepSound, PLATFORM_MAX_PATH))
		PrecacheSound(g_szBeepSound, true);
}

public void OnClientPutInServer(int client) {
	g_iAbsTicks[client] = 0;
	g_iCurrentStrafe[client] = 0;
	g_iPerfAngleStreak[client] = 0;
	g_iPreviousButtons[client] = 0;
	g_iKeyTransitionTick[client] = 0;
	g_iAngleTransitionTick[client] = 0;
	g_iBashTriggerCountdown[client] = 0;

	g_iCurrentJump[client] = 0;

	g_bKeyChanged[client] = false;
	g_bDirectionChanged[client] = false;

	g_aStrafeHistory[client] = new ArrayList();
}

public void OnClientDisconnect(int client) {
	delete g_aStrafeHistory[client];
}

int GetStrafeSamples(int client) {
	if(g_aStrafeHistory[client] == null)
		return 0;

	int iSize = g_aStrafeHistory[client].Length;
	int iEnd = (iSize >= STRAFE_SIZE) ? (iSize - STRAFE_SIZE):0;

	return (iSize - iEnd);
}

public Action Client_PrintStrafeStats(int client, int args) {
	if(args < 1) {
		ReplyToCommand(client, "Proper Formatting: sm_strafes <target>");
		return Plugin_Handled;
	}

	char[] szArgs = new char[MAX_TARGET_LENGTH];
	GetCmdArgString(szArgs, MAX_TARGET_LENGTH);

	char[] szAuthid = new char[32];
	GetClientAuthString(client, szAuthid, 32);

	char szArg[128];
	GetCmdArg(1, szArg, sizeof(szArg));

	char szTarget[MAX_TARGET_LENGTH];
	int iTargetList[MAXPLAYERS], target_count;
	bool tn_is_ml;

	if ((target_count = ProcessTargetString(
		szArg,
		client,
		iTargetList,
		MAXPLAYERS,
		COMMAND_FILTER_ALIVE,
		szTarget,
		sizeof(szTarget),
		tn_is_ml)) <= 0) {
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}

	for(int i = 0; i < target_count; i++) {
		char[] szStrafeStats = new char[256];
		FormatStrafes(iTargetList[i], szStrafeStats, 256);
		if(GetStrafeSamples(iTargetList[i]) == 0)
			PrintToChat(client, "\x01[\x0FGuardian\x01] \x06%N\x01 does not have any strafe stats.", iTargetList[i]);
		else {
			PrintToChat(client, "\x01[\x0FGuardian\x01] \x06%N\x01's strafe stats have been printed to console.", iTargetList[i]);
			PrintToConsole(client, "==============================================\nUsername: %N\nSteamID: %s\nStats: %s", iTargetList[i], szAuthid, szStrafeStats);
		}
	}
/*
	if(target == -1)
		return Plugin_Handled;

	if(GetStrafeSamples(target) == 0) {
		PrintToChat(client, "\x01[\x0FGuardian\x01] \x06%N\x01 does not have any strafe stats.", target);
		return Plugin_Handled;
	}
	else {
		PrintToChat(client, "\x01[\x0FGuardian\x01] Information printed to console.");
		PrintToConsole(client, "\n \n==============================================\nUsername: %N\nSteamID: %s\nStats: %s\n==============================================\n \n", target, szAuthid, szStrafeStats);
	}
*/
	return Plugin_Handled;
}

void FormatStrafes(int client, char[] buffer, int maxlength) {
	FormatEx(buffer, maxlength, "", GetStrafeSamples(client));

	int iSize = g_aStrafeHistory[client].Length;
	int iEnd = (iSize >= STRAFE_SIZE) ? (iSize - STRAFE_SIZE):0;

	for(int i = iSize - 1; i >= iEnd; i--)
		Format(buffer, maxlength, "%s %d,", buffer, g_aStrafeHistory[client].Get(i));

	int iPos = strlen(buffer) - 1;

	if(StrEqual(buffer[iPos], ",", false)) //
		buffer[iPos] = ' ';

	//StrCat(buffer, maxlength, "}");
}

public bool TRFilter_NoPlayers(int entity, int mask, any data) {
	return (entity != view_as<int>(data) || (entity < 1 || entity > MaxClients));
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3]) {
	if(!IsValidClient(client)) // || !IsMoveTypeLeagl(client) || !AC_AllowDetect(client))
		return Plugin_Continue;
	SetupStrafeMove(client, buttons, angles, vel);

	return Plugin_Continue;
}

void SetupStrafeMove(int client, int &buttons, float angles[3], float vel[3]) {
	float fDeltaAngle = angles[1] - g_fPreviousAngle[client];
	g_fPreviousAngle[client] = angles[1];

	g_iAbsTicks[client]++;

	if(fDeltaAngle > 180.0)
		fDeltaAngle -= 360.0;

	else if(fDeltaAngle < -180.0)
		fDeltaAngle += 360.0;

	float fDeltaAngleAbs = FloatAbs(fDeltaAngle);

	if(fDeltaAngleAbs < 0.015625)
		return;

	int iFlags = GetEntityFlags(client);

	// Are they in air?
	if((iFlags & (FL_ONGROUND | FL_INWATER)) == 0) {
		if((buttons & (IN_MOVELEFT | IN_MOVERIGHT)) != (IN_MOVELEFT | IN_MOVERIGHT) &&
			 (buttons & (IN_FORWARD | IN_BACK)) != (IN_FORWARD | IN_BACK)) {
			// True sync calculations...
			// not that KZTimer %sync shit
			if(
					// Buttons switch from A to D
					// Or D to A
					((((buttons & IN_MOVELEFT) > 0 && (g_iPreviousButtons[client] & IN_MOVELEFT) == 0) ||
					((buttons & IN_MOVERIGHT) > 0 && (g_iPreviousButtons[client] & IN_MOVERIGHT) == 0)) ||
					((g_iPreviousButtons[client] & IN_MOVERIGHT) > 0 && (g_iPreviousButtons[client] & IN_MOVELEFT) > 0)) ||

					// Buttons switch from W to S
					// Or S to W
					((((buttons & IN_FORWARD) > 0 && (g_iPreviousButtons[client] & IN_FORWARD) == 0) ||
					((buttons & IN_BACK) > 0 && (g_iPreviousButtons[client] & IN_BACK) == 0)) ||
					((g_iPreviousButtons[client] & IN_BACK) > 0 && (g_iPreviousButtons[client] & IN_FORWARD) > 0))) {
				// sorry for that...
				g_bKeyChanged[client] = true;
				g_iKeyTransitionTick[client] = g_iAbsTicks[client];
			}
		}

		if(!g_bDirectionChanged[client] &&
				(fDeltaAngleAbs != 0.0 &&
				((fDeltaAngle < 0.0 && g_fPreviousDeltaAngle[client] > 0.0) ||
				(fDeltaAngle > 0.0 && g_fPreviousDeltaAngle[client] < 0.0) ||
				g_fPreviousDeltaAngleAbs[client] == 0.0))) {
			// i dont like maths in sp

			//g_bDirectionChanged means mouse changed....
			g_bDirectionChanged[client] = true;
			g_iAngleTransitionTick[client] = g_iAbsTicks[client];
		}

		// if client switches key and mouse movement...
		if(g_bKeyChanged[client] && g_bDirectionChanged[client]) {
			//reset bools
			g_bKeyChanged[client] = false;
			g_bDirectionChanged[client] = false;

			int iTick = g_iKeyTransitionTick[client] - g_iAngleTransitionTick[client];

			// Only update array if they are actually syncing their
			// keys and mouse movement
			if(-25 <= iTick <= 25) {
				g_aStrafeHistory[client].Push(iTick);
				g_iCurrentStrafe[client]++;

				if((g_iCurrentStrafe[client] % STRAFE_SIZE) == 0)
					AnalyzeStrafeStats(client);
			}

			if(g_iBashTriggerCountdown[client] > 0)
				g_iBashTriggerCountdown[client]--;
		}

		if((buttons & IN_LEFT) > 0)
			g_bLeftThisJump[client] = true;

		if((buttons & IN_RIGHT) > 0)
			g_bRightThisJump[client] = true;

		if(g_bLeftThisJump[client] && g_bRightThisJump[client]) {
			vel[0] = 0.0;
			vel[1] = 0.0;
		}
	}
	else {
		g_bKeyChanged[client] = false;
		g_bDirectionChanged[client] = false;

		g_bLeftThisJump[client] = false;
		g_bRightThisJump[client] = false;
	}

	float fAbsVelocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fAbsVelocity);

	float fSpeed = (SquareRoot(Pow(fAbsVelocity[0], 2.0) + Pow(fAbsVelocity[1], 2.0)));

	// i think i did maths wrong here?
	//TODO
	if((FloatAbs(fDeltaAngleAbs - g_fPreviousOptimizedAngle[client]) <= (g_fPreviousOptimizedAngle[client] / 128.0) && fSpeed < 2560.0)) {
		char[] szStrafeStats = new char[256];
		FormatStrafes(client, szStrafeStats, 256);
		char szBuffer[256];
		Format(szBuffer, 256, "Perf angles: %i", g_iPerfAngleStreak[client]);
		StrCat(szStrafeStats, 256, szBuffer);

		if(++g_iPerfAngleStreak[client] == 10) {
			AC_Trigger(client, T_LOW);
			NotifyDiscord(client, 0, STRAFED3);
		}
		else if(g_iPerfAngleStreak[client] == 30) {
			AC_Trigger(client, T_MED);
			NotifyDiscord(client, 1, STRAFED3);
		}
		else if(g_iPerfAngleStreak[client] == 40) {
			AC_Trigger(client, T_HIGH);
			NotifyDiscord(client, 2, STRAFED3);
		}
		else if(g_iPerfAngleStreak[client] == 50) {
			AC_Trigger(client, T_DEF);
			NotifyDiscord(client, 3, STRAFED3);
		}
	}
	else
		g_iPerfAngleStreak[client] = 0;

	g_iPreviousButtons[client] = buttons;
	g_fPreviousOptimizedAngle[client] = ArcSine(30.0 / fSpeed) * 57.29577951308;
	g_fPreviousDeltaAngleAbs[client] = fDeltaAngleAbs;
	g_fPreviousDeltaAngle[client] = fDeltaAngle;

	return;
}

int Abs(int num) {
	return (num < 0) ? -num:num;
}

void AnalyzeStrafeStats(int client) {
	int iTickDifference = 0;
	int iZeroes = 0;
	int iStrafeCount = 0;
	int iBadTicks = 0;
	float fAvgTick = 0.0;

	for(int i = (g_iCurrentStrafe[client] - STRAFE_SIZE); i < g_iCurrentStrafe[client] - 1; i++) {
		int iTick = Abs(g_aStrafeHistory[client].Get(i));

		// all nums add up to under X
		iTickDifference += iTick;

		// average tick diff over sample size
		iStrafeCount++;
		iBadTicks = (iBadTicks + iTick);

		if(iTick == 0)
			iZeroes++;
	}

	fAvgTick = (float(iBadTicks) / float(iStrafeCount));

	char[] szStrafeStats = new char[256];
	FormatStrafes(client, szStrafeStats, 256);
	char szInfo[256];
	Format(szInfo, 256, "Avg Tick: %.2f", fAvgTick);
	StrCat(szStrafeStats, 256, szInfo);

	if(fAvgTick < 0.10) {
		AC_Trigger(client, T_DEF);
		NotifyDiscord(client, 3, STRAFED4);
		g_iBashTriggerCountdown[client] = 35;
	}
	else if(fAvgTick < 0.5) {
		AC_Trigger(client, T_HIGH);
		NotifyDiscord(client, 2, STRAFED4);
		g_iBashTriggerCountdown[client] = 35;
	}
	else if(fAvgTick < 1.0) {
		AC_Trigger(client, T_MED);
		NotifyDiscord(client, 1, STRAFED4);
		g_iBashTriggerCountdown[client] = 35;
	}

	Format(szInfo, 256, "Tick Difference: %i", iTickDifference);
	StrCat(szStrafeStats, 256, szInfo);

	if(iTickDifference < 3) {
		AC_Trigger(client, T_DEF);
		NotifyDiscord(client, 3, STRAFED2);
		g_iBashTriggerCountdown[client] = 35;
	}
	else if(iTickDifference < 6) {
		AC_Trigger(client, T_HIGH);
		NotifyDiscord(client, 2, STRAFED2);
		g_iBashTriggerCountdown[client] = 35;
	}
	else if(iTickDifference < 9) {
		AC_Trigger(client, T_MED);
		NotifyDiscord(client, 1, STRAFED2);
		g_iBashTriggerCountdown[client] = 35;
	}
	else if(iTickDifference < 15) {
		AC_Trigger(client, T_LOW);
		NotifyDiscord(client, 0, STRAFED2);
		g_iBashTriggerCountdown[client] = 35;
	}

	if(iZeroes > 35) {
		AC_Trigger(client, T_DEF);
		g_iBashTriggerCountdown[client] = 35;
	}

	else if(iZeroes > 32) {
		AC_Trigger(client, T_HIGH);
		NotifyDiscord(client, 2, STRAFED1);
		g_iBashTriggerCountdown[client] = 35;
	}

	else if(iZeroes > 28) {
		AC_Trigger(client, T_MED);
		NotifyDiscord(client, 1, STRAFED1);
		g_iBashTriggerCountdown[client] = 35;
	}

	else if(iZeroes > 25) {
		AC_Trigger(client, T_LOW);
		NotifyDiscord(client, 0, STRAFED1);
		g_iBashTriggerCountdown[client] = 35;
	}
}

bool IsValidClient(int client) {
	return (0 < client <= MaxClients && IsClientInGame(client));
}

void NotifyDiscord(int client, int reason, char[] szDesc) {
	char szReason[64];
	Format(szReason, sizeof(szReason), "Strafe Detection");

	char[] szStrafeStats = new char[300];
	FormatStrafes(client, szStrafeStats, 300);
	
	char szServer[64];
	char szAuthid[32];
	char szName[256];
	GetClientAuthString(client, szAuthid, sizeof(szAuthid));
	GetClientName(client, szName, sizeof(szName));
	Handle hHostName = FindConVar("hostname");
	GetConVarString(hHostName, szServer, sizeof(szServer));
	
	DiscordWebHook hook = new DiscordWebHook(WEBHOOK);
	hook.SlackMode = true;

	hook.SetUsername("[Guardian]");

	MessageEmbed Embed = new MessageEmbed();

	if(reason == 0) {
		Embed.SetTitle("LOW:");
		Embed.SetColor("#f5bc42");
	}
	else if(reason == 1) {
		Embed.SetTitle("MED:");
		Embed.SetColor("#f5bc42");
	}
	else if(reason == 2) {
		Embed.SetTitle("HIGH:");
		Embed.SetColor("#fcb14e");
	}
	else {
		Embed.SetTitle("DEF:");
		Embed.SetColor("#fcb14e");
	}

	//Embed.SetColor("#ff0000");
	//Embed.SetTitle("New ban:");
	Embed.AddField("Username:", szName, true);
	Embed.AddField("SteamID:", szAuthid, true);
	Embed.AddField("Reason:", szReason, false);
	Embed.AddField("Type:", szDesc, false);
	Embed.AddField("Strafe Stats:", szStrafeStats, false);
	Embed.AddField("Server:", szServer, false);

	hook.Embed(Embed);

	hook.Send();
	delete hook;
}

void AC_Trigger(int client, int level) { //, char[] szCheatDesc
	char[] szLevel = new char[16];

	if(level == T_LOW) {
		strcopy(szLevel, 16, "LOW");
	} else if(level == T_MED) {
		strcopy(szLevel, 16, "MED");
	} else if(level == T_HIGH) {
		strcopy(szLevel, 16, "HIGH");
		SBPP_BanPlayer(0, client, 0, "[Guardian] Unfair Advantage");
	} else if(level == T_DEF) {
		strcopy(szLevel, 16, "DEF");
		SBPP_BanPlayer(0, client, 0, "[Guardian] Unfair Advantage");
	}

	char[] szAuthid = new char[32];
	GetClientAuthString(client, szAuthid, 32);
	
	char[] szIP = new char[32];
	GetClientIP(client, szIP, 32);

	AC_NotifyAdmins(client);
	return;
}

void AC_NotifyAdmins(int client) {
	for(int i = 1; i <= MaxClients; i++) {
		if(CheckCommandAccess(i, "admin", ADMFLAG_GENERIC)) {
			PrintToChat(i, "\01[\x0FGuardian\01] \x06%N\x01 has been detected.", client);
			ClientCommand(i, "play */%s", g_szBeepSound);
		}
	}
}