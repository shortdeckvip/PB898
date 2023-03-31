
Î
crash.protonetwork.cmdcommon.proto"U
PBCrashBetReq_C,
idx (2.network.cmd.RoomIndexDataRidx
value (Rvalue"h
PBCrashBetResp_S
code (Rcode
uid (Ruid
value (Rvalue
balance (Rbalance"E
PBCrashCancelBetReq_C,
idx (2.network.cmd.RoomIndexDataRidx"X
PBCrashCancelBetResp_S
code (Rcode
uid (Ruid
balance (Rbalance"R
PBCrashStopReq_C,
idx (2.network.cmd.RoomIndexDataRidx
uid (Ruid"…
PBCrashStopResp_S
code (Rcode
uid (Ruid
winTimes (RwinTimes
value (Rvalue
balance (Rbalance"0
PBCrashStateNotify
winTimes (RwinTimes"C
PBCrashHistoryReq_C,
idx (2.network.cmd.RoomIndexDataRidx"0
PBCrashHistoryResp_S
results (Rresults"}
PBCrashPlayerInfo
name (	Rname
uid (Ruid
bet (Rbet
winTimes (RwinTimes
money (Rmoney"F
PBCrashAllBetInfoReq_C,
idx (2.network.cmd.RoomIndexDataRidx"M
PBCrashAllBetInfoResp_S2
bets (2.network.cmd.PBCrashPlayerInfoRbets"E
PBCrashRoomStateReq_C,
idx (2.network.cmd.RoomIndexDataRidx"¤
PBCrashRoomStateResp_S
state (Rstate
start (Rstart
current (Rcurrent
leftTime (RleftTime(
currentWinTimes (RcurrentWinTimes"–
PBCrashData
state (Rstate
start (Rstart
current (Rcurrent
leftTime (RleftTime
roundid (Rroundid-
player (2.network.cmd.PBPlayerRplayer2
bets (2.network.cmd.PBCrashPlayerInfoRbets
logs (Rlogs 
configchips	 (Rconfigchips 
playerCount
 (RplayerCount(
currentWinTimes (RcurrentWinTimes&
autoStopConfig (RautoStopConfig"Ÿ
PBCrashIntoRoomResp_S
code (Rcode
gameid (Rgameid,
idx (2.network.cmd.RoomIndexDataRidx,
data (2.network.cmd.PBCrashDataRdata