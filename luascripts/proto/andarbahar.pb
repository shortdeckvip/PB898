
Ì
andarbahar.protonetwork.cmdcommon.proto"‰
PBAndarBaharNotifyStart_N
t (Rt
roundid (Rroundid"
needclearlog (Rneedclearlog 
playerCount (RplayerCount"'
PBAndarBaharNotifyBet_N
t (Rt"¹
PBAndarBaharBetArea
bettype (Rbettype
betvalue (Rbetvalue$
userareatotal (Ruserareatotal
	areatotal (R	areatotal
iswin (Riswin
odds (Rodds"›
PBAndarBaharBetData
uid (Ruid
	usertotal (R	usertotal:
areabet (2 .network.cmd.PBAndarBaharBetAreaRareabet
balance (Rbalance"z
PBAndarBaharBetReq_C,
idx (2.network.cmd.RoomIndexDataRidx4
data (2 .network.cmd.PBAndarBaharBetDataRdata"a
PBAndarBaharBetResp_S
code (Rcode4
data (2 .network.cmd.PBAndarBaharBetDataRdata"i
PBAndarBaharTypeStatisticData
type (Rtype
hitcount (Rhitcount
lasthit (Rlasthit"S
PBAndarBaharLogData
wintype (Rwintype"
winpokertype (Rwinpokertype"œ
PBAndarBaharNotifyShow_N
cardnum (Rcardnum(
card (2.network.cmd.PBPokerRcard<
areainfo (2 .network.cmd.PBAndarBaharBetAreaRareainfo"¹
PBAndarBaharNotifyFinish_N)
ranks (2.network.cmd.PBRankRranks2
log (2 .network.cmd.PBAndarBaharLogDataRlog<
sta (2*.network.cmd.PBAndarBaharTypeStatisticDataRsta"W
PBAndarBaharNotifyBettingInfo_N4
bets (2 .network.cmd.PBAndarBaharBetDataRbets"H
PBAndarBaharHistoryReq_C,
idx (2.network.cmd.RoomIndexDataRidx"
PBAndarBaharHistoryResp_S4
logs (2 .network.cmd.PBAndarBaharLogDataRlogs<
sta (2*.network.cmd.PBAndarBaharTypeStatisticDataRsta"K
PBAndarBaharOnlineListReq_C,
idx (2.network.cmd.RoomIndexDataRidx"{
PBAndarBaharOnlineList-
player (2.network.cmd.PBPlayerRplayer
wincnt (Rwincnt
totalbet (Rtotalbet"W
PBAndarBaharOnlineListResp_S7
list (2#.network.cmd.PBAndarBaharOnlineListRlist"ˆ
PBAndarBaharData
state (Rstate
lefttime (Rlefttime
roundid (Rroundid
jackpot (Rjackpot-
player (2.network.cmd.PBPlayerRplayer-
seats (2.network.cmd.PBSeatInfoRseats4
logs (2 .network.cmd.PBAndarBaharLogDataRlogs<
sta (2*.network.cmd.PBAndarBaharTypeStatisticDataRsta:
betdata	 (2 .network.cmd.PBAndarBaharBetDataRbetdata(
card
 (2.network.cmd.PBPokerRcard 
configchips (Rconfigchips
odds (Rodds 
playerCount (RplayerCount"©
PBIntoAndarBaharRoomResp_S
code (Rcode
gameid (Rgameid,
idx (2.network.cmd.RoomIndexDataRidx1
data (2.network.cmd.PBAndarBaharDataRdata*²
EnumAndarBaharState
EnumAndarBaharState_Check
EnumAndarBaharState_Start
EnumAndarBaharState_Betting
EnumAndarBaharState_Show
EnumAndarBaharState_Finish*P
EnumAndarBaharType
EnumAndarBaharType_Andar
EnumAndarBaharType_Bahar