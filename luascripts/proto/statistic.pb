
?[
statistic.protonetwork.cmd"[
PBTexasStatisticReq
uid (Ruid
gameid (Rgameid
roomtype (Rroomtype"?
PBTexasStatisticEntry
vpip (Rvpip
pfr (Rpfr
winrate (Rwinrate

totalhands (R
totalhands 
totalprofit (Rtotalprofit"?
PBTexasStatisticResp
uid (Ruid
gameid (Rgameid
roomtype (Rroomtype4
day (2".network.cmd.PBTexasStatisticEntryRday8
month (2".network.cmd.PBTexasStatisticEntryRmonth8
total (2".network.cmd.PBTexasStatisticEntryRtotal"L
PBStatisticGameRankReq
gameid (Rgameid
ranktype (Rranktype"?
PBRankMostWinInToday
nickname (	Rnickname
nickurl (	Rnickurl
amount (Ramount
	timestamp (R	timestamp
rank (Rrank
uid (Ruid"?
PBStatisticGameRankResp
gameid (Rgameid
ranktype (Rranktype;
mostwin (2!.network.cmd.PBRankMostWinInTodayRmostwin"6
 PBStatisticGameJackpotRecordsReq
jpid (Rjpid"?
PBStatisticGameJackpotData
username (	Rusername
	pokertype (R	pokertype
bonus (Rbonus
	timestamp (R	timestamp"E
PBStatisticGameJackpotLevelConf
sb (Rsb
ante (Rante"?
!PBStatisticGameJackpotRecordsRespN
biggest_winner (2'.network.cmd.PBStatisticGameJackpotDataRbiggestWinnerL
bonus_records (2'.network.cmd.PBStatisticGameJackpotDataRbonusRecordsH
conflist (2,.network.cmd.PBStatisticGameJackpotLevelConfRconflist"?
PBStatisticGameClickEventReq
clickid (Rclickid
clitype (Rclitype
acctype (Racctype
uid (Ruid
uuid (	Ruuid
balance (Rbalance
api (Rapi*?
PBEnumRankType!
PBEnumRankType_MostWinInToday&
"PBEnumRankType_MostWinHistoryToday!
PBEnumRankType_MostWinInRound&
"PBEnumRankType_MostWinHistoryRound
PBEnumRankType_Max*?
PBClientAccoutType!
PBClientAccoutType_Login_None %
!PBClientAccoutType_Login_Facebook(
$PBClientAccoutType_Login_HW_FastGame&
"PBClientAccoutType_Login_rummycity#
PBClientAccoutType_Login_Guest?#
PBClientAccoutType_Login_Phone?*?
PBClientOSType
PBClientOSType_WIN32 
PBClientOSType_LINUX
PBClientOSType_MACOS
PBClientOSType_ANDROID
PBClientOSType_IPHONE
PBClientOSType_IPAD
PBClientOSType_BLACKBERRY
PBClientOSType_NACL
PBClientOSType_EMSCRIPTEN
PBClientOSType_TIZEN	
PBClientOSType_WINRT

PBClientOSType_WP8!
PBClientOSType_MOBILE_BROWSERd"
PBClientOSType_DESKTOP_BROWSERe
PBClientOSType_EDITOR_PAGEf
PBClientOSType_EDITOR_COREg
PBClientOSType_WECHAT_GAMEh
PBClientOSType_QQ_PLAYi"
PBClientOSType_FB_PLAYABLE_ADSj
PBClientOSType_BAIDU_GAMEk
PBClientOSType_VIVO_GAMEl
PBClientOSType_OPPO_GAMEm
PBClientOSType_HUAWEI_GAMEn
PBClientOSType_XIAOMI_GAMEo
PBClientOSType_JKW_GAMEp
PBClientOSType_ALIPAY_GAMEq"
PBClientOSType_WECHAT_GAME_SUBr!
PBClientOSType_BAIDU_GAME_SUBs*?D
PBClientClickEventType
PBCCEType_None !
PBCCEType_login_loginRegister
PBCCEType_login_guest
PBCCEType_login_bonustag
PBCCEType_login_service$
 PBCCEType_loginRegister_logintab'
#PBCCEType_loginRegister_registertab,
(PBCCEType_loginRegister_login_phoneinput$
 PBCCEType_loginRegister_pwdinput'
#PBCCEType_loginRegister_login_foget	*
&PBCCEType_loginRegister_login_loginbtn
2
.PBCCEType_loginRegister_login_loginbtn_english0
,PBCCEType_loginRegister_login_loginbtn_hindi/
+PBCCEType_loginRegister_register_phoneinput-
)PBCCEType_loginRegister_register_optinput+
'PBCCEType_loginRegister_register_optbtn0
,PBCCEType_loginRegister_register_registerbtn8
4PBCCEType_loginRegister_register_registerbtn_english6
2PBCCEType_loginRegister_register_registerbtn_hindi
PBCCEType_lobby_avatar
PBCCEType_lobby_moneyplus
PBCCEType_lobby_chest
PBCCEType_lobby_download
PBCCEType_lobby_service
PBCCEType_lobby_mail
PBCCEType_lobby_setting
PBCCEType_lobby_Rummy
PBCCEType_lobby_Teenpatti
PBCCEType_lobby_Joker 
PBCCEType_lobby_BetTeenpatti
PBCCEType_lobby_AB
PBCCEType_lobby_CB
PBCCEType_lobby_DT 
PBCCEType_lobby_wheel!
PBCCEType_lobby_Task"
PBCCEType_lobby_Checkin#
PBCCEType_lobby_Refer$
PBCCEType_lobby_Wallet%
PBCCEType_checkin_wallet&
PBCCEType_checkin_claim'
PBCCEType_checkin_nextlevel(!
PBCCEType_checkin_levelIcon_0)!
PBCCEType_checkin_levelIcon_1*!
PBCCEType_checkin_levelIcon_2+!
PBCCEType_checkin_levelIcon_3,!
PBCCEType_checkin_levelIcon_4-!
PBCCEType_checkin_levelIcon_5.!
PBCCEType_checkin_levelIcon_6/!
PBCCEType_checkin_levelIcon_70!
PBCCEType_checkin_levelIcon_81!
PBCCEType_checkin_levelIcon_92#
PBCCEType_daily_deposit_deposit3!
PBCCEType_daily_deposit_close4
PBCCEType_daily_deposit_05
PBCCEType_daily_deposit_16
PBCCEType_daily_deposit_27
PBCCEType_daily_deposit_38
PBCCEType_daily_deposit_49
PBCCEType_daily_deposit_5:
PBCCEType_daily_deposit_6;#
PBCCEType_first_deposit_deposit<!
PBCCEType_first_deposit_close=
PBCCEType_first_deposit_0>
PBCCEType_first_deposit_1?
PBCCEType_first_deposit_2@
PBCCEType_first_deposit_3A
PBCCEType_first_deposit_4B
PBCCEType_first_deposit_5C
PBCCEType_refer_earnD
PBCCEType_refer_mybonusE
PBCCEType_refer_referralsF
PBCCEType_refer_rankG
PBCCEType_refer_WhatsAppH
PBCCEType_refer_facebookI
PBCCEType_refer_telegramJ
PBCCEType_refer_sharelinkK
PBCCEType_chest_nextlevelL
PBCCEType_chest_levelicon_0M
PBCCEType_chest_levelicon_1N
PBCCEType_chest_levelicon_2O
PBCCEType_chest_levelicon_3P
PBCCEType_chest_levelicon_4Q
PBCCEType_chest_levelicon_5R
PBCCEType_chest_levelicon_6S
PBCCEType_chest_levelicon_7T
PBCCEType_chest_levelicon_8U
PBCCEType_chest_levelicon_9V!
PBCCEType_setting_cardstyle_1W!
PBCCEType_setting_cardstyle_2X"
PBCCEType_setting_tablecolor_1Y"
PBCCEType_setting_tablecolor_2Z"
PBCCEType_setting_tablecolor_3[!
PBCCEType_setting_sound_close\ 
PBCCEType_setting_sound_open]!
PBCCEType_setting_music_close^ 
PBCCEType_setting_music_open_
PBCCEType_setting_logout`
PBCCEType_wallet_depositTaba"
PBCCEType_wallet_withdrawalTabb
PBCCEType_wallet_recordTabc
PBCCEType_wallet_serviced"
PBCCEType_wallet_quickamount_0e"
PBCCEType_wallet_quickamount_1f"
PBCCEType_wallet_quickamount_2g"
PBCCEType_wallet_quickamount_3h"
PBCCEType_wallet_quickamount_4i"
PBCCEType_wallet_quickamount_5j!
PBCCEType_wallet_rolloverhintk!
PBCCEType_wallet_fiaiedreasonl
PBCCEType_wallet_video_0m
PBCCEType_wallet_video_1n
PBCCEType_wallet_video_2o
PBCCEType_wallet_video_3p
PBCCEType_wallet_video_4q
PBCCEType_wallet_video_5r 
PBCCEType_rummy_roomlist_lowx 
PBCCEType_rummy_roomlist_midy!
PBCCEType_rummy_roomlist_highz%
!PBCCEType_rummy_roomlist_addmoney{,
(PBCCEType_rummy_roomlist_style_liststyle|,
(PBCCEType_rummy_roomlist_style_iconstyle}$
 PBCCEType_teenpatti_roomlist_low~$
 PBCCEType_teenpatti_roomlist_mid&
!PBCCEType_teenpatti_roomlist_high?*
%PBCCEType_teenpatti_roomlist_addmoney?1
,PBCCEType_teenpatti_roomlist_style_liststyle?1
,PBCCEType_teenpatti_roomlist_style_iconstyle?'
"PBCCEType_joker3patti_roomlist_low?'
"PBCCEType_joker3patti_roomlist_mid?(
#PBCCEType_joker3patti_roomlist_high?,
'PBCCEType_joker3patti_roomlist_addmoney?3
.PBCCEType_joker3patti_roomlist_style_liststyle?3
.PBCCEType_joker3patti_roomlist_style_iconstyle?
PBCCEType_rummyRoom_menu?%
 PBCCEType_rummyRoom_menu_standup?#
PBCCEType_rummyRoom_menu_rules?$
PBCCEType_rummyRoom_menu_switch?%
 PBCCEType_rummyRoom_menu_setting?#
PBCCEType_rummyRoom_menu_leave?!
PBCCEType_rummyRoom_taskicon?
PBCCEType_rummyRoom_record?
PBCCEType_rummyRoom_chat?%
 PBCCEType_rummyRoom_playeravatar?!
PBCCEType_rummyRoom_buyinBtn?"
PBCCEType_rummyRoom_buyin_add?#
PBCCEType_rummyRoom_buyin_less?'
"PBCCEType_rummyRoom_buyin_addmoney?%
 PBCCEType_rummyRoom_buyin_slider?%
 PBCCEType_rummyRoom_result_leave?(
#PBCCEType_rummyRoom_result_continue?!
PBCCEType_teenpattiRoom_menu?)
$PBCCEType_teenpattiRoom_menu_standup?'
"PBCCEType_teenpattiRoom_menu_rules?(
#PBCCEType_teenpattiRoom_menu_switch?)
$PBCCEType_teenpattiRoom_menu_setting?'
"PBCCEType_teenpattiRoom_menu_leave?%
 PBCCEType_teenpattiRoom_taskicon?#
PBCCEType_teenpattiRoom_record?!
PBCCEType_teenpattiRoom_chat?)
$PBCCEType_teenpattiRoom_playeravatar?%
 PBCCEType_teenpattiRoom_buyinBtn?&
!PBCCEType_teenpattiRoom_buyin_add?'
"PBCCEType_teenpattiRoom_buyin_less?+
&PBCCEType_teenpattiRoom_buyin_addmoney?)
$PBCCEType_teenpattiRoom_buyin_slider?$
PBCCEType_teenpattiRoom_jackpot?
PBCCEType_jackpot_record?+
&PBCCEType_rummy_losebet_prompt_confirm?*
%PBCCEType_rummy_losebet_prompt_cancel?/
*PBCCEType_teenpatti_losebet_prompt_confirm?.
)PBCCEType_teenpatti_losebet_prompt_cancel?1
,PBCCEType_joker3patti_losebet_prompt_confirm?0
+PBCCEType_joker3patti_losebet_prompt_cancel?
PBCCEType_betgame_cb_menu?%
 PBCCEType_betgame_cb_menu_review?&
!PBCCEType_betgame_cb_menu_setting?
PBCCEType_betgame_cb_task?#
PBCCEType_betgame_cb_repeatbet?"
PBCCEType_betgame_cb_addmoney?
PBCCEType_betgame_cb_lushu?#
PBCCEType_betgame_cb_lushuicon?!
PBCCEType_betgame_cb_players?!
PBCCEType_betgame_cb_chipadd?"
PBCCEType_betgame_cb_chipless?)
$PBCCEType_betgame_cb_players_rankTab?
PBCCEType_betgame_dt_menu?%
 PBCCEType_betgame_dt_menu_review?&
!PBCCEType_betgame_dt_menu_setting?
PBCCEType_betgame_dt_task?#
PBCCEType_betgame_dt_repeatbet?"
PBCCEType_betgame_dt_addmoney?
PBCCEType_betgame_dt_lushu?#
PBCCEType_betgame_dt_lushuicon?!
PBCCEType_betgame_dt_players?!
PBCCEType_betgame_dt_chipadd?"
PBCCEType_betgame_dt_chipless?)
$PBCCEType_betgame_dt_players_rankTab?"
PBCCEType_betgame_dt_bebanker?
PBCCEType_betgame_ab_menu?%
 PBCCEType_betgame_ab_menu_review?&
!PBCCEType_betgame_ab_menu_setting?
PBCCEType_betgame_ab_task?#
PBCCEType_betgame_ab_repeatbet?"
PBCCEType_betgame_ab_addmoney?
PBCCEType_betgame_ab_lushu?#
PBCCEType_betgame_ab_lushuicon?!
PBCCEType_betgame_ab_players?!
PBCCEType_betgame_ab_chipadd?"
PBCCEType_betgame_ab_chipless?)
$PBCCEType_betgame_ab_players_rankTab?%
 PBCCEType_betgame_bet3patti_menu?,
'PBCCEType_betgame_bet3patti_menu_review?-
(PBCCEType_betgame_bet3patti_menu_setting?%
 PBCCEType_betgame_bet3patti_task?*
%PBCCEType_betgame_bet3patti_repeatbet?)
$PBCCEType_betgame_bet3patti_addmoney?&
!PBCCEType_betgame_bet3patti_lushu?*
%PBCCEType_betgame_bet3patti_lushuicon?(
#PBCCEType_betgame_bet3patti_players?(
#PBCCEType_betgame_bet3patti_chipadd?)
$PBCCEType_betgame_bet3patti_chipless?0
+PBCCEType_betgame_bet3patti_players_rankTab?
PBCCEType_task_dailyTab?
PBCCEType_task_achieveTab?
PBCCEType_task_daily_tpTab?"
PBCCEType_task_daily_jokerTab?"
PBCCEType_task_daily_rummyTab? 
PBCCEType_task_daily_betTab?!
PBCCEType_task_achieve_tpTab?$
PBCCEType_task_achieve_jokerTab?$
PBCCEType_task_achieve_rummyTab?"
PBCCEType_task_achieve_betTab?"
PBCCEType_task_daily_tp_goBtn?%
 PBCCEType_task_daily_joker_goBtn?%
 PBCCEType_task_daily_rummy_goBtn?#
PBCCEType_task_daily_bet_goBtn?$
PBCCEType_task_achieve_tp_goBtn?'
"PBCCEType_task_achieve_joker_goBtn?'
"PBCCEType_task_achieve_rummy_goBtn?%
 PBCCEType_task_achieve_bet_goBtn?
PBCCEType_lobby_Slot?