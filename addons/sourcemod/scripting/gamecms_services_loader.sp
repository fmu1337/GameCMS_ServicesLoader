#include <sourcemod>
#include <regex>


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
new String:	sInfoVar[32];


public Plugin:myinfo = 
{
	name = "GameCMS Admin Loader",
	author = "Danyas",
	description = "Loading admins and services from GameCMS database",
	version = "1.5",
	url = "https://vk.com/id36639907"
}

public OnPluginStart()
{
	if (!SQL_CheckConfig("gamecms")) 
	{ 
		SetFailState("Секция \"gamecms\" не найдена в databases.cfg");
	}
	
	new Handle: hCvar = CreateConVar(
		"sm_gamecms_loader_logs",
		"31", "1 - LOG SERVICES / 2 - LOG RIGHTS / 4 - CONNECTS / 8 - LOG DB QUERIES / 16 - LOG PASSCHECKS (LOG SERVICES + LOG RIGHTS = 3)"
		, _, true, 0.0, true, 31.0);
	
	HookConVarChange(hCvar, UpdateCvars);
	AutoExecConfig(true, "gamecms_loader");
	g_iLoggin = GetConVarInt(hCvar);
	SQL_TConnect(GotDatabase, "gamecms");
	
	if (!GetPassInfoVar(sInfoVar, sizeof(sInfoVar)))
	{
		if(g_iLoggin & LOGPW) LogToFileEx(sLog, "PassInfoVar не найден в файле core.cfg, установленно значение _pw");
		sInfoVar = "_pw";
	}
	else
	{
		if(g_iLoggin & LOGPW) LogToFileEx(sLog, "PassInfoVar = \"%s\"", sInfoVar);
	}
}

public GotDatabase(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)  
	{
		LogError("Database failure: %s", error);
		return;
	}

	hDatabase = hndl;
	decl String:query[192]; query[0] = '\0';
	
	new longip = GetConVarInt(FindConVar("hostip"));
	
	FormatEx(query, sizeof(query),
		"SELECT `id`, `name`, `rights`, `immunity` FROM `services` WHERE `server` = (SELECT `id` FROM `servers` WHERE `ip` = '%d.%d.%d.%d' AND `port` = '%i')",
			(longip >> 24) & 0x000000FF, (longip >> 16) & 0x000000FF, (longip >> 8) & 0x000000FF, longip & 0x000000FF,
			GetConVarInt(FindConVar("hostport")));
			
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
	decl String: steamid[32], String:query[384];
	GetClientAuthId(client, AuthId_Engine, steamid, 32);
	if(g_iLoggin & LOGCONNECTS) LogToFileEx(sLog, "Игрок %N (%s) подключен.", client, steamid);
	
	FormatEx(query, 384, 
		"SELECT `admins_services`.`service`, `admins_services`.`rights_und`, `admins`.`pass` FROM `admins_services`, `admins` WHERE `admins`.`id`=`admins_services`.`admin_id` AND `admins`.`name`='%s' AND (`admins_services`.`ending_date`>CURRENT_TIMESTAMP OR`admins_services`.`ending_date`='0000-00-0000:00:00')",
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
		new	iImmunity = GetAdminImmunityLevel(client);
		new AdminId:id = GetUserAdmin(client);
		new c;
		
		while (SQL_FetchRow(hndl))
		{	
			new iAuthStatus = 0;
			// -1 - invalid pass
			//  0 - no db pass
			//  1 - valid pass
			
			decl String: sPasswordDB[32]; sPasswordDB[0] = '\0';
			SQL_FetchString(hndl, 2, sPasswordDB, sizeof(sPasswordDB));
			
			if(sPasswordDB[0] != 0)
			{
				decl String: sPassword[32]; sPassword[0] = '\0';
				iAuthStatus = -1;
				
				if(GetClientInfo(client, sInfoVar, sPassword, sizeof(sPassword)))
				{
					if(sPassword[0] != 0 && StrEqual(sPassword, sPasswordDB))
					{
						iAuthStatus = 1;
					}
				}
				else LogToFileEx(sLog, "GetClientInfo \"%N\" Failed", client);
				
				if(iAuthStatus == -1) LogToFileEx(sLog, "Пароль \"%s\" неверен, правильный пароль \"%s\"", sPassword, sPasswordDB);
			}
			
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
					if(g_iLoggin & LOGRIGHTS)
						LogToFileEx(sLog, "У игрока %N обнаружена услуга: %s%s%s%s",
												client,  g_iServiceName[i],
												
												bFlagsOverride ? ". Обнаружено изменение флагов на ": "", tFlags,
												
												iAuthStatus == -1 ? ", но пароль введен не верно" :
													(g_iLoggin & LOGPW && iAuthStatus == 1) ? ", пароль введен верно" :
													(g_iLoggin & LOGPW && iAuthStatus == 0) ? ", пароль не требуеться" :
													"");
					if(iAuthStatus != -1)
					{
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

public OnRebuildAdminCache(AdminCachePart:part)
{
	if(part != AdminCache_Admins) return;
	
	for (new i = 1; i <= MaxClients; ++i)
	{
		if (IsClientInGame(i)) OnClientPostAdminCheck(i);
	}
}


public UpdateCvars(Handle:c, const String:ov[], const String:nv[])	g_iLoggin = StringToInt(nv);


bool:GetPassInfoVar(String:value[], maxlength)
{
	new Handle:file = OpenFile("addons/sourcemod/configs/core.cfg", "rt");
	if (file != INVALID_HANDLE)
	{
		new Handle:re = CompileRegex("^\\s+\"PassInfoVar\"\\s+\"(\\w+)\""); // ([^\"]*)
		if (re != INVALID_HANDLE)
		{
			decl String:buffer[PLATFORM_MAX_PATH];
			while (!IsEndOfFile(file) && ReadFileLine(file, buffer, sizeof(buffer)))
			{
				if (MatchRegex(re, buffer) > 0 && GetRegexSubString(re, 1, value, maxlength))
				{
					CloseHandle(re);
					CloseHandle(file);
					return true;
				}
			}
			CloseHandle(re);
		}
		CloseHandle(file);
	}
	return false;
}
