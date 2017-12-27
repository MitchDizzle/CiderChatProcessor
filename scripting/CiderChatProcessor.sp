#pragma semicolon 1
#pragma newdecls required
#include <CiderChatProcessor>


bool bNewMsg[MAXPLAYERS+1];

//EngineVersion engineVersion;

Handle fwOnChatMessagePre;
Handle fwOnChatMessage;
Handle fwOnChatMessagePost;

StringMap mapMessageFormats;

bool bProto;

ConVar cEnabled;
ConVar cConfig;
ConVar cDeadChat; //Dead chat isn't seen by alive players
ConVar cTeamChat; //Team chat isn't seen by the other team. 
                  // 0 - Team chat is only seen by teammates.
                  // 1 - All Team chat is made all chat.
                  // 2 - Team 2's team chat is seen by all players.
                  // 3 - Team 3's team chat is seen by all players.

#define PLUGIN_VERSION "1.0.0"
public Plugin myinfo = {
    name = "Cider Chat Processor",
    author = "Mitch",
    description = "A generic API for other plugins to capture chat messages",
    version = "1.0.0",
    url = "mtch.tech"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    RegPluginLibrary("CiderChatProcessor");

    fwOnChatMessagePre = CreateGlobalForward("CCP_OnChatMessagePre", ET_Hook, Param_CellByRef, Param_Cell, Param_String);
    fwOnChatMessage = CreateGlobalForward("CCP_OnChatMessage", ET_Hook, Param_CellByRef, Param_Cell, Param_String, Param_String, Param_String);
    fwOnChatMessagePost = CreateGlobalForward("CCP_OnChatMessagePost", ET_Ignore, Param_Cell, Param_Cell, Param_String, Param_String, Param_String, Param_String);

    //engineVersion = GetEngineVersion();
    return APLRes_Success;
}

public void OnPluginStart() {
    CreateConVar("sm_ciderchatprocessor_version", PLUGIN_VERSION, "A generic API for other plugins to capture chat messages", FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_SPONLY | FCVAR_DONTRECORD);
    
    cEnabled = CreateConVar("sm_ccp_enable", "1", "Enable Cider Chat Processor");
    cConfig = CreateConVar("sm_ccp_config", "configs/chat_processor.cfg", "Name of the message formats config.");
    cDeadChat = CreateConVar("sm_ccp_deadchat", "1", "Dead chat is seen by alive players.");
    cTeamChat = CreateConVar("sm_ccp_teamchat", "0", "Team chat isn't seen by other team");
    AutoExecConfig(true, "CiderChatProcessor");

    AddCommandListener(Command_Say, "say");
    AddCommandListener(Command_Say, "say_team");

    mapMessageFormats = CreateTrie();
}

public void OnConfigsExecuted() {
    char sGame[64];
    GetGameFolderName(sGame, sizeof(sGame));

    char sConfig[PLATFORM_MAX_PATH];
    cConfig.GetString(sConfig, sizeof(sConfig));

    GenerateMessageFormats(sConfig, sGame);

    bProto = CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf;

    UserMsg SayText2 = GetUserMessageId("SayText2");
    if (SayText2 != INVALID_MESSAGE_ID) {
        HookUserMessage(SayText2, OnSayText2, true);LogMessage("Successfully hooked either SayText or SayText2 chat hooks.");
    } else {
        SetFailState("Error loading the plugin, both chat hooks are unavailable. (SayText & SayText2)");
    }
}

public Action Command_Say(int client, const char[] command, int argc) {
    if (client > 0 && client <= MaxClients) {
        bNewMsg[client] = true;
    }
}

public Action OnSayText2(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init) {
    if (!cEnabled.BoolValue) {
        return Plugin_Continue;
    }

    int iSender = bProto ? PbReadInt(msg, "ent_idx") : BfReadByte(msg);
    if (iSender <= 0) {
        return Plugin_Continue;
    }

    if(!bNewMsg[iSender]) {
        return Plugin_Stop;
    }
    bNewMsg[iSender] = false;

    bool bChat = true;
    char sFlag[MAXLENGTH_FLAG];
    char sFormat[MAXLENGTH_BUFFER];
    char sName[MAXLENGTH_NAME];
    char sMessage[MAXLENGTH_MESSAGE];
    if(bProto) {
        bChat = PbReadBool(msg, "chat");
        PbReadString(msg, "msg_name", sFlag, sizeof(sFlag));
        PbReadString(msg, "params", sName, sizeof(sName), 0);
        PbReadString(msg, "params", sMessage, sizeof(sMessage), 1);
    } else {
        bChat = view_as<bool>(BfReadByte(msg));
        BfReadString(msg, sFlag, sizeof(sFlag));
        if(BfGetNumBytesLeft(msg)) {
            BfReadString(msg, sName, sizeof(sName));
        }
        if(BfGetNumBytesLeft(msg)) {
            BfReadString(msg, sMessage, sizeof(sMessage));
        }
    }
    //Find any weird colors that aren't supposed to be there.
    char findString[6];
    for(int cl = 1; cl < 17; cl++) {
        Format(findString, sizeof(findString), "%c", cl);
        ReplaceString(sMessage, sizeof(sMessage), findString, "");
    }

    ArrayList alRecipients = CreateArray();

    bool bAllChat = StrContains(sFlag, "_All") != -1;
    
    bool bDeadChat = cDeadChat.BoolValue;
    int  iTeamChat = cTeamChat.IntValue;
    int  team = GetClientTeam(iSender);

    if(!bAllChat && ((iTeamChat == 1) ||
        (team == 2 && iTeamChat == 2) ||
        (team == 3 && iTeamChat == 3))) {
        ReplaceString(sFlag, MAXLENGTH_FLAG, "Team_Dead", "AllDead", false);
        ReplaceString(sFlag, MAXLENGTH_FLAG, "Team", "All", false);
        bAllChat = true;
    }
    
    if(!mapMessageFormats.GetString(sFlag, sFormat, sizeof(sFormat))) {
        return Plugin_Continue;
    }

    alRecipients.Push(GetClientUserId(iSender)); //Always add the sender.
    for(int i = 1; i < MaxClients; i++) {
        if(!IsClientInGame(i) || IsFakeClient(i) || i == iSender) {
            continue;
        }
        
        if(!bAllChat && team != GetClientTeam(i)) {
            continue;
        }

        if(!IsPlayerAlive(iSender)) {
            if(!bDeadChat && IsPlayerAlive(i)) {
                continue;
            }
        }
        alRecipients.Push(GetClientUserId(i));
    }

    //We need to make copy of these strings for checks after the pre-forward has fired.
    char sNameCopy[MAXLENGTH_NAME];
    strcopy(sNameCopy, sizeof(sNameCopy), sName);

    char sMessageCopy[MAXLENGTH_MESSAGE];
    strcopy(sMessageCopy, sizeof(sMessageCopy), sMessage);

    char sFlagCopy[MAXLENGTH_FLAG];
    strcopy(sFlagCopy, sizeof(sFlagCopy), sFlag);
    int author = iSender;
    
    Call_StartForward(fwOnChatMessagePre);
    Call_PushCellRef(iSender);
    Call_PushCell(alRecipients);
    Call_PushStringEx(sFlag, sizeof(sFlag), SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);

    Action iResults;
    int error = Call_Finish(iResults);
    if(error != SP_ERROR_NONE) {
        delete alRecipients;
        ThrowNativeError(error, "Global Forward 'CCP_OnChatMessage' has failed to fire. [Error code: %i]", error);
        return Plugin_Continue;
    }
    if(iResults == Plugin_Stop) {
        delete alRecipients;
        return Plugin_Continue;
    }

    Call_StartForward(fwOnChatMessage);
    Call_PushCellRef(iSender);
    Call_PushCell(alRecipients);
    Call_PushStringEx(sFlag, sizeof(sFlag), SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
    Call_PushStringEx(sName, sizeof(sName), SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
    Call_PushStringEx(sMessage, sizeof(sMessage), SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);

    error = Call_Finish(iResults);
    if(error != SP_ERROR_NONE) {
        delete alRecipients;
        ThrowNativeError(error, "Global Forward 'CCP_OnChatMessage' has failed to fire. [Error code: %i]", error);
        return Plugin_Continue;
    }
    if(iResults == Plugin_Stop) {
        delete alRecipients;
        return Plugin_Continue;
    }
    
    bool replaceAuthor = false;
    if(iSender == -1) {
        replaceAuthor = true;
        iSender = author;
    }

    if(!StrEqual(sFlag, sFlagCopy) && !mapMessageFormats.GetString(sFlag, sFormat, sizeof(sFormat))) {
        delete alRecipients;
        return Plugin_Continue;
    }

    Handle hPack = CreateDataPack();
    WritePackCell(hPack, GetClientUserId(iSender));
    WritePackString(hPack, sName);
    WritePackString(hPack, sMessage);
    WritePackString(hPack, sFlag);
    WritePackCell(hPack, alRecipients);
    WritePackCell(hPack, replaceAuthor);

    WritePackString(hPack, sFormat);
    WritePackCell(hPack, bChat);
    WritePackCell(hPack, iResults);

    RequestFrame(Frame_OnChatMessage_SayText2, hPack);

    return Plugin_Stop;
}

public void Frame_OnChatMessage_SayText2(DataPack data) {
    //Retrieve pack contents and what not, this part is obvious.
    ResetPack(data);

    int iSender = GetClientOfUserId(ReadPackCell(data));
    
    char sName[MAXLENGTH_NAME];
    ReadPackString(data, sName, sizeof(sName));

    char sMessage[MAXLENGTH_MESSAGE];
    ReadPackString(data, sMessage, sizeof(sMessage));

    char sFlag[MAXLENGTH_FLAG];
    ReadPackString(data, sFlag, sizeof(sFlag));
    
    ArrayList alRecipients = ReadPackCell(data);
    
    bool replaceAuthor = ReadPackCell(data);

    char sFormat[MAXLENGTH_BUFFER];
    ReadPackString(data, sFormat, sizeof(sFormat));

    bool bChat = ReadPackCell(data);
    Action iResults = ReadPackCell(data);

    delete data;
    
    if(!iSender || !IsClientInGame(iSender)) {
        delete alRecipients;
        return;
    }
    
    int author = -1;
    if(!replaceAuthor) {
        author = iSender;
    }
    
    if(iResults != Plugin_Changed) {
        Format(sMessage, sizeof(sMessage), "\x01%s", sMessage);
        Format(sName, sizeof(sName), "\x03%s", sName);
    }
    
    //ReplaceString(sMessage, sizeof(sMessage), "%", "%%"); //Annoying fix.
    if(iResults != Plugin_Stop)  {
        int printToClients[MAXPLAYERS+1];
        int clientCount = 0;
        for(int i = 0; i < GetArraySize(alRecipients); i++) {
            int client = GetClientOfUserId(GetArrayCell(alRecipients, i));
            if(client && IsClientInGame(client)) {
                printToClients[clientCount] = client;
                clientCount++;
            }
        }
        if(clientCount != 0) {
            Handle buf = StartMessage("SayText2", printToClients, clientCount, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);
            //Handle buf = StartMessageOne("SayText2", client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);
            char sBuffer[MAXLENGTH_BUFFER];
            strcopy(sBuffer, sizeof(sBuffer), sFormat);
            Format(sBuffer, sizeof(sBuffer), "\x01%s", sBuffer);

            ReplaceString(sBuffer, sizeof(sBuffer), "{3}", "\x01");
            ReplaceString(sName, sizeof(sName), "{2}", "{2\x01}");
            ReplaceString(sBuffer, sizeof(sBuffer), "{1}", sName);
            ReplaceString(sBuffer, sizeof(sBuffer), "{2}", sMessage);
            ReplaceString(sBuffer, sizeof(sBuffer), "{2\x01}", "{2}");
            if(bProto) {
                PbSetInt(buf, "ent_idx", author);
                PbSetBool(buf, "chat", false);
                PbSetString(buf, "msg_name", sBuffer);
                PbAddString(buf, "params", "");
                PbAddString(buf, "params", "");
                PbAddString(buf, "params", "");
                PbAddString(buf, "params", "");
            } else {
                BfWriteByte(buf, author); // Message author
                BfWriteByte(buf, bChat); // Chat message
                BfWriteString(buf, sBuffer); // Message text
            }
            EndMessage();
        }
    }

    Call_StartForward(fwOnChatMessagePost);
    Call_PushCell(iSender);
    Call_PushCell(alRecipients);
    Call_PushString(sFlag);
    Call_PushString(sFormat);
    Call_PushString(sName);
    Call_PushString(sMessage);
    Call_Finish();

    delete alRecipients;
}

public bool GenerateMessageFormats(const char[] config, const char[] game) {
    KeyValues kv = CreateKeyValues("chat-processor");

    char sPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sPath, sizeof(sPath), config);

    if (FileToKeyValues(kv, sPath) && KvJumpToKey(kv, game) && KvGotoFirstSubKey(kv, false)) {
        ClearTrie(mapMessageFormats);
        do {
            char sName[256];
            KvGetSectionName(kv, sName, sizeof(sName));

            char sValue[256];
            KvGetString(kv, NULL_STRING, sValue, sizeof(sValue));

            SetTrieString(mapMessageFormats, sName, sValue);

        } while (KvGotoNextKey(kv, false));

        LogMessage("Message formats generated for game '%s'.", game);
        delete kv;
        return true;
    }

    LogError("Error parsing the flag message formatting config for game '%s', please verify its integrity.", game);
    delete kv;
    return false;
}