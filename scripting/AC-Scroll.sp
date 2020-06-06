#include <sourcemod>
//#include <AC-Helper>
#include <sdktools>
#include <discord>
#include <sourcebanspp>

#pragma newdecls required
#pragma semicolon 1

// discord logging invite - https://discord.gg/N6TyCAC

#define WEBHOOK "https://discordapp.com/api/webhooks/718697989614469160/FTJOSRJ4zvVqyDRovA4PWpd7PfI7MVFPNmp20EN7vgRy1DGSWyrscNvAJrwEuZ1EIarn/slack"

#define SCROLLD1 "Scripted jumps (patt0)" // 100% pos, no matter what sp is
#define SCROLLD2 "Scripted jumps (patt1)" // 95%+ pos, no matter what sp is
#define SCROLLD3 "Scripted jumps (patt2)" // 85%+ pos, no matter what sp is
#define SCROLLD4 "Scripted jumps (patt3)" // 80%+ pos, no matter what sp is
#define SCROLLD5 "Scripted jumps (patt4)" // 75%+ pos, inhumanly consistent sp
#define SCROLLD6 "Scripted jumps (patt5)" // 70%+ pos, obvously random sp
#define SCROLLD7 "Scripted jumps (patt6)" // 40%+ pos, no sp before touching ground
#define SCROLLD8 "Scripted jumps (patt7)" // 40%+ pos, no sp after touching ground
#define SCROLLD9 "Scripted jumps (patt8)" // 50%+ pos, same sp before and after touching ground
#define SCROLLD10 "Scroll macro (patt0)" // sp 15+ (hyper scroll or similar)
#define SCROLLD11 "Scroll cheat (patt1)" // average ground ticks are inhuman

#define SCROLL_SIZE_MIN 35
#define SCROLL_SIZE_MAX 54

// Ammount of ticks between jumps to not count one
#define TICKS_NOT_COUNT_JUMP 8

// Max airtime before we ignore scrolls.
// Stops false detections on surfs and while falling... cough cow cough...
#define TICKS_NOT_COUNT_AIR 102

char g_szLogPath[PLATFORM_MAX_PATH]
	 , g_szBeepSound[PLATFORM_MAX_PATH];

ArrayList g_aJumpStats[MAXPLAYERS+1];

ConVar g_svAutoBhop = null;

int g_iAbsTicks[MAXPLAYERS+1]
	, g_iCurrentStrafe[MAXPLAYERS+1]
	, g_iPerfAngleStreak[MAXPLAYERS+1]
	, g_iPreviousButtons[MAXPLAYERS+1]
	, g_iKeyTransitionTick[MAXPLAYERS+1]
	, g_iAngleTransitionTick[MAXPLAYERS+1]
	, g_iBashTriggerCountdown[MAXPLAYERS+1]
	, g_iSampleSize = 45
	, g_iGroundTicks[MAXPLAYERS+1]
	, g_iReleaseTick[MAXPLAYERS+1]
	, g_iAirTicks[MAXPLAYERS+1]
	, g_iCurrentJump[MAXPLAYERS+1];

bool g_bKeyChanged[MAXPLAYERS+1]
	 , g_bDirectionChanged[MAXPLAYERS+1]
	 , g_bAutoBhop = false
	 , g_bPreviousGround[MAXPLAYERS+1] = {true, ...};

// enums for jummping checks
enum {
	StatsArray_Scrolls,      //Scrolls before the jump
	StatsArray_BeforeGround, // Scrolls before touching ground (33 units above ground)
	StatsArray_AfterGround,  // Scrolls after touching ground (33 units above ground)
	StatsArray_AverageTicks, // Average ticks between each +jump input
	StatsArray_PerfectJump,  // Did they perf?
	STATSARRAY_SIZE
}
enum {
	State_Nothing,
	State_Landing,
	State_Jumping,
	State_Pressing,
	State_Releasing
}

enum {
	T_LOW,
	T_MED,
	T_HIGH,
	T_DEF,
	T_TEST
}

any g_aStatsArray[MAXPLAYERS+1][STATSARRAY_SIZE];

public Plugin myinfo = {
	name = "Guardian-Scroll",
	author = "hiiamu",
	description = "",
	version = "1.8.4",
	url = "/id/hiiamu"
}

public void OnPluginStart() {
	RegAdminCmd("sm_scrolls", Client_PrintScrollStats, ADMFLAG_ROOT);
	RegAdminCmd("sm_bhopcheck", Client_PrintScrollStats, ADMFLAG_ROOT);
	LoadTranslations("common.phrases");

	g_svAutoBhop = FindConVar("sv_autobunnyhopping");
	if(g_svAutoBhop != null)
		g_svAutoBhop.AddChangeHook(OnAutoBhopChanged);

	BuildPath(Path_SM, g_szLogPath, PLATFORM_MAX_PATH, "logs/AC-Scroll.log");

	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i))
			OnClientPutInServer(i);
	}
}

public void OnMapStart() {
	Handle hConfig = LoadGameConfigFile("funcommands.games");
	if(GameConfGetKeyValue(hConfig, "SoundBeep", g_szBeepSound, PLATFORM_MAX_PATH))
		PrecacheSound(g_szBeepSound, true);

	g_iSampleSize = GetRandomInt(SCROLL_SIZE_MIN, SCROLL_SIZE_MAX);
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
	ResetScrollStats(client);

	g_bKeyChanged[client] = false;
	g_bDirectionChanged[client] = false;

	g_aJumpStats[client] = new ArrayList(STATSARRAY_SIZE);
}

public void OnClientDisconnect(int client) {
	delete g_aJumpStats[client];
}

public void OnAutoBhopChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	g_bAutoBhop = view_as<bool>(StringToInt(newValue));
}

public void OnConfigsExecuted() {
	if(g_svAutoBhop != null)
		g_bAutoBhop = g_svAutoBhop.BoolValue;
}

public Action Client_PrintScrollStats(int client, int args) {
	if(args < 1) {
		PrintToChat(client, "\x01[\x0FGuardian\x01] Proper Formatting: sm_bhopcheck <target>");
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
		char[] szScrollStats = new char[256];
		FormatScrolls(iTargetList[i], szScrollStats, 256);
		if(GetScrollSamples(iTargetList[i]) == 0)
			PrintToChat(client, "\x01[\x0FGuardian\x01] \x06%N\x01 does not have any bhop stats.", iTargetList[i]);
		else {
			PrintToChat(client, "\x01[\x0FGuardian\x01] \x06%N\x01's bhop stats have been printed to console.", iTargetList[i]);
			PrintToConsole(client, "==============================================\nUsername: %N\nSteamID: %s\nStats: %s", iTargetList[i], szAuthid, szScrollStats);
		}
	}
/*
	if(target == -1)
		return Plugin_Handled;

	if(GetScrollSamples(target) == 0) {
		PrintToChat(client, "\x01[\x0FGuardian\x01] \x06%N\x01 does not have any bhop stats.", target);
		return Plugin_Handled;
	}
	else {
		PrintToChat(client, "\x01[\x0FGuardian\x01] Information printed to console.");
		PrintToConsole(client, "==============================================\n[Guardian] Bhop Stats for %N: %s\n==============================================", target, szScrollStats);
	}
*/
	return Plugin_Handled;
}

void FormatScrolls(int client, char[] buffer, int maxlength) {
	FormatEx(buffer, maxlength, "Perf Rate: %i%%\n%i Jumps: ", GetPerfs(client), GetScrollSamples(client));

	int iSize = g_aJumpStats[client].Length;
	int iEnd = (iSize >= g_iSampleSize) ? (iSize - g_iSampleSize):0;

	for(int i = iSize - 1; i >= iEnd; i--) {
		//TODO different format for a perf jump rather than no perf
		Format(buffer, maxlength, "%s %i", buffer, g_aJumpStats[client].Get(i, StatsArray_Scrolls));
	}

	int iPos = strlen(buffer) - 1;

	if(buffer[iPos] == ',')
		buffer[iPos] = ' ';

	//(buffer, maxlength, "}");
}

int GetScrollSamples(int client) {
	if(g_aJumpStats[client] == null)
		return 0;

	int iSize = g_aJumpStats[client].Length;
	int iEnd = (iSize >= g_iSampleSize) ? (iSize - g_iSampleSize):0;

	return (iSize - iEnd);
}

int GetPerfs(int client) {
	int iPerfs = 0;
	int iSize = g_aJumpStats[client].Length;
	int iEnd = (iSize >= g_iSampleSize) ? (iSize - g_iSampleSize):0;
	int iJumpCount = (iSize - iEnd);

	for(int i = iSize - 1; i >= iEnd; i--) {
		if(view_as<bool>(g_aJumpStats[client].Get(i, StatsArray_PerfectJump)))
			iPerfs++;
	}

	if(iJumpCount == 0)
		return 0;

	return RoundToZero((float(iPerfs) / iJumpCount) * 100);
}

void ResetScrollStats(int client) {
	for(int i = 0; i < STATSARRAY_SIZE; i++) {
		g_aStatsArray[client][i] = 0;
	}

	g_iReleaseTick[client] = GetGameTickCount();
	g_iAirTicks[client] = 0;
}

public bool TRFilter_NoPlayers(int entity, int mask, any data) {
	return (entity != view_as<int>(data) || (entity < 1 || entity > MaxClients));
}

float GetGroundDistance(int client) {
	if(GetEntPropEnt(client, Prop_Send, "m_hGroundEntity") == 0) {
		return 0.0;
	}

	float fPosition[3];
	GetClientAbsOrigin(client, fPosition);
	TR_TraceRayFilter(fPosition, view_as<float>({90.0, 0.0, 0.0}), MASK_PLAYERSOLID, RayType_Infinite, TRFilter_NoPlayers, client);
	float fGroundPosition[3];

	if(TR_DidHit() && TR_GetEndPosition(fGroundPosition)) {
		return GetVectorDistance(fPosition, fGroundPosition);
	}

	return 0.0;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3]) {
	if(!IsValidClient(client)) // || !IsMoveTypeLeagl(client) || !AC_AllowDetect(client))
		return Plugin_Continue;
	SetupScrollMove(client, buttons);

	return Plugin_Continue;
}

void SetupScrollMove(int client, int buttons) {
	if(g_bAutoBhop)
		return;

	bool bTouchingGround = ((GetEntityFlags(client) & FL_ONGROUND) > 0 || GetEntProp(client, Prop_Send, "m_nWaterLevel") >= 2);

	if(bTouchingGround)
		g_iGroundTicks[client]++;

	float fAbsVelocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fAbsVelocity);

	float fSpeed = (SquareRoot(Pow(fAbsVelocity[0], 2.0) + Pow(fAbsVelocity[1], 2.0)));

	if(fSpeed > 240.0)
		CollectScrollStats(client, bTouchingGround, buttons, fAbsVelocity[2]);

	else
		ResetScrollStats(client);

	g_bPreviousGround[client] = bTouchingGround;
	g_iPreviousButtons[client] = buttons;

	return;
}

int Max(int a, int b) {
	return (a > b) ? a:b;
}

int Min(int a, int b) {
	return (a < b) ? a:b;
}

int Abs(int num) {
	return (num < 0) ? -num:num;
}

void CollectScrollStats(int client, bool bTouchingGround, int buttons, float fAbsVelocityZ) {
	int iGroundState = State_Nothing;
	int iButtonState = State_Nothing;

	if(bTouchingGround && !g_bPreviousGround[client])
		iGroundState = State_Landing;

	else if(!bTouchingGround && g_bPreviousGround[client])
		iGroundState = State_Jumping;

	if((buttons & IN_JUMP) > 0 && (g_iPreviousButtons[client] & IN_JUMP) == 0)
		iButtonState = State_Pressing;

	else if((buttons & IN_JUMP) == 0 && (g_iPreviousButtons[client] & IN_JUMP) > 0)
		iButtonState = State_Releasing;

	int iTicks = GetGameTickCount();

	if(iButtonState == State_Pressing) {
		g_aStatsArray[client][StatsArray_Scrolls]++;
		g_aStatsArray[client][StatsArray_AverageTicks] += (iTicks - g_iReleaseTick[client]);

		if(bTouchingGround) {
			if((buttons & IN_JUMP) > 0)
				g_aStatsArray[client][StatsArray_PerfectJump] = !g_bPreviousGround[client];
		}

		else {
			float fDistance = GetGroundDistance(client);

			if(fDistance < 33.0) {
				if(fAbsVelocityZ > 0.0 && g_iCurrentJump[client] > 1) {
					// updating previous jump with StatsArray_AfterGround data.
					int iJump = (g_iCurrentJump[client] - 1);
					int iAfter = g_aJumpStats[client].Get(iJump, StatsArray_AfterGround);
					g_aJumpStats[client].Set(iJump, iAfter + 1, StatsArray_AfterGround);
				}
				else if(fAbsVelocityZ < 0.0)
					g_aStatsArray[client][StatsArray_BeforeGround]++;
			}
		}
	}

	else if(iButtonState == State_Releasing) {
		g_iReleaseTick[client] = iTicks;
	}

	if(!bTouchingGround && g_iAirTicks[client]++ > TICKS_NOT_COUNT_AIR) {
		ResetScrollStats(client);
		return;
	}

	if(iGroundState == State_Landing) {
		int iScrolls = g_aStatsArray[client][StatsArray_Scrolls];

		if(iScrolls == 0) {
			ResetScrollStats(client);
			return;
		}

		if(g_iGroundTicks[client] < TICKS_NOT_COUNT_JUMP) {
			int iJump = g_iCurrentJump[client];
			g_aJumpStats[client].Resize(iJump + 1);

			g_aJumpStats[client].Set(iJump, iScrolls, StatsArray_Scrolls);
			g_aJumpStats[client].Set(iJump, g_aStatsArray[client][StatsArray_BeforeGround], StatsArray_BeforeGround);
			g_aJumpStats[client].Set(iJump, 0, StatsArray_AfterGround);
			g_aJumpStats[client].Set(iJump, (g_aStatsArray[client][StatsArray_AverageTicks] / iScrolls), StatsArray_AverageTicks);
			g_aJumpStats[client].Set(iJump, g_aStatsArray[client][StatsArray_PerfectJump], StatsArray_PerfectJump);

			g_iCurrentJump[client]++;
		}

		g_iGroundTicks[client] = 0;

		ResetScrollStats(client);
	}
	else if(iGroundState == State_Jumping && g_iCurrentJump[client] >= g_iSampleSize)
		AnalyzeScrollStats(client);
}

void AnalyzeScrollStats(int client) {
	int iPerfs = GetPerfs(client);

	// ints for checking...
	int iHypeScroll = 0;
	int iSameScroll = 0;
	int iSimilarScroll = 0;
	int iBadScrolls = 0;
	int iGoodPre = 0;
	int iGoodPost = 0;
	int iSamePrePost = 0;

	for(int i = (g_iCurrentJump[client] - g_iSampleSize); i < g_iCurrentJump[client] - 1; i++) {
		int iCurrentScrolls = g_aJumpStats[client].Get(i, StatsArray_Scrolls);
		int iTicks = g_aJumpStats[client].Get(i, StatsArray_AverageTicks);
		int iPre = g_aJumpStats[client].Get(i, StatsArray_BeforeGround);
		int iPost = g_aJumpStats[client].Get(i, StatsArray_AfterGround);

		if(i != g_iSampleSize - 1) {
			int iNextScrolls = g_aJumpStats[client].Get(i + 1, StatsArray_Scrolls);

			if(iCurrentScrolls == iNextScrolls)
				iSameScroll++;

			if(Abs(Max(iCurrentScrolls, iNextScrolls) - Min(iCurrentScrolls, iNextScrolls)) <= 2)
				iSimilarScroll++;
		}

		if(iCurrentScrolls >= 24)
			iHypeScroll++;

		if(iTicks <= 2)
			iBadScrolls++;

		if(iPre <= 1)
			iGoodPre++;

		if(iPost == iPre)
			iSamePrePost++;
	}

	float fIntervals = (float(iBadScrolls) / g_iSampleSize);

	bool bDetection = true;

	char[] szScrollStats = new char[300];
	FormatScrolls(client, szScrollStats, 300);

	char szCheatInfo[512];
	Format(szCheatInfo, 512, "Perfs: %i\nBefore Ground: %i\nPost Ground: %i\nSame Pre/Post: %i\n Intervals: %.2f\n Pattern: %s", iPerfs, iGoodPre, iGoodPost, iSamePrePost, fIntervals, szScrollStats);

	//im sorry
	if(iPerfs == 100) {
		AC_Trigger(client, T_DEF);
		NotifyDiscord(client, 0, SCROLLD1);
	}
	else if(iPerfs >= 95) {
		AC_Trigger(client, T_DEF);
		NotifyDiscord(client, 0, SCROLLD2);
	}
	else if(iPerfs >= 85) {
		AC_Trigger(client, T_DEF);
		NotifyDiscord(client, 0, SCROLLD3);
	}
	else if(iPerfs >= 80) {
		AC_Trigger(client, T_DEF);
		NotifyDiscord(client, 0, SCROLLD4);
	}
	else if(iPerfs >= 75 && (iSameScroll >= 10 || iSimilarScroll >= 15)) {
		AC_Trigger(client, T_DEF);
		NotifyDiscord(client, 0, SCROLLD5);
	}
	else if(iPerfs >= 70 && iHypeScroll >= 3 && iSameScroll >= 3 && iSimilarScroll >= 7) {
		AC_Trigger(client, T_DEF);
		NotifyDiscord(client, 0, SCROLLD6);
	}
	else if(iPerfs >= 40 && iGoodPre >= 40) {
		AC_Trigger(client, T_HIGH);
		NotifyDiscord(client, 0, SCROLLD7);
	}
	else if(iPerfs >= 40 && iGoodPost >= 40) {
		AC_Trigger(client, T_HIGH);
		NotifyDiscord(client, 0, SCROLLD8);
	}
	else if(iPerfs >= 50 && iSamePrePost >= 20) {
		AC_Trigger(client, T_HIGH);
		NotifyDiscord(client, 0, SCROLLD9);
	}
	else if(iHypeScroll >= 15) {
		AC_Trigger(client, T_DEF);
		NotifyDiscord(client, 0, SCROLLD10);
	}
	else if(fIntervals > 1.0) {
		AC_Trigger(client, T_MED);
		NotifyDiscord(client, 0, SCROLLD12);
	}
	else
		bDetection = false;

	if(bDetection) {
		ResetScrollStats(client);
		g_iCurrentJump[client] = 0;
		g_aJumpStats[client].Clear();
	}
}

bool IsValidClient(int client) {
	return (0 < client <= MaxClients && IsClientInGame(client));
}

void NotifyDiscord(int client, int reason, char[] szDesc) { //, char[] szCheatInfo
	char szReason[64];
	Format(szReason, sizeof(szReason), "Bhop Detection");

	//char[] szScrollStats = new char[300];
	//FormatScrolls(client, szScrollStats, 300);
	char szBuffer[256];
	FormatEx(szBuffer, 256, "");

	char szPerfs[256];

	int iSize = g_aJumpStats[client].Length;
	int iEnd = (iSize >= g_iSampleSize) ? (iSize - g_iSampleSize):0;

	for(int i = iSize - 1; i >= iEnd; i--) {
		//TODO different format for a perf jump rather than no perf
		Format(szBuffer, 256, "%s %i", szBuffer, g_aJumpStats[client].Get(i, StatsArray_Scrolls));
	}
	int iPos = strlen(szBuffer) - 1;

	if(szBuffer[iPos] == ',')
		szBuffer[iPos] = ' ';

	int iPerfs = GetPerfs(client);
	IntToString(iPerfs, szPerfs, sizeof(szPerfs));
	StrCat(szPerfs, sizeof(szPerfs), "%");

	char szServer[64];
	char szAuthid[32];
	char szIP[32];
	char szName[256];
	GetClientAuthString(client, szAuthid, sizeof(szAuthid));
	GetClientName(client, szName, sizeof(szName));
	GetClientIP(client, szIP, 32);
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
	Embed.AddField("Username:", szName, true);
	Embed.AddField("SteamID:", szAuthid, true);
	Embed.AddField("IP:", szIP, true);
	Embed.AddField("Reason:", szReason, false);
	Embed.AddField("Type:", szDesc, false);
	Embed.AddField("Bhop Stats:", szBuffer, false);
	Embed.AddField("Perfs:", szPerfs, false);
	Embed.AddField("Server:", szServer, false);

	hook.Embed(Embed);

	hook.Send();
	delete hook;
}

void AC_Trigger(int client, int level) { //, char[] szCheatDesc, char[] szCheatInfo
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