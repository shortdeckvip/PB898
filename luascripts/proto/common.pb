
?#
common.protonetwork.cmd"?
RoomIndexData
srvid (Rsrvid
roomid (Rroomid
matchid (Rmatchid
passwd (	Rpasswd
roomtype (Rroomtype"K
PBPlayerExtra
api (	Rapi
ip (	Rip
platuid (	Rplatuid"?
PBPlayer
uid (Ruid
nickname (	Rnickname
username (	Rusername
viplv (Rviplv
nickurl (	Rnickurl
gender (Rgender
balance (Rbalance
currency (	Rcurrency0
extra	 (2.network.cmd.PBPlayerExtraRextra"g

PBSeatInfo
sid (Rsid
tid (Rtid5

playerinfo (2.network.cmd.PBPlayerR
playerinfo"5
PBPoker
color (Rcolor
count (Rcount"?
	PBBetArea
bettype (Rbettype
betvalue (Rbetvalue$
userareatotal (Ruserareatotal
	areatotal (R	areatotal
iswin (Riswin
odds (Rodds
profit (Rprofit

pureprofit (R
pureprofit
fee	 (Rfee"?
PBRank
uid (Ruid
rank (Rrank 
totalprofit (Rtotalprofit,
areas (2.network.cmd.PBBetAreaRareas-
player (2.network.cmd.PBPlayerRplayer"7
	PBContext
seq (Rseq
content (	Rcontent"?
PBChannelData
channel (Rchannel
appid (	Rappid
secret (	Rsecret
mchid (	Rmchid
paykey (	Rpaykey
packname (	Rpackname
aliappid (	Raliappid"?
PBGameMatchData
serverid (Rserverid
matchid (Rmatchid
minchips (Rminchips
online (Ronline
state (Rstate
name (	Rname"C
PBGameMatchList0
data (2.network.cmd.PBGameMatchDataRdata"v
PBGameBankUserData
uid (Ruid
nickurl (	Rnickurl
nickname (	Rnickname
balance (Rbalance"?
PBGameBankData7
banker (2.network.cmd.PBGameBankUserDataRbanker)
onbank_minimoney (RonbankMinimoney%
successive_cnt (RsuccessiveCnt#
banklist_size (RbanklistSize"
is_going_down (RisGoingDown,
successive_max_cnt (RsuccessiveMaxCnt$
onbank_max_cnt (RonbankMaxCnt+
outbank_minimoney (RoutbankMinimoney"g
PBGameJackpotData
sid (Rsid
uid (Ruid
delta (Rdelta
wintype (Rwintype*?
EnumPokerColor
EnumPokerColor_Diamond
EnumPokerColor_Club
EnumPokerColor_Heart
EnumPokerColor_Spade
EnumPokerColor_JOKER*?
EnumPokerCount
EnumPokerCount_2
EnumPokerCount_3
EnumPokerCount_4
EnumPokerCount_5
EnumPokerCount_6
EnumPokerCount_7
EnumPokerCount_8
EnumPokerCount_9	
EnumPokerCount_T

EnumPokerCount_J
EnumPokerCount_Q
EnumPokerCount_K
EnumPokerCount_A
EnumPokerCount_JOKER1
EnumPokerCount_JOKER2*7

PBRoomType
PBRoomType_Money
PBRoomType_Coin*g
PBGameMatchState
PBGameMatchState_Idle
PBGameMatchState_Hot
PBGameMatchState_Recommend*?
PBBankOperatorType
PBBankOperatorType_OnBank!
PBBankOperatorType_CancelBank
PBBankOperatorType_OutBank
PBBankOperatorType_BankList*?
PBBankOperatorCode
PBBankOperatorCode_Success #
PBBankOperatorCode_OverListSize%
!PBBankOperatorCode_NotEnoughMoney$
 PBBankOperatorCode_HasOnBankList 
PBBankOperatorCode_HasOnBank
PBBankOperatorCode_Failed*?
PBLoginCommonErrorCode!
PBLoginErrorCode_LoginSuccess 
PBLoginErrorCode_LoginFailed 
PBLoginErrorCode_BindSuccess
PBLoginErrorCode_VerifyCode#
PBLoginErrorCode_NoAccountOrPwd 
PBLoginErrorCode_TokenExpire"
PBLoginErrorCode_LogoutSuccess$
 PBLoginErrorCode_IntoGameSuccess!
PBLoginErrorCode_IntoGameFail	%
!PBLoginErrorCode_LeaveGameSuccess$
 PBLoginErrorCode_LeaveGameFailed
PBLoginErrorCode_SameIp"
PBLoginErrorCode_BuyinOverTime+
'PBLoginErrorCode_AccountReconnectRepeat 
PBLoginErrorCode_OverMaxInto
PBLoginErrorCode_Success%
PBLoginErrorCode_Fail& 
PBLoginErrorCode_WrongRoomid**?
PBFollowTableCommonErrorCode%
!PBFollowTableCommonErrorCode_Succ %
!PBFollowTableCommonErrorCode_Fail0
,PBFollowTableCommonErrorCode_TargetTableFull/
+PBFollowTableCommonErrorCode_UserBetOnRound.
*PBFollowTableCommonErrorCode_InTargetTable*
&PBFollowTableCommonErrorCode_UserLeave*?
EnumBetErrorCode
EnumBetErrorCode_Succ 
EnumBetErrorCode_Fail 
EnumBetErrorCode_InvalidUser%
!EnumBetErrorCode_InvalidGameState*
&EnumBetErrorCode_InvalidBetTypeOrValue
EnumBetErrorCode_OverLimits 
EnumBetErrorCode_OverBalance
EnumBetErrorCode_IsBanker*4
EnumMsgTipsCode!
EnumMsgTipsCode_InvalidAmount