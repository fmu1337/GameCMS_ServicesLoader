
#include <sourcemod>

#define MAXSERVICES 32 // must to switch into ADT Array later

#define DB_PASS		0
#define USER_PASS	1

#define LOGSERVICES	1
#define LOGRIGHTS	2
#define LOGCONNECTS	4
#define LOGDB		8
#define LOGPW		16

static const String: sLog[] = "addons/sourcemod/logs/gamecms_admin_loader.log";
new 		g_iLoggin;

new Handle:	hDatabase;

new 		g_iServiceId[MAXSERVICES];
new String:	g_iServiceName[MAXSERVICES][64];
new 		g_iServiceFlags[MAXSERVICES];
new 		g_iServiceImmunity[MAXSERVICES];
new			g_iLoadedServices;

new			g_iServerId	= -1;
new String:	g_sInfoVar[32] = "_pw", Handle: hCvarForceId;


public Plugin:myinfo = 
{
	name = "GameCMS Admin Loader",
	author = "Danyas",
	description = "Loading admins and services from GameCMS database",
	version = "1.6.b31",
	url = "https://vk.com/id36639907"
}

public OnPluginStart()
{
	if (!SQL_CheckConfig("gamecms")) 
	{ 
		SetFailState("Секция \"gamecms\" не найдена в databases.cfg");
	}
	
	new Handle: hCvarLog = CreateConVar(
		"sm_gamecms_loader_logs",
		"31", "1 - LOG SERVICES / 2 - LOG RIGHTS / 4 - CONNECTS / 8 - LOG DB QUERIES / 16 - LOG PASSCHECKS (LOG SERVICES + LOG RIGHTS = 3)"
		, _, true, 0.0, true, 31.0);
		
	hCvarForceId = CreateConVar("sm_gamecms_loader_force_serverid", "-1", "Manual choose ServerId, -1 for autodetect", _, true, -1.0);
	
	HookConVarChange(hCvarLog, UpdateCvar_log);
	
	AutoExecConfig(true, "gamecms_loader");
	
	g_iLoggin = GetConVarInt(hCvarLog);
	
	SQL_TConnect(SQL_LoadServer, "gamecms");
}


public SQL_LoadServer(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)  
	{
		SetFailState("Database failure: %s", error);
		return;
	}

	hDatabase = hndl;
	decl String:query[192]; query[0] = '\0';
	
	new iVar = GetConVarInt(hCvarForceId);
	if(iVar == -1)
	{
		new longip = GetConVarInt(FindConVar("hostip"));
		
		FormatEx(query, sizeof(query),
			"SELECT `pass_prifix`,`id` FROM `servers` WHERE `ip` = '%d.%d.%d.%d' AND `port` = '%i'",
				(longip >> 24) & 0x000000FF, (longip >> 16) & 0x000000FF, (longip >> 8) & 0x000000FF, longip & 0x000000FF, GetConVarInt(FindConVar("hostport")));
				
		if(g_iLoggin & LOGDB) LogToFileEx(sLog, "SQL_LoadServer: \"%s\"", query);
	}
	else
	{
		FormatEx(query, sizeof(query), "SELECT `pass_prifix` FROM `servers` WHERE `id` = '%i'", g_iServerId = iVar);
		if(g_iLoggin & LOGDB) LogToFileEx(sLog, "SQL_LoadServer: \"%s\"", query);
	}
	
	SQL_TQuery(hDatabase, SQL_CheckServer, query);
}


public SQL_CheckServer(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE) LogError("SQL_CheckServer Query falied. (error:  %s)", error);

	if (SQL_HasResultSet(hndl) && SQL_FetchRow(hndl))
	{
		SQL_FetchString(hndl, 0, g_sInfoVar, sizeof(g_sInfoVar));
		if(g_iServerId == -1) g_iServerId = SQL_FetchInt(hndl, 1);
		
		if(g_iLoggin & LOGDB) LogToFileEx(sLog, "SQL_LoadServer Result: [SERVER ID: %i] [PASS INFO VAR: \"%s\"]", g_iServerId, g_sInfoVar);
		
		
		decl String:query[96]; query[0] = '\0';
		FormatEx(query, sizeof(query), "SELECT `id`, `name`, `rights`, `immunity` FROM `services` WHERE `server` = '%i'", g_iServerId);
		
		if(g_iLoggin & LOGDB) LogToFileEx(sLog, "SQL_GetServices: \"%s\"", query);
		SQL_TQuery(hDatabase, SQL_GetServices, query);
	}
	
	else
	{
		if(g_iServerId == -1)
		{
			new longip = GetConVarInt(FindConVar("hostip"));
			SetFailState("Сервер \"%d.%d.%d.%d:%i\" не найден базе сайта", (longip >> 24) & 0x000000FF, (longip >> 16) & 0x000000FF, (longip >> 8) & 0x000000FF, longip & 0x000000FF, GetConVarInt(FindConVar("hostport")));
		}
		else
		{
			SetFailState("Указан неверный \"sm_gamecms_loader_force_serverid\"");
		}
	}
}

public SQL_GetServices(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE) LogError("SQL_GetServices Query falied. (error:  %s)", error);

	if (SQL_HasResultSet(hndl))
	{
		g_iLoadedServices = 0;
		if(g_iLoggin & LOGSERVICES)  LogToFileEx(sLog, "|#    |        Флаги          | Иммунитет | Название услуги");
		while (SQL_FetchRow(hndl))
		{
			decl String:buff[AdminFlags_TOTAL + 1];
			
			g_iServiceId[g_iLoadedServices] = SQL_FetchInt(hndl, 0);
			SQL_FetchString(hndl, 1, g_iServiceName[g_iLoadedServices], sizeof(g_iServiceName[]));
			SQL_FetchString(hndl, 2, buff, sizeof(buff));
			
			
			new len = strlen(buff);
			new AdminFlag:flag;
			
			for (new i = 0; i < len; i++)
			{
				if (!FindFlagByChar(buff[i], flag))
				{
					LogToFileEx(sLog, "Найден неверный флаг: %c", buff[i]);
				}
				else
				{
					g_iServiceFlags[g_iLoadedServices] |= FlagToBit(flag);
				}
			}
			
			g_iServiceImmunity[g_iLoadedServices] = SQL_FetchInt(hndl, 3);
			
			if(g_iLoggin & LOGSERVICES)
				LogToFileEx(sLog, "|#%4d| %21s | %9i | %s",
					g_iLoadedServices + 1, buff, g_iServiceImmunity[g_iLoadedServices], g_iServiceName[g_iLoadedServices]);
			
			g_iLoadedServices++;
		}
		
		if(g_iLoadedServices == 0) SetFailState("Не удалось получить список услуг");
		
		if(g_iLoggin & LOGSERVICES) LogToFileEx(sLog, "Загружено %i услуг из базы.", g_iLoadedServices);
		
		for (new i = 1; i <= MaxClients; ++i)
		{
			if (IsClientInGame(i)) OnClientPostAdminCheck(i);
		}
	}
}

public OnClientPostAdminCheck(client)
{
	if(IsFakeClient(client)) return;
	decl String: steamid[21], String:query[350];
	GetClientAuthId(client, AuthId_Engine, steamid, 21);
	if(g_iLoggin & LOGCONNECTS) LogToFileEx(sLog, "Игрок %N (%s) подключен.", client, steamid);	
	FormatEx(query, 350, "SELECT `admins_services`.`service`, `admins_services`.`rights_und`, `admins`.`pass` FROM `admins_services`, `admins` WHERE `admins`.`id`=`admins_services`.`admin_id` AND `admins`.`name`='%s' AND (`admins_services`.`ending_date`>CURRENT_TIMESTAMP OR`admins_services`.`ending_date`='0000-00-0000:00:00')", steamid);
	if(g_iLoggin & LOGDB) LogToFileEx(sLog, "OnClientPostAdminCheck: \"%s\"", query);
	SQL_TQuery(hDatabase, SQL_Callback, query, client)
}

public SQL_Callback(Handle:owner, Handle:hndl, const String:error[], any:client)
{
	if (!IsClientConnected(client))	return;
	
	if(hndl == INVALID_HANDLE) LogError("SQL_Callback Query falied. (error:  %s)", error);

	if (SQL_HasResultSet(hndl))
	{
		decl String:sFlags[AdminFlags_TOTAL + 1]; sFlags[0] = '\0';
		new	MaxImmunity;
		new c;
		
		while (SQL_FetchRow(hndl))
		{
			decl String:tFlags[AdminFlags_TOTAL + 1]; tFlags[0] = '\0';
			decl String:sPasswordDB[32]; sPasswordDB[0] = '\0';
			
			new iService = SQL_FetchInt(hndl, 0);
			new bool: bFlagsOverride;
			new iAuthStatus;
			// -1 - invalid pass
			//  0 - no db pass
			//  1 - valid pass
			
			
			SQL_FetchString(hndl, 2, sPasswordDB, sizeof(sPasswordDB));
			
			if(sPasswordDB[0] != 0)
			{
				decl String: sPassword[32]; sPassword[0] = '\0';
				iAuthStatus = -1;
				
				if(GetClientInfo(client, g_sInfoVar, sPassword, sizeof(sPassword)) && sPassword[0] != 0 && StrEqual(sPassword, sPasswordDB))
				{
					iAuthStatus = 1;
				}
			}
			
			SQL_FetchString(hndl, 1, tFlags, sizeof(tFlags));
			
			
			if(!StrEqual(tFlags, "none"))
			{
				bFlagsOverride = true;
			}
			else tFlags[0] = '\0';
			
			for(new i; i < g_iLoadedServices; i++)
			{
				if(g_iServiceId[i] == iService)
				{
					if(g_iLoggin & LOGRIGHTS) LogToFileEx(sLog, "У игрока %N обнаружена услуга: %s%s%s%s", client,  g_iServiceName[i], bFlagsOverride ? ". Обнаружено изменение флагов на ": "", tFlags,	iAuthStatus == -1 ? ", но пароль введен не верно" : (g_iLoggin & LOGPW && iAuthStatus == 1) ? ", пароль введен верно" : (g_iLoggin & LOGPW && iAuthStatus == 0) ? ", пароль не требуеться" : "");
					
					if(iAuthStatus != -1)
					{
						if(MaxImmunity < g_iServiceImmunity[i]) MaxImmunity = g_iServiceImmunity[i];
						
						if(bFlagsOverride)
						{
							new AdminFlag:flag;
							
							for (new a = 0; a < strlen(tFlags); a++)
							{
								if (!FindFlagByChar(tFlags[a], flag)) {LogToFileEx(sLog, "Найден неверный флаг: %c", tFlags[a]);}
								else
								{
									AddUserFlags(client, flag);
									if(g_iLoggin & LOGRIGHTS) {if(!FindFlagChar(flag, c)) c = 't'; Format(sFlags, sizeof(sFlags), "%s%c", sFlags, c);}
								}
							}
						}
						else
						{
							new AdminFlag:flags[AdminFlags_TOTAL];
							new num_flags = FlagBitsToArray(g_iServiceFlags[i], flags, sizeof(flags));
							
							for (new x = 0; x < num_flags; x++)
							{
								AddUserFlags(client, flags[x]);
								if(g_iLoggin & LOGRIGHTS) {if(!FindFlagChar(flags[x], c)) c = 't'; Format(sFlags, sizeof(sFlags), "%s%c", sFlags, c);}
							}
						}
					}
				}
			}
		}
	
		new	iImmunity, AdminId:id = GetUserAdmin(client);
		if(id == INVALID_ADMIN_ID)
		{
			id = CreateAdmin();
			SetUserAdmin(client, id, true);
		}
		else
		{
			iImmunity = GetAdminImmunityLevel(id);
		}
		
		if(iImmunity < MaxImmunity)
		{
			SetAdminImmunityLevel(id, iImmunity);
		}
		
		if(g_iLoggin & LOGRIGHTS && c != 0) LogToFileEx(sLog, "Игроку %N выданы флаги: \"%s\" и установлен иммунитет \"%i\"", client, sFlags, iImmunity < MaxImmunity ? MaxImmunity : iImmunity);
	}
}

public OnRebuildAdminCache(AdminCachePart:part)
{
	if(part != AdminCache_Admins) return;
	
	for (new i = 1; i <= MaxClients; ++i)
	{
		if (IsClientInGame(i)) OnClientPostAdminCheck(i);
	}
}


public UpdateCvar_log(Handle:c, const String:ov[], const String:nv[])	g_iLoggin = StringToInt(nv);