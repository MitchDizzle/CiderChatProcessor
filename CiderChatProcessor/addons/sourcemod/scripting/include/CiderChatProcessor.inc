#if defined _CiderChatProcessor_included
  #endinput
#endif
#define _CiderChatProcessor_included

//Globals
#define MAXLENGTH_FLAG		32
#define MAXLENGTH_NAME		128
#define MAXLENGTH_MESSAGE	128
#define MAXLENGTH_BUFFER	255

forward Action CCP_OnChatMessagePre(int& author, ArrayList recipients, char[] flagstring);

/**
* Called while sending a chat message before It's sent.
* Limits on the name and message strings can be found above.
*
* param author			Author that created the message. For CSGO setting to -1 will turn \x03 from team color to Purple.
* param recipients		Array of clients who will receive the message.
* param flagstring		Flag string to determine the type of message.
* param name			Name string of the author to be pushed.
* param message		Message string from the author to be pushed.
*
* return types
*  - Plugin_Continue	Stops the message.
*  - Plugin_Stop		Stops the message.
*  - Plugin_Changed		Fires the post-forward below and prints out a message.
*  - Plugin_Handled		Fires the post-forward below but doesn't print a message.
**/
forward Action CCP_OnChatMessage(int& author, ArrayList recipients, char[] flagstring, char[] name, char[] message);

/**
* Called after the chat message is sent to the designated clients by the author.
*
* param author			Author that sent the message.
* param recipients		Array of clients who received the message.
* param flagstring		Flag string to determine the type of message.
* param formatstring	Format string used in the message based on the flag string.
* param name			Name string of the author.
* param message		Message string from the author.
* param processcolors	Check if colors were processed in the buffer strings.
* param removecolors	Check if colors were removed from the buffer strings.
*
* noreturn
**/
forward void CCP_OnChatMessagePost(int author, ArrayList recipients, const char[] flagstring, const char[] formatstring, const char[] name, const char[] message);

#if !defined REQUIRE_PLUGIN
public void __pl_CiderChatProcessor_SetNTVOptional() {
}
#endif

public SharedPlugin __pl_CiderChatProcessor = {
	name = "CiderChatProcessor",
	file = "CiderChatProcessor.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};
