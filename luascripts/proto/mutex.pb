
≥
mutex.protonetwork.cmdcommon.proto"ò
PBMutexCheck
uid (Ruid
srvid (Rsrvid
matchid (Rmatchid
roomid (Rroomid
code (Rcode
roomtype (Rroomtype"e
PBMutexRemove
uid (Ruid
srvid (Rsrvid
roomid (Rroomid
cache (Rcache"o
PBMutexUserRoomData
mid (Rmid
roomid (Rroomid
roomtype (Rroomtype
uids (Ruids"d
PBMutexDataSynchronize
srvid (Rsrvid4
data (2 .network.cmd.PBMutexUserRoomDataRdata"
PBMutexUserRoomInfosReq"≠
PBMutexUserRoomInfoData
srvid (Rsrvid
matchid (Rmatchid
roomid (Rroomid
gameid (Rgameid
passwd (	Rpasswd
roomtype (Rroomtype"V
PBMutexUserRoomInfosResp:
infos (2$.network.cmd.PBMutexUserRoomInfoDataRinfos"‰
PBMutexPlazaNotification

notifytype (R
notifytype
	loginname (	R	loginname
nickname (	Rnickname
gametype (	Rgametype
vid (	Rvid
seatnum (Rseatnum"
jackpotlevel (Rjackpotlevel
sequence (Rsequence

resulttype	 (	R
resulttype
amount
 (Ramount
icon (Ricon
currency (	Rcurrency"ï
PBMutexPlazaPlayerCountInfo
gametype (	Rgametype
serverid (Rserverid
	servervid (	R	servervid 
playercount (Rplayercount"ê
PBMutexPlazaCheckSeatStatusReq
	servervid (	R	servervid&
targetusername (	Rtargetusername(
requestusername (	Rrequestusername"ó
PBMutexPlazaCheckSeatStatusResp(
requestusername (	Rrequestusername&
targetusername (	Rtargetusername"
isAbleFollow (RisAbleFollow"⁄
PBMutexUserMoneyUpdateNotify
mid (Rmid
roomid (Rroomid
roomtype (Rroomtype
uid (Ruid
money (Rmoney
coin (Rcoin
	bankmoney (R	bankmoney
bankcoin (Rbankcoin"
PBMutexAllUsersRoomInfosReq"d
PBMutexAllUserRoomInfoData,
idx (2.network.cmd.RoomIndexDataRidx
uidlist (Ruidlist"
PBMutexAllUsersRoomInfosRespA
idxlist (2'.network.cmd.PBMutexAllUserRoomInfoDataRidxlist
	srvidlist (R	srvidlist