
∆
dragontiger.protonetwork.cmdcommon.proto"ª
PBDragonTigerNotifyStart_N
t (Rt
roundid (Rroundid"
needclearlog (Rneedclearlog/
bank (2.network.cmd.PBGameBankDataRbank 
playerCount (RplayerCount"(
PBDragonTigerNotifyBet_N
t (Rt"∫
PBDragonTigerBetArea
bettype (Rbettype
betvalue (Rbetvalue$
userareatotal (Ruserareatotal
	areatotal (R	areatotal
iswin (Riswin
odds (Rodds"ù
PBDragonTigerBetData
uid (Ruid
	usertotal (R	usertotal;
areabet (2!.network.cmd.PBDragonTigerBetAreaRareabet
balance (Rbalance"|
PBDragonTigerBetReq_C,
idx (2.network.cmd.RoomIndexDataRidx5
data (2!.network.cmd.PBDragonTigerBetDataRdata"c
PBDragonTigerBetResp_S
code (Rcode5
data (2!.network.cmd.PBDragonTigerBetDataRdata"j
PBDragonTigerTypeStatisticData
type (Rtype
hitcount (Rhitcount
lasthit (Rlasthit"0
PBDragonTigerLogData
wintype (Rwintype"¥
PBDragonTigerNotifyShow_N,
dragon (2.network.cmd.PBPokerRdragon*
tiger (2.network.cmd.PBPokerRtiger=
areainfo (2!.network.cmd.PBDragonTigerBetAreaRareainfo"È
PBDragonTigerNotifyFinish_N)
ranks (2.network.cmd.PBRankRranks3
log (2!.network.cmd.PBDragonTigerLogDataRlog=
sta (2+.network.cmd.PBDragonTigerTypeStatisticDataRsta+
banker (2.network.cmd.PBRankRbanker"Y
 PBDragonTigerNotifyBettingInfo_N5
bets (2!.network.cmd.PBDragonTigerBetDataRbets"I
PBDragonTigerHistoryReq_C,
idx (2.network.cmd.RoomIndexDataRidx"í
PBDragonTigerHistoryResp_S5
logs (2!.network.cmd.PBDragonTigerLogDataRlogs=
sta (2+.network.cmd.PBDragonTigerTypeStatisticDataRsta"L
PBDragonTigerOnlineListReq_C,
idx (2.network.cmd.RoomIndexDataRidx"|
PBDragonTigerOnlineList-
player (2.network.cmd.PBPlayerRplayer
wincnt (Rwincnt
totalbet (Rtotalbet"Y
PBDragonTigerOnlineListResp_S8
list (2$.network.cmd.PBDragonTigerOnlineListRlist"Ì
PBDragonTigerData
state (Rstate
lefttime (Rlefttime
roundid (Rroundid
jackpot (Rjackpot-
player (2.network.cmd.PBPlayerRplayer-
seats (2.network.cmd.PBSeatInfoRseats5
logs (2!.network.cmd.PBDragonTigerLogDataRlogs=
sta (2+.network.cmd.PBDragonTigerTypeStatisticDataRsta;
betdata	 (2!.network.cmd.PBDragonTigerBetDataRbetdata,
dragon
 (2.network.cmd.PBPokerRdragon*
tiger (2.network.cmd.PBPokerRtiger/
bank (2.network.cmd.PBGameBankDataRbank 
configchips (Rconfigchips
odds (Rodds 
playerCount (RplayerCount"´
PBIntoDragonTigerRoomResp_S
code (Rcode
gameid (Rgameid,
idx (2.network.cmd.RoomIndexDataRidx2
data (2.network.cmd.PBDragonTigerDataRdata*∏
EnumDragonTigerState
EnumDragonTigerState_Check
EnumDragonTigerState_Start 
EnumDragonTigerState_Betting
EnumDragonTigerState_Show
EnumDragonTigerState_Finish*r
EnumDragonTigerType
EnumDragonTigerType_Dragon
EnumDragonTigerType_Tiger
EnumDragonTigerType_Draw