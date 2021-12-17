
íS
userinfo.protonetwork.cmd"6
PBUserInfoSetNickNameReq
nickname (	Rnickname"/
PBUserInfoSetNickNameResp
code (Rcode"9
PBUserInfoSetIntroduceReq
	introduce (	R	introduce"0
PBUserInfoSetIntroduceResp
code (Rcode"
PBUserInfoSetAvatarReq"3
PBUserInfoSetAvatarResp
nickurl (	Rnickurl",
PBUserInfoBankDepositReq
val (Rval"Y
PBUserInfoBankDepositResp
money (Rmoney
bank (Rbank
code (Rcode"E
PBUserInfoBankWithdrawReq
val (Rval
passwd (	Rpasswd"Z
PBUserInfoBankWithdrawResp
money (Rmoney
bank (Rbank
code (Rcode"O
PBUserInfoBankSetPasswdReq
passwd (	Rpasswd
passwd_s (	RpasswdS"1
PBUserInfoBankSetPasswdResp
code (Rcode"
PBUserInfoBankHistoryReq"o
PBUserInfoBankHistoryData
optime (Roptime
op (Rop
val (Rval
leftval (Rleftval"k
PBUserInfoBankHistoryResp
code (Rcode:
data (2&.network.cmd.PBUserInfoBankHistoryDataRdata")
PBUserInfoSigninReq
time (Rtime"R
PBUserInfoSigninResp
code (Rcode
money (Rmoney
pic (	Rpic"-
PBUserInfoSigninListReq
time (Rtime"R
PBUserInfoSequenceData
money (Rmoney
pic (	Rpic
exp (Rexp"{
PBUserInfoBoxData
money (Rmoney
pic (	Rpic
state (Rstate
days (Rdays
viplv (Rviplv"á
PBUserInfoSigninListResp
code (Rcode
sequence (Rsequence5
seq (2#.network.cmd.PBUserInfoSequenceDataRseq
total (Rtotal
hasget (Rhasget0
box (2.network.cmd.PBUserInfoBoxDataRbox"%
PBUserInfoGetBoxReq
id (Rid"R
PBUserInfoGetBoxResp
code (Rcode
money (Rmoney
pic (	Rpic"³
PBUserInfoQuestData
id (Rid
pic (	Rpic
money (Rmoney
val (Rval
maxv (Rmaxv
title (	Rtitle
desc (	Rdesc
state (Rstate"³
PBUserInfoHonorData
id (Rid
pic (	Rpic
money (Rmoney
val (Rval
maxv (Rmaxv
title (	Rtitle
desc (	Rdesc
state (Rstate"|
PBMailBoxListReq
uid (Ruid
type (Rtype
page (Rpage
pagesize (Rpagesize
time (Rtime"Ž

PBMailInfo
uid (Ruid
title (	Rtitle
time (Rtime
content (	Rcontent
unread (Runread
type (Rtype"j
PBMailBoxListResp
page (Rpage-
infos (2.network.cmd.PBMailInfoRinfos
time (Rtime"G
PBMailIndex
uid (Ruid
time (Rtime
type (Rtype"=
PBMailReadReq,
mail (2.network.cmd.PBMailIndexRmail"d
PBMailReadResp,
mail (2.network.cmd.PBMailIndexRmail
code (Rcode
msg (	Rmsg"A
PBMailRemoveReq.
mails (2.network.cmd.PBMailIndexRmails"h
PBMailRemoveResp.
mails (2.network.cmd.PBMailIndexRmails
code (Rcode
msg (	Rmsg"-
PBUserQuestHonorListReq
time (Rtime"ž
PBUserQuestHonorListResp
code (Rcode6
quest (2 .network.cmd.PBUserInfoQuestDataRquest6
honor (2 .network.cmd.PBUserInfoHonorDataRhonor")
PBUserQuestGetRewardReq
id (Rid"f
PBUserQuestGetRewardResp
id (Rid
code (Rcode
money (Rmoney
pic (	Rpic")
PBUserHonorGetRewardReq
id (Rid"f
PBUserHonorGetRewardResp
id (Rid
code (Rcode
money (Rmoney
pic (	Rpic")
PBUserGetGiftBagReq
code (	Rcode"¢
PBUserGetGiftBagResp
code (Rcode
money (Rmoney
pic (	Rpic
diamond (Rdiamond
trumpet (Rtrumpet
duelcard (Rduelcard"X
PBUserInfoAlmsData
money (Rmoney
num (Rnum
minmoney (Rminmoney"
PBUserGetAlmsReq"y
PBUserGetAlmsResp
code (Rcode
money (Rmoney
num (Rnum
maxnum (Rmaxnum
pic (	Rpic":
PBUserNotifyRedPoint
type (Rtype
id (	Rid"
PBUserGetRedPointReq"N
PBUserGetRedPointResp5
data (2!.network.cmd.PBUserNotifyRedPointRdata"+
PBUserGetFreeCoinsReq
time (Rtime"N
PBUserGetFreeCoinsResp
alms_min (RalmsMin
alms_max (RalmsMax"´
PBUserRankData
nickurl (	Rnickurl
name (	Rname
money (Rmoney
	introduce (	R	introduce
uid (Ruid
level (Rlevel
diamond (Rdiamond"
PBUserGetMoneyRankReq"g
PBUserGetMoneyRankResp/
data (2.network.cmd.PBUserRankDataRdata
	cachetime (R	cachetime"
PBUserGetProfitRankReq"h
PBUserGetProfitRankResp/
data (2.network.cmd.PBUserRankDataRdata
	cachetime (R	cachetime"/
PBUserNotifyVipLvUpdate
viplv (Rviplv"/
PBUserNotifyLevelUpdate
level (Rlevel"6
PBUserUpdateNickPicReq
	imageName (	R	imageName"3
PBUserUpdateNickPicResp
nickurl (	Rnickurl"/
PBUserUpdateGenderReq
gender (Rgender"0
PBUserUpdateGenderResp
gender (Rgender"?
PBUserVipConfigData
money (Rmoney
days (Rdays"<
PBVipPrivilegeData
isnew (Risnew
dec (	Rdec"_
PBVipPrivilegeInfo
viplv (Rviplv3
data (2.network.cmd.PBVipPrivilegeDataRdata"
PBUserVipInfoReq"Ž
PBUserVipInfoResp
viplv (Rviplv
val (Rval
levelval (Rlevelval5
infos (2.network.cmd.PBVipPrivilegeInfoRinfos"8
PBJPInfo
	timestamp (R	timestamp
jp (Rjp"

PBGetJPReq"8
PBGetJPResp)
info (2.network.cmd.PBJPInfoRinfo"
PBGetBackpackInfoReq"f

PBToolInfo
id (Rid
name (	Rname
num (Rnum
dec (	Rdec
pic (	Rpic"F
PBGetBackpackInfoResp-
tools (2.network.cmd.PBToolInfoRtools"
PBOpenInteractToolReq"[
PBOpenInteractToolResp
code (Rcode-
tools (2.network.cmd.PBToolInfoRtools"–
PBToolPackageInfo
toolid (Rtoolid
state (Rstate
id (Rid
price (Rprice-
tools (2.network.cmd.PBToolInfoRtools"]
PBNotifyToolPackageInfoB
packageInfos (2.network.cmd.PBToolPackageInfoRpackageInfos"[
PBNotifyOpenToolPackage@
packageInfo (2.network.cmd.PBToolPackageInfoRpackageInfo"C
PBNotifyItemUpdate-
tools (2.network.cmd.PBToolInfoRtools"
PBUserInfoTurntableGetInfoReq"K
PBUserInfoTurntableRankRecord
name (	Rname
itemid (Ritemid"Â
PBUserInfoTurntableGetInfoResp
leftnum (RleftnumF
luckiest (2*.network.cmd.PBUserInfoTurntableRankRecordRluckiest>
rank (2*.network.cmd.PBUserInfoTurntableRankRecordRrank"
PBUserInfoTurntableLotteryReq"x
PBUserInfoTurntableLotteryResp
code (Rcode
item (Ritem
leftnum (Rleftnum
bonus (Rbonus">
PBUserInfoTurntableNotifyIncNum
	num_delta (RnumDelta"
PBUserInfoPromoterGetInfoReq"Æ
PBUserInfoPromoterGetInfoResp
name (	Rname
my_code (	RmyCode
pig (Rpig
weight (Rweight
state (Rstate
	min_times (RminTimes
	max_times (RmaxTimes".
PBUserInfoPromoterSetReq
code (	Rcode"C
PBUserInfoPromoterSetResp
code (Rcode
name (	Rname" 
PBUserInfoPromoterMyPartnerReq"s
PromoterMyPartnerRecord
name (	Rname
level (Rlevel
vit (Rvit
	timestamp (R	timestamp"[
PBUserInfoPromoterMyPartnerResp8
data (2$.network.cmd.PromoterMyPartnerRecordRdata"$
"PBUserInfoPromoterAwardsHistoryReq"`
PBPromoterAwardsRecord
type (Rtype
bonus (Rbonus
	timestamp (R	timestamp"^
#PBUserInfoPromoterAwardsHistoryResp7
data (2#.network.cmd.PBPromoterAwardsRecordRdata"%
#PBUserInfoPromoterWinningDetailsReq"u
PBPromoterWinningRecord
name (	Rname
level (Rlevel
degree (Rdegree
nickurl (	Rnickurl"v
$PBUserInfoPromoterWinningDetailsResp
bonus (Rbonus8
data (2$.network.cmd.PBPromoterWinningRecordRdata"
PBUserInfoPromoterGetPigReq"v
PBUserInfoPromoterGetPigResp
code (Rcode
multi (Rmulti
bonus (Rbonus
weight (Rweight"3
PBUserInfoPromoterReferrerReq
code (	Rcode"H
PBUserInfoPromoterReferrerResp
code (Rcode
name (	Rname"(
PBUserPhoneBillReq
type (Rtype"‘
PBPhoneBillShopData
id (Rid
name (	Rname
tickets (Rtickets
money (Rmoney
num (Rnum
state (Rstate"j
PBPhoneBillQuestData
id (Rid
name (	Rname
tickets (Rtickets
state (Rstate"`
PBPhoneBillHistoryData
name (	Rname
	timestamp (R	timestamp
state (Rstate"ü
PBUserPhoneBillResp
type (Rtype#
total_tickets (RtotalTickets4
shop (2 .network.cmd.PBPhoneBillShopDataRshop7
quest (2!.network.cmd.PBPhoneBillQuestDataRquest=
history (2#.network.cmd.PBPhoneBillHistoryDataRhistory"-
PBUserPhoneBillGetTicketReq
id (Rid"Ž
PBUserPhoneBillGetTicketResp
code (Rcode!
left_tickets (RleftTickets7
quest (2!.network.cmd.PBPhoneBillQuestDataRquest",
PBUserPhoneBillExchangeReq
id (Rid"T
PBUserPhoneBillExchangeResp
code (Rcode!
left_tickets (RleftTickets"v
PBUserNotifyUserInfo
mname (	Rmname
micon (	Rmicon
mgender (Rmgender
ismnick (Rismnick"
PBGetUserMoneyReq"X
PBGetUserMoneyResp
money (Rmoney
diamond (Rdiamond
coin (Rcoin",
PBUserWXGetUserInfoReq
info (	Rinfo*[
PBUserInfoBankOpType 
PBUserInfoBankOpType_Deposit!
PBUserInfoBankOpType_Withdraw*l
QUESTHONOR_STATE
QUESTHONOR_STATE_INCOMPLETE 
QUESTHONOR_STATE_COMPLETE
QUESTHONOR_STATE_GOT*ù
PBUserRedPointType
PBUserRedPointType_Signin
PBUserRedPointType_Quest
PBUserRedPointType_Honor"
PBUserRedPointType_System_Mail"
PBUserRedPointType_Notice_Mail
PBUserRedPointType_Alms
PBUserRedPointType_Giftbag 
PBUserRedPointType_Promation
PBUserRedPointType_Rank	"
PBUserRedPointType_PhoneTicket
 
PBUserRedPointType_Turntable*c
ToolID
ToolID_Tomato
ToolID_Bomb
ToolID_Chicken
ToolID_Water
ToolID_Rose*O
PBToolPackageState
PBToolPackageState_NotBuy
PBToolPackageState_Buy*»
PBUserInfoTurntableCountType%
!PBUserInfoTurntableCountType_Free"
PBUserInfoTurntableCountType_6&
"PBUserInfoTurntableCountType_6t200(
$PBUserInfoTurntableCountType_200t500*©
PBUserInfoTurntableItem
PBUserInfoTurntableItem_888 
PBUserInfoTurntableItem_1888 
PBUserInfoTurntableItem_8888!
PBUserInfoTurntableItem_1p88w 
PBUserInfoTurntableItem_8p8w
PBUserInfoTurntableItem_88w 
PBUserInfoTurntableItem_888w!
PBUserInfoTurntableItem_8888w*e
PBUserInfoPromoterPigType"
PBUserInfoPromoterPigType_Gold$
 PBUserInfoPromoterPigType_Silver*[
PhoneBillType
PhoneBillType_Shop
PhoneBillType_Quest
PhoneBillType_History