
ß

game.protonetwork.cmdcommon.proto".
PBGameMatchListReq_C
gameid (Rgameid"a
PBGameMatchListResp_S
gameid (Rgameid0
data (2.network.cmd.PBGameMatchListRdata"≥
PBIntoGameRoomReq_C
gameid (Rgameid
matchid (Rmatchid
passwd (	Rpasswd
roomid (Rroomid
serverid (Rserverid
money (Rmoney
width (Rwidth
high (Rhigh
ip	 (	Rip
mac
 (	Rmac
api (	Rapi
mobile (Rmobile
ante (Rante"ä
PBIntoGameRoomResp_S
code (Rcode
gameid (Rgameid,
idx (2.network.cmd.RoomIndexDataRidx
maxuser (Rmaxuser"B
PBChangeGameRoom_C,
idx (2.network.cmd.RoomIndexDataRidx"(
PBChangeGameRoom_S
code (Rcode"\
PBLeaveGameRoomReq_C,
idx (2.network.cmd.RoomIndexDataRidx
opcode (Ropcode"è
PBLeaveGameRoomResp_S
code (Rcode
hands (Rhands
profits (Rprofits
roomtype (Rroomtype
gameid (Rgameid"-
PBNotifyGameMoneyUpdate_N
val (Rval",
PBNotifyGameCoinUpdate_N
val (Rval"/
PBNotifyGameDiamondUpdate_N
val (Rval")
PBNotifyGameChips_N
code (Rcode"P
PBGameSitReq_C,
idx (2.network.cmd.RoomIndexDataRidx
pos (Rpos"%
PBGameSitResp_S
code (Rcode"D
PBGameSeatsInfoReq_C,
idx (2.network.cmd.RoomIndexDataRidx"D
PBGameUpdateSeats_N-
seats (2.network.cmd.PBSeatInfoRseats"\
PBUpdateUserVipLevel_C,
idx (2.network.cmd.RoomIndexDataRidx
viplv (Rviplv"B
PBGameNotifyVipLevelUp_N
uid (Ruid
viplv (Rviplv"?
PBGameInfoReq_C,
idx (2.network.cmd.RoomIndexDataRidx"≤
PBGameKickPlayer_N
gameName (	RgameName
limit (Rlimit
gameid (Rgameid
	userMoney (R	userMoney
code (Rcode 
userDiamond (RuserDiamond"m
PBGameChatReq_C,
idx (2.network.cmd.RoomIndexDataRidx
type (Rtype
content (	Rcontent"T
PBGameNotifyChat_N
sid (Rsid
type (Rtype
content (	Rcontent"ã
PBGameToolSendReq_C,
idx (2.network.cmd.RoomIndexDataRidx
fromsid (Rfromsid
tosid (Rtosid
toolID (RtoolID"\
PBGameToolSendResp_S
code (Rcode
toolID (RtoolID
leftNum (RleftNum"z
PBGameNotifyTool_N
fromsid (Rfromsid
tosid (Rtosid
toolID (RtoolID
	seatMoney (R	seatMoney"o
PBUpdateRobotMoneyReq_S
uid (Ruid
money (Rmoney
diamond (Rdiamond
coin (Rcoin".
PBUpdateRobotMoneyResp_S
code (Rcode"j
PBFollowTableReq_C,
idx (2.network.cmd.RoomIndexDataRidx&
targetusername (	Rtargetusername")
PBFollowTableResp_S
code (Rcode"1
PBGameNotifyJackPot_N
jackpot (Rjackpot"N
PBGameJackpotAnimation_N2
data (2.network.cmd.PBGameJackpotDataRdata"N
PBGameOpBank_C,
idx (2.network.cmd.RoomIndexDataRidx
op (Rop"i
PBGameOpBank_S
op (Rop
code (Rcode3
list (2.network.cmd.PBGameBankUserDataRlist"+
PBGameNotifyOnBankCnt_N
cnt (Rcnt"æ
PBServerSynGame2ASAssignRoom
uid (Ruid
srvid (Rsrvid
roomid (Rroomid
matchid (Rmatchid
maincmd (Rmaincmd
subcmd (Rsubcmd
data (Rdata*É
PBKickCodeType
PBKickCodeType_NoMoney
PBKickCodeType_LongTime
PBKickCodeType_NoDiamond
PBKickCodeType_Dismiss*]
PBGameChatType
PBGameChatType_Emoji
PBGameChatType_Text
PBGameChatType_Voice