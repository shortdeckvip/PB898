
ò

dice.protonetwork.cmdcommon.proto"É
PBDiceNotifyStart_N
t (Rt
roundid (Rroundid"
needclearlog (Rneedclearlog 
playerCount (RplayerCount"!
PBDiceNotifyBet_N
t (Rt"≥
PBDiceBetArea
bettype (Rbettype
betvalue (Rbetvalue$
userareatotal (Ruserareatotal
	areatotal (R	areatotal
iswin (Riswin
odds (Rodds"è
PBDiceBetData
uid (Ruid
	usertotal (R	usertotal4
areabet (2.network.cmd.PBDiceBetAreaRareabet
balance (Rbalance"n
PBDiceBetReq_C,
idx (2.network.cmd.RoomIndexDataRidx.
data (2.network.cmd.PBDiceBetDataRdata"U
PBDiceBetResp_S
code (Rcode.
data (2.network.cmd.PBDiceBetDataRdata"c
PBDiceTypeStatisticData
type (Rtype
hitcount (Rhitcount
lasthit (Rlasthit"M
PBDiceLogData
wintype (Rwintype"
winpokertype (Rwinpokertype"¨
PBDiceNotifyShow_N
cardnum (Rcardnum(
card (2.network.cmd.PBPokerRcard6
areainfo (2.network.cmd.PBDiceBetAreaRareainfo
winTimes (RwinTimes"ß
PBDiceNotifyFinish_N)
ranks (2.network.cmd.PBRankRranks,
log (2.network.cmd.PBDiceLogDataRlog6
sta (2$.network.cmd.PBDiceTypeStatisticDataRsta"K
PBDiceNotifyBettingInfo_N.
bets (2.network.cmd.PBDiceBetDataRbets"B
PBDiceHistoryReq_C,
idx (2.network.cmd.RoomIndexDataRidx"}
PBDiceHistoryResp_S.
logs (2.network.cmd.PBDiceLogDataRlogs6
sta (2$.network.cmd.PBDiceTypeStatisticDataRsta"E
PBDiceOnlineListReq_C,
idx (2.network.cmd.RoomIndexDataRidx"u
PBDiceOnlineList-
player (2.network.cmd.PBPlayerRplayer
wincnt (Rwincnt
totalbet (Rtotalbet"K
PBDiceOnlineListResp_S1
list (2.network.cmd.PBDiceOnlineListRlist"å

PBDiceData
state (Rstate
lefttime (Rlefttime
roundid (Rroundid
jackpot (Rjackpot-
player (2.network.cmd.PBPlayerRplayer-
seats (2.network.cmd.PBSeatInfoRseats.
logs (2.network.cmd.PBDiceLogDataRlogs6
sta (2$.network.cmd.PBDiceTypeStatisticDataRsta4
betdata	 (2.network.cmd.PBDiceBetDataRbetdata(
card
 (2.network.cmd.PBPokerRcard 
configchips (Rconfigchips
odds (Rodds 
playerCount (RplayerCount
winTimes (RwinTimes"ù
PBIntoDiceRoomResp_S
code (Rcode
gameid (Rgameid,
idx (2.network.cmd.RoomIndexDataRidx+
data (2.network.cmd.PBDiceDataRdata*é
EnumDiceState
EnumDiceState_Check
EnumDiceState_Start
EnumDiceState_Betting
EnumDiceState_Show
EnumDiceState_Finish*O
EnumDiceType
EnumDiceType_2_6
EnumDiceType_7
EnumDiceType_8_12