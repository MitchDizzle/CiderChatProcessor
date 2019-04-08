# Cider Chat Processor

Just another Sourcemod SayText2 hook and forwards. 
The reason this exists is primiarily because I've had so many issues with the other chat processors availalbe.
I needed something that could also change the recipients before any other plugin added chat colors etc, and manage dead chat properly.
Also needed it to disable `say_team` theroritically, so the other team can see it (without the prefix of `(TEAM)`). 

This plugin contains a few bug fixes that other processors do not contain that should prevent any exploits of players adding colors to their chat without help from a server plugin.


## ConVar Config

```
//Enable Cider Chat Processor
sm_ccp_enable "1"   

//Name of the message formats config, incase you have some where else you want to put this?
sm_ccp_config "configs/chat_processor.cfg"

//Dead chat is seen by alive players.
// (WARNING) a module plugin can use CCP_OnChatMessagePre or CCP_OnChatMessage to change the array of recipients.
sm_ccp_deadchat "1"     

//Team chat isn't seen by other team
// 0 - Disabled, say_team isn't converted to All Chat.
// 1 - No Filter, all team's say_team is converted to All Chat.
// 2 - Team 2's chat is converted to All Chat.
// 3 - Team 3's chat is converted to All Chat.
sm_ccp_teamchat "0"     
```