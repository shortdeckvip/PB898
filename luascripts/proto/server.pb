
®ê
server.protonetwork.inter"M
SharedSynData
uids (Ruids
udids (	Rudids
apis (	Rapis"l
SharedRegisterServer
type (Rtype
sid (Rsid
yosid (Ryosid
syndata (Rsyndata"§
SharedPlayerLogout
uid (Ruid
roomid (Rroomid
matchid (Rmatchid
	accountid (	R	accountid
gameid (	Rgameid
token (	Rtoken"I
SharedPlayerLogin
uid (Ruid
mod (Rmod
api (	Rapi"0
SharedDeployAS

servertype (R
servertype"N
SharedUpdateConfigFile
filename (	Rfilename
content (	Rcontent"
SharedHeartBeat"Ö
SS2ASSubCmdIDLoginState
srvid (Rsrvid
uid (Ruid
loginid (Rloginid
success (Rsuccess
maincmd (Rmaincmd
subcmd (Rsubcmd
data (Rdata
udid (	Rudid
	accountid	 (	R	accountid
gameid
 (	Rgameid"F
PBStoreOrderInfo
payway (Rpayway
payvalue (Rpayvalue"Â
PBUserAction
date (Rdate
uid (Ruid
action (Raction

createtime (R
createtime5
order (2.network.inter.PBStoreOrderInfoRorder
os (Ros
channel (Rchannel
gameid (Rgameid"H
PBUserActionReq5
actions (2.network.inter.PBUserActionRactions"‘

PBCoinData
date (Rdate
bets (Rbets
fee (Rfee
recycle (Rrecycle
robot (Rrobot
	robotbets (R	robotbets
robotfee (Rrobotfee"
robotrecycle	 (Rrobotrecycle"R
	PBCoinReq
gameid (Rgameid-
data (2.network.inter.PBCoinDataRdata"Ó
PBMoneyChanged
uid (Ruid
time (Rtime
logid (	Rlogid
gameid (Rgameid
svid (Rsvid
matchid (Rmatchid
roomid (Rroomid
type (Rtype
reason	 (Rreason
from
 (Rfrom
cto (Rcto
changed (Rchanged
remark (	Rremark
api (	Rapi
ip (	Rip
	extrainfo (	R	extrainfo"I
PBMoneyChangeReportReq/
mcs (2.network.inter.PBMoneyChangedRmcs"”
	PBRoomLog
uid (Ruid
time (Rtime
roomtype (Rroomtype
gameid (Rgameid
serverid (Rserverid
roomid (Rroomid

smallblind (R
smallblind
seconds (Rseconds
changed	 (Rchanged
roomname
 (	Rroomname
	gamecount (R	gamecount
matchid (Rmatchid
api (Rapi"B
PBRoomLogReportReq,
logs (2.network.inter.PBRoomLogRlogs"
PBCards
cards (Rcards"5
PBHandCards
uid (Ruid
cards (	Rcards"\
PBGameSeatInfo
sid (Rsid
uid (Ruid
name (	Rname
role (	Rrole"q
PBGameWinInfo
uid (Ruid
wintype (	Rwintype
profit (Rprofit
	extrainfo (	R	extrainfo"C
PBTexasBetsInfo
uid (Ruid
bv (Rbv
bt (	Rbt"Ö
PBTexasGameInfo
sb (Rsb
bb (Rbb

maxplayers (R
maxplayers

curplayers (R
curplayers
ante (Rante"€
PBDiscardInfo
uid (Ruid
discard (	Rdiscard 
discardtype (	Rdiscardtype
	handcards (	R	handcards
discards (	Rdiscards
draw (	Rdraw

mahjongcmd (	R
mahjongcmd4
	pongcards (2.network.inter.PBCardsR	pongcards6

mkongcards	 (2.network.inter.PBCardsR
mkongcards6

pkongcards
 (2.network.inter.PBCardsR
pkongcards6

akongcards (2.network.inter.PBCardsR
akongcards0
hucards (2.network.inter.PBCardsRhucards"Ø
PBLandlordGameInfo3
seats (2.network.inter.PBGameSeatInfoRseats8
	handcards (2.network.inter.PBHandCardsR	handcards8
commoncards (2.network.inter.PBCardsRcommoncards8
discards (2.network.inter.PBDiscardInfoRdiscards6
wininfo (2.network.inter.PBGameWinInfoRwininfo"Ù
PBMahjongGameInfo3
seats (2.network.inter.PBGameSeatInfoRseats8
	handcards (2.network.inter.PBHandCardsR	handcards8
discards (2.network.inter.PBDiscardInfoRdiscards6
wininfo (2.network.inter.PBGameWinInfoRwininfo"µ

PBGameInfo4
texas (2.network.inter.PBTexasGameInfoRtexas5
lord (2!.network.inter.PBLandlordGameInfoRlord:
mahjong (2 .network.inter.PBMahjongGameInfoRmahjong"å

PBAreaInfo
bettype (Rbettype
betvalue (Rbetvalue
profit (Rprofit

pureprofit (R
pureprofit
fee (Rfee"µ
PBJackPotInfo
id (Rid
jp (Rjp
	delta_add (RdeltaAdd
	delta_sub (RdeltaSub
uid (Ruid
username (	Rusername
	minichips (R	minichips"ﬂ
	PBGameLog
logid (	Rlogid
stime (Rstime
etime (Retime
gameid (Rgameid
serverid (Rserverid
matchid (Rmatchid
roomid (Rroomid
roomtype (Rroomtype
tag	 (Rtag,
jp
 (2.network.inter.PBJackPotInfoRjp,
cards (2.network.inter.PBCardsRcards
	cardstype (R	cardstype
wintypes (Rwintypes"
winpokertype (Rwinpokertype
totalbet (Rtotalbet 
totalprofit (Rtotalprofit/
areas (2.network.inter.PBAreaInfoRareas5
gameinfo (2.network.inter.PBGameInfoRgameinfo
	extrainfo (	R	extrainfo"B
PBGameLogReportReq,
logs (2.network.inter.PBGameLogRlogs"◊
PBTexasUserGameInfo$
inctotalhands (Rinctotalhands*
inctotalwinhands (Rinctotalwinhands0
incpreflopfoldhands (Rincpreflopfoldhands2
incpreflopraisehands (Rincpreflopraisehands2
incpreflopcheckhands (Rincpreflopcheckhands9
pre_bets (2.network.inter.PBTexasBetsInfoRpreBets;
	flop_bets (2.network.inter.PBTexasBetsInfoRflopBets;
	turn_bets (2.network.inter.PBTexasBetsInfoRturnBets=

river_bets	 (2.network.inter.PBTexasBetsInfoR	riverBets
	bestcards
 (R	bestcards$
bestcardstype (Rbestcardstype
	leftchips (R	leftchips"J
PBUserGameInfo8
texas (2".network.inter.PBTexasUserGameInfoRtexas"˜
	PBUserLog
uid (Ruid
logid (	Rlogid
stime (Rstime
etime (Retime
gameid (Rgameid
serverid (Rserverid
matchid (Rmatchid
roomid (Rroomid
role	 (Rrole
tid
 (Rtid
sid (Rsid
username (	Rusername
nickurl (	Rnickurl
cards (Rcards
	cardstype (R	cardstype
totalbet (Rtotalbet 
totalprofit (Rtotalprofit(
totalpureprofit (Rtotalpureprofit
totalfee (Rtotalfee/
areas (2.network.inter.PBAreaInfoRareas;
	ugameinfo (2.network.inter.PBUserGameInfoR	ugameinfo
	extrainfo (	R	extrainfo"B
PBUserLogReportReq,
logs (2.network.inter.PBUserLogRlogs"w
PBGameUserLog2
gamelog (2.network.inter.PBGameLogRgamelog2
userlog (2.network.inter.PBUserLogRuserlog"J
PBGameUserLogReportReq0
logs (2.network.inter.PBGameUserLogRlogs"
PBPushSigninNotify"€
PBStatisticJackpotUserWinning
matchid (Rmatchid
roomid (Rroomid
uid (Ruid
roomtype (Rroomtype
value (Rvalue
jp (Rjp
nickname (	Rnickname
wintype (Rwintype"S
PBJackPotData
id (Rid
value (Rvalue
	timestamp (R	timestamp"D
PBJackpotReqResp0
data (2.network.inter.PBJackPotDataRdata"+
PBStatisticOnlineNotify
uid (Ruid"ß
PBPlayHandReqResp
uid (Ruid
matchid (Rmatchid
roomid (Rroomid
roomtype (Rroomtype
gameid (Rgameid
playhand (Rplayhand"2
PBUserItemData
id (Rid
num (Rnum"å

PBUserData
money (Rmoney
diamond (Rdiamond
bank (Rbank
nickurl (	Rnickurl
level (Rlevel
viplv (Rviplv
name (	Rname3
items (2.network.inter.PBUserItemDataRitems
exp	 (Rexp
sex
 (Rsex'
addon_timestamp (RaddonTimestamp
coin (Rcoin
api (	Rapi
jp (Rjp
sid (	Rsid
userId (	RuserId"¥
PBQueryUserInfo
uid (Ruid
roomid (Rroomid
matchid (Rmatchid)
ud (2.network.inter.PBUserDataRud
jpid (Rjpid

carrybound (R
carrybound"2
PBUserAtomUpdateData
k (	Rk
v (	Rv"ü
PBUserAtomUpdate
uid (Ruid
matchid (Rmatchid
roomid (Rroomid
op (Rop7
data (2#.network.inter.PBUserAtomUpdateDataRdata"ï
PBPostMailReq
uid (Ruid
type (Rtype
title (	Rtitle
content (	Rcontent
deadline (Rdeadline
acid (Racid"‰
PBUserProfitUpdateData
uid (Ruid
deposit (Rdeposit
withdraw (Rwithdraw
reviews (Rreviews
profit (Rprofit
	needchips (R	needchips
	playchips (R	playchips
balance (Rbalance
rebated	 (Rrebated

leftrebate
 (R
leftrebate
mtime (Rmtime
peak (Rpeak

cresttimes (R
cresttimes 
troughtimes (Rtroughtimes
	isrecycle (R	isrecycle
maxwin (Rmaxwin
res (Rres
	leftchips (R	leftchips
	rebateadd (R	rebateadd
	rebatesub (R	rebatesub
ispvp (Rispvp
	resettime (R	resettime"¢
PBUserProfitResultData
uid (Ruid
chips (Rchips
betchips (Rbetchips
res (Rres
maxwin (Rmaxwin
debugstr (	Rdebugstr"~
Game2UserUpdateProfitInfo
ctx (Rctx9
data (2%.network.inter.PBUserProfitUpdateDataRdata
ispvp (Rispvp"≥
Game2UserProfitResultReqResp
ctx (Rctx
matchid (Rmatchid
roomid (Rroomid9
data (2%.network.inter.PBUserProfitResultDataRdata
ispvp (Rispvp"é
Game2UserQueryChargeInfo
uid (Ruid
matchid (Rmatchid
roomid (Rroomid
gameid (Rgameid
charge (Rcharge"√
PBTablePlayersEntry
gameid (Rgameid
roomtype (Rroomtype
tag (Rtag
serverid (Rserverid
matchid (Rmatchid
roomid (Rroomid
players (Rplayers"T
PBTablePlayersUpdate<
tpentry (2".network.inter.PBTablePlayersEntryRtpentry"d
PBUserAcidInfo
uid (Ruid
acid (Racid
api (	Rapi
serverid (Rserverid"E
PBUserAcidResp3
acids (2.network.inter.PBUserAcidInfoRacids"*
PBNotify2ASUserKickout
uid (Ruid"F
PBPushRedPoint
uid (Ruid
type (Rtype
id (	Rid"∞

PBTimerMsg

createtime (R
createtime
status (Rstatus
interval (Rinterval
	maxruncnt (R	maxruncnt
runcnt (Rruncnt
content (	Rcontent">
PBAddTimerMsg-
msgs (2.network.inter.PBTimerMsgRmsgs"/
PBDelTimerMsg

createtime (R
createtime"O
PBKickOutUser
uid (Ruid
username (	Rusername
msg (	Rmsg"o
PBPushMsgToUser
uid (Ruid
maincmd (Rmaincmd
subcmd (Rsubcmd
content (Rcontent"?
PBUpdateOnlines
robots (Rrobots
users (Rusers"|
PBTableApiPlayer
api (	Rapi
players (Rplayers 
viewplayers (Rviewplayers
roomtype (Rroomtype"^
PBPlayerApi
serverid (Rserverid3
apis (2.network.inter.PBTableApiPlayerRapis"1
PBNotifyGameSvrDown
serverid (Rserverid""

PBSynDBLog
dblog (	Rdblog"{
PBGlobalDBConfig&
money_rank_time (RmoneyRankTime(
profit_rank_time (RprofitRankTime
jp_val (RjpVal"Ä
PBTimeConfig
year (Ryear
mon (Rmon
mday (Rmday
hour (Rhour
min (Rmin
sec (Rsec"ä
PBGame2GameClientForward
uid (Ruid
linkid (Rlinkid
maincmd (Rmaincmd
subcmd (Rsubcmd
data (Rdata"a
PBGame2GameToolsForward
matchid (Rmatchid
roomid (Rroomid
jdata (	Rjdata"ï
PBGame2RobotNotifyCreateRobot
srvid (Rsrvid
roomid (Rroomid
matchid (Rmatchid
roomtype (Rroomtype
num (Rnum"_
PBRobotInfo
uid (Ruid
name (	Rname
nickurl (	Rnickurl
api (	Rapi"ë
PBRobot2GameCreateRobotResp
roomid (Rroomid
matchid (Rmatchid
num (Rnum.
data (2.network.inter.PBRobotInfoRdata"ï
PBGame2RobotNotifyRemoveRobot
srvid (Rsrvid
roomid (Rroomid
matchid (Rmatchid
roomtype (Rroomtype
uid (Ruid*É
ServerCmdType
ServerCmdType_SharedÄ˛
ServerCmdType_ForwardÄ¸
ServerCmdType_BroadcastÄ˙
ServerCmdType_ClientÄ¯*Ö
ServerMainCmdID
ServerMainCmdID_Shared
ServerMainCmdID_SS2AS
ServerMainCmdID_Game2Money
ServerMainCmdID_Game2AS
ServerMainCmdID_Game2Mutex"
ServerMainCmdID_Game2Statistic 
ServerMainCmdID_SS2Statistic!
ServerMainCmdID_Game2UserInfo
ServerMainCmdID_Notify2AS	$
 ServerMainCmdID_Statistic2Notify
 
ServermainCmdID_Tools2Notify"
ServerMainCmdID_Servers2Notify
ServerMainCmdID_Mutex2TList%
!ServerMainCmdID_Statistic2DBProxy#
ServerMainCmdID_Servers2DBProxy
ServerMainCmdID_PHP2Server
ServerMainCmdID_Game2TList
ServerMainCmdID_Game2Game
ServerMainCmdID_Game2Robot*Q
eBroadcastType
BroadcastType_ExceptUsers 
BroadcastType_SpecifiedUsers*Û
SharedSubCmdID!
SharedSubCmdID_RegisterServer
SharedSubCmdID_PlayerLogout
SharedSubCmdID_PlayerLogin
SharedSubCmdID_PlayerAcid
SharedSubCmdID_DeployAS#
SharedSubCmdID_UpdateConfigFile
SharedSubCmdID_HeartBeat*-
SS2ASSubCmdID
SS2ASSubCmdID_LoginState*È
Game2MoneySubCmd$
 Game2MoneySubCmd_MoneyAtomUpdate2
.Game2MoneySubCmd_MoneySingleWalletOperationReq!
Game2MoneySubCmd_ReportResult4
/Game2MoneySubCmd_MoneySingleWalletOperationRespÇ "
Game2MoneySubCmd_QueryUserInfo*0
Game2ASSubCmd
Game2ASSubCmd_SysAssignRoom*•
Game2MutexSubCmd
Game2MutexSubCmd_MutexCheck 
Game2MutexSubCmd_MutexRemove%
!Game2MutexSubCmd_MutexSynchronize+
'Game2MutexSubCmd_MutexPlazaNotification.
*Game2MutexSubCmd_MutexPlazaPlayerCountInfo1
-Game2MutexSubCmd_MutexPlazaCheckSeatStatusReq(
$Game2MutexSubCmd_MutexUserRoomIdxReq+
'Game2MutexSubCmd_MutexAllUserRoomIdxReq3
.Game2MutexSubCmd_MutexPlazaCheckSeatStatusRespÜ *
%Game2MutexSubCmd_MutexUserRoomIdxRespá -
(Game2MutexSubCmd_MutexAllUserRoomIdxRespà 0
+Game2MutexSubCmd_MutexUserMoneyUpdateNotifyÅ@*:
SS2StatisticSubCmd$
 SS2StatisticSubCmd_UserActionReq*¡
Game2StatisticSubCmd&
"Game2StatisticSubCmd_UserActionReq$
 Game2StatisticSubCmd_GameCoinReq(
$Game2StatisticSubCmd_MoneyChangedReq)
%Game2StatisticSubCmd_GameLogReportReq)
%Game2StatisticSubCmd_UserLogReportReq)
%Game2StatisticSubCmd_RoomLogReportReq-
)Game2StatisticSubCmd_GameUserLogReportReq*
&Game2StatisticSubCmd_TexasStatisticReq'
#Game2StatisticSubCmd_JackpotReqResp	,
'Game2StatisticSubCmd_TexasStatisticRespà ,
'Game2StatisticSubCmd_JackpotUserWinningâ &
!Game2StatisticSubCmd_OnlineNotifyä (
$Game2StatisticSubCmd_PlayHandReqResp*Â
STATISTIC_ACTION_TYPE
ACTION_TYPE_LOGIN
ACTION_TYPE_INTOROOM
ACTION_TYPE_CHARGE
ACTION_TYPE_WINGAME
ACTION_TYPE_LOSEGAME
ACTION_TYPE_BINDTEL
ACTION_TYPE_UPGRADELV
ACTION_TYPE_UPGRADEVIPLV*—
STATISTIC_PAYWAY_TYPE
STATISTIC_PAYWAY_APPSTORE
STATISTIC_PAYWAY_ALIPAY
STATISTIC_PAYWAY_WECHATPAY
STATISTIC_PAYWAY_YDPAY 
STATISTIC_PAYWAY_BEIFUBAOPAY
STATISTIC_PAYWAY_SULONGPAY*Á
KUCUN_CHANGE_TYPE
KUCUN_CHANGE_CHARGE
KUCUN_CHANGE_FIRSTCHARGE
KUCUN_CHANGE_ADMININC
KUCUN_CHANGE_ADMINDEC
KUCUN_CHANGE_ROBOTINC
KUCUN_CHANGE_ROBOTDEC
KUCUN_CHANGE_PROMOTEINC
KUCUN_CHANGE_GIFTBAG
KUCUN_CHANGE_REGISTER	
KUCUN_CHANGE_ALMS

KUCUN_CHANGE_SIGNIN
KUCUN_CHANGE_TASK
KUCUN_CHANGE_HONOR*â
MONEY_CHANGE_TYPE
MONEY_CHANGE_MONEY
MONEY_CHANGE_COIN
MONEY_CHANGE_TOOL
MONEY_CHANGE_VIP
MONEY_CHANGE_DIAMOND*¥	
MONEY_CHANGE_REASON
MONEY_CHANGE_TRAIN
MONEY_CHANGE_CHARGE
MONEY_CHANGE_TASK
MONEY_CHANGE_HONOR
MONEY_CHANGE_ALMS
MONEY_CHANGE_SIGNIN
MONEY_CHANGE_SIGNINBOX
MONEY_CHANGE_ACCOUNT
MONEY_CHANGE_ADMIN	
MONEY_CHANGE_REGISTER

MONEY_CHANGE_ROBOT
MONEY_CHANGE_BANK_SEND
MONEY_CHANGE_BANK_RECE
MONEY_CHANGE_BANK_IN
MONEY_CHANGE_BANK_OUT
MONEY_CHANGE_MALL
MONEY_CHANGE_BET
MONEY_CHANGE_BUYINCHIPS
MONEY_CHANGE_RETURNCHIPS
MONEY_CHANGE_INTERACTTOOL
MONEY_CHANGE_ADDTIME
MONEY_CHANGE_NEXTCARD
MONEY_CHANGE_SHOWCARD
MONEY_CHANGE_SETTLE
MONEY_CHANGE_COWBOY_BET
MONEY_CHANGE_COWBOY_SETTLE 
MONEY_CHANGE_DRAGONTIGER_BET#
MONEY_CHANGE_DRAGONTIGER_SETTLE
MONEY_CHANGE_ANDARBAHAR_BET"
MONEY_CHANGE_ANDARBAHAR_SETTLE
MONEY_CHANGE_TPBET_BET 
MONEY_CHANGE_TPBET_SETTLE!
MONEY_CHANGE_SLOT_BET"
MONEY_CHANGE_SLOT_SETTLE#
MONEY_CHANGE_DICE_BET$
MONEY_CHANGE_DICE_SETTLE%
MONEY_CHANGE_SEOTDAWAR_BET&!
MONEY_CHANGE_SEOTDAWAR_SETTLE'
MONEY_CHANGE_DICE6_BET(
MONEY_CHANGE_DICE6_SETTLE)
MONEY_CHANGE_WHEEL_SETTLE 
MONEY_CHANGE_WHEEL_BETÀ*r
USER_ROLE_TYPE
USER_ROLE_BANKER
USER_ROLE_TEXAS_SB
USER_ROLE_TEXAS_BB	
USER_ROLE_TEXAS_PLAYER
*á
Game2UserInfoSubCmd&
"Game2UserInfoSubCmd_UserAtomUpdate 
Game2UserInfoSubCmd_PostMail&
"Game2UserInfoSubCmd_JackpotReqResp(
$Game2UserInfoSubCmd_UpdateProfitInfo+
'Game2UserInfoSubCmd_ProfitResultReqResp'
#Game2UserInfoSubCmd_QueryChargeInfo*@
MAILBOX_TYPE
MAILBOX_TYPE_MAIL
MAILBOX_TYPE_ANNOUNCE*;
Game2TListSubCmd'
#Game2TListSubCmd_TablePlayersUpdate*
Notify2ASSubCmdID!
Notify2ASSubCmdID_UserAcidReq#
Notify2ASSubCmdID_UserAcidRespÅ "
Notify2ASSubCmdID_UserKickoutÅ@*Ô
Statistic2NotifySubCmdID)
%Statistic2NotifySubCmdID_PushRedPoint(
$Statistic2NotifySubCmdID_AddTimerMsg(
$Statistic2NotifySubCmdID_DelTimerMsg(
$Statistic2NotifySubCmdID_KickOutUser*
&Statistic2NotifySubCmdID_UpdateOnlines*A
Tools2NotifySubCmdID)
%Tools2NotifySubCmdID_PushSigninNotify*∂
Servers2NotifySubCmdID(
$Servers2NotifySubCmdID_PushMsgToUser$
 Servers2NotifySubCmdID_OnlineReq$
 Servers2NotifySubCmdID_PlayerApi&
!Servers2NotifySubCmdID_OnlineRespÇ *@
Mutex2TListSubCmdID)
%Mutex2TListSubCmdID_NotifyGameSvrDown*C
Statistic2DBProxySubCmdID&
"Statistic2DBProxySubCmdID_SynDBLog*d
Servers2DBProxySubCmdID#
Servers2DBProxySubCmdID_CRUDReq$
 Servers2DBProxySubCmdID_CRUDResp*\
Game2GameSubCmdID#
Game2GameSubCmdID_ClientForward"
Game2GameSubCmdID_ToolsForward*ª
Game2RobotSubCmdID(
$Game2RobotSubCmdID_NotifyCreateRobot)
%Game2RobotSubCmdID_NotifyCreateRobot2&
"Game2RobotSubCmdID_CreateRobotResp(
$Game2RobotSubCmdID_NotifyRemoveRobot