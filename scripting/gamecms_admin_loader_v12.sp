#include <sourcemod>

#define MAXSERVICES 32

static String: sLog[] = "addons/sourcemod/logs/gamecms_admin_loader.log";

new Handle:	hDatabase;

new 		g_iServiceId[MAXSERVICES];
new String:	g_iServiceName[MAXSERVICES][64];
new 		g_iServiceFlags[MAXSERVICES];
new 		g_iServiceImmunity[MAXSERVICES];
new			g_iLoadedServices;

new 		g_iLoggin;

#define LOGSERVICES	1
#define LOGRIGHTS	2
#define LOGCONNECTS	4
#define LOGDB		8


public Plugin:myinfo = 
{
	name = "GameCMS Admin Loader",
	author = "Danyas",
	description = "",
	version = "1.3 [12.12.2016]",
	url = "https://vk.com/id36639907"
}

public OnPluginStart()
{
	if (!SQL_CheckConfig("gamecms")) 
	{ 
		SetFailState("Секция \"gamecms\" не найдена в databases.cfg");
	}
	
	HookConVarChange(CreateConVar("sm_gamecms_loader_log", "2", "0 - выключить логи, 1 - логи загрузки услуг, 2 - логи выданых услуг, 4 - логи подключений всех игроков, 8 - логи БД"), UpdateCvars);
	AutoExecConfig(true, "gamecms_loader");
	
	SQL_TConnect(GotDatabase, "gamecms");
}

public UpdateCvars(Handle:convar, const String:oldValue[], const String:newValue[])
{
	g_iLoggin = StringToInt(newValue);
	
	if(g_iLoggin & LOGSERVICES)	PrintToServer("LOGSERVICES");
	if(g_iLoggin & LOGRIGHTS)	PrintToServer("LOGRIGHTS");
	if(g_iLoggin & LOGCONNECTS)	PrintToServer("LOGCONNECTS");
	if(g_iLoggin & LOGDB)		PrintToServer("LOGDB");
}


public GotDatabase(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)  
	{
		LogError("Database failure: %s", error);
		return;
	}

	hDatabase = hndl;
	PrintToServer("%i", g_iLoggin);
	new longip = GetConVarInt(FindConVar("hostip"));
	decl String:query[192];
	FormatEx(query, sizeof(query), "SELECT `id`, `name`, `rights`, `immunity` FROM `services` WHERE `server` = (SELECT `id` FROM `servers` WHERE `ip` = '%d.%d.%d.%d' AND `port` = '%i')", (longip >> 24) & 0x000000FF, (longip >> 16) & 0x000000FF, (longip >> 8) & 0x000000FF, longip & 0x000000FF, GetConVarInt(FindConVar("hostport")));
	if(g_iLoggin & LOGDB) LogToFileEx(sLog, "Got Database: \"%s\"", query);
	SQL_TQuery(hDatabase, SQL_GetServices, query);
}

public SQL_GetServices(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE) LogError("SQL_GetServices Query falied. (error:  %s)", error);

	if (SQL_HasResultSet(hndl))
	{
		g_iLoadedServices = 0;
		if(g_iLoggin & LOGSERVICES)  LogToFileEx(sLog, "|#    |        Флаги          | Иммунитет | Название услуги");
		PrintToServer("%i", g_iLoggin);
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
			
			if(g_iLoggin & LOGSERVICES) LogToFileEx(sLog, "|#%4d| %21s | %9i | %s", g_iLoadedServices + 1, buff, g_iServiceImmunity[g_iLoadedServices], g_iServiceName[g_iLoadedServices]);
			
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
	PrintToServer("%i", g_iLoggin);
	if(IsFakeClient(client)) return;
	decl String: steamid[32], String:query[256];
	GetClientAuthId(client, AuthId_Engine, steamid, 32);
	if(g_iLoggin & LOGCONNECTS) LogToFileEx(sLog, "Игрок %N (%s) подключен.", client, steamid);
	
	FormatEx(query, 256, 
		"SELECT `service`, `rights_und` FROM `admins_services` WHERE `admin_id` = (SELECT `id` FROM `admins` WHERE `name` = '%s') AND (`ending_date` > CURRENT_TIMESTAMP OR `ending_date` = '0000-00-00 00:00:00')",
		steamid);
	
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
		
		new	iImmunity = GetAdminImmunityLevel(client)
		new AdminId:id = GetUserAdmin(client);
		new c;
		
		while (SQL_FetchRow(hndl))
		{	
			decl String:tFlags[AdminFlags_TOTAL + 1]; tFlags[0] = '\0';
			
			SQL_FetchString(hndl, 1, tFlags, sizeof(tFlags));
			
			new bool: bFlagsOverride;
			if(!StrEqual(tFlags, "none"))
			{
				bFlagsOverride = true;
			}
			else tFlags[0] = '\0';
			
			new iService = SQL_FetchInt(hndl, 0);
			
			new i;
			for(i = 0; i < g_iLoadedServices; i++)
			{
				if(g_iServiceId[i] == iService)
				{
					if(g_iLoggin & LOGRIGHTS) LogToFileEx(sLog, "У игрока %N обнаружена услуга: %s%s%s", client,  g_iServiceName[i],  bFlagsOverride ? ". Обнаружено изменение флагов на ": "", tFlags);
					
					if(iImmunity < g_iServiceImmunity[i])
					{
						iImmunity = g_iServiceImmunity[i];
					}
					
					if(bFlagsOverride)
					{
						new len = strlen(tFlags);
						new AdminFlag:flag;
						
						for (new a = 0; a < len; a++)
						{
							if (!FindFlagByChar(tFlags[a], flag))
							{
								LogToFileEx(sLog, "Найден неверный флаг: %c", tFlags[a]);
							}
							else
							{
								SetAdminFlag(id, flag, true);
								
								if(g_iLoggin & LOGRIGHTS)
								{
									FindFlagChar(flag, c);
									Format(sFlags, sizeof(sFlags), "%s%c", sFlags, c);
								}
							}
						}
					}
					
					else
					{
						new AdminFlag:flags[AdminFlags_TOTAL];
						new num_flags = FlagBitsToArray(g_iServiceFlags[i], flags, sizeof(flags));
						
						for (new x = 0; x < num_flags; x++)
						{
							SetAdminFlag(id, flags[x], true);
							if(g_iLoggin & LOGRIGHTS)
							{
								if(!FindFlagChar(flags[x], c)) c = 't';
								Format(sFlags, sizeof(sFlags), "%s%c", sFlags, c);
							}
						}
					}
				}
			}
		}
		
		if(g_iLoggin & LOGRIGHTS)
		{
			if(c != 0)
			{
				LogToFileEx(sLog, "Игроку %N выданы флаги: %s", client, sFlags);
			}
			
			if(iImmunity != 0)
			{
				LogToFileEx(sLog, "Игроку %N установлен иммунитет: %i", client, iImmunity);
			}
		}
	}
}
