
ü#
qiuqiu.protonetwork.cmdcommon.proto"Ù
PBQiuQiuSeat+
seat (2.network.cmd.PBSeatInfoRseat
	isPlaying (R	isPlaying
	seatMoney (R	seatMoney 
chipinMoney (RchipinMoney

chipinType (R
chipinType
	chipinNum (R	chipinNum
needCall (RneedCall
	needRaise (R	needRaise"
needMaxRaise	 (RneedMaxRaise

chipinTime
 (R
chipinTime
	handcards (R	handcards
onePot (RonePot 
reserveSeat (RreserveSeat
	totalTime (R	totalTime 
addtimeCost (RaddtimeCost"
addtimeCount (RaddtimeCount(
confirmLeftTime (RconfirmLeftTime
	isconfirm (R	isconfirm"“
PBQiuQiuTableInfo
gameId (RgameId
	seatCount (R	seatCount

smallBlind (R
smallBlind
bigBlind (RbigBlind
	tableName (	R	tableName
	gameState (R	gameState
	buttonSid (R	buttonSid
roundNum (RroundNum 
publicPools	 (RpublicPools7
	seatInfos
 (2.network.cmd.PBQiuQiuSeatR	seatInfos

minbuyinbb (R
minbuyinbb

maxbuyinbb (R
maxbuyinbb
ante (Rante 
bettingtime (Rbettingtime
	matchType (R	matchType

matchState (R
matchState
roomType (RroomType 
addtimeCost (RaddtimeCost0
peekWinnerCardsCost (RpeekWinnerCardsCost
toolCost (RtoolCost
jpid (Rjpid
jp (Rjp
	jp_ratios (RjpRatios 
middlebuyin (Rmiddlebuyin
maxinto (Rmaxinto"U
PBQiuQiuTableInfoResp<
	tableInfo (2.network.cmd.PBQiuQiuTableInfoR	tableInfo"Y
PBQiuQiuHandCards
sid (Rsid
state (Rstate
	handcards (R	handcards"H
PBQiuQiuDealCard4
cards (2.network.cmd.PBQiuQiuHandCardsRcards"Í
PBQiuQiuGameStart
gameId (RgameId
	gameState (R	gameState
	buttonSid (R	buttonSid

smallBlind (R
smallBlind
bigBlind (RbigBlind
ante (Rante
minChip (RminChip'
table_starttime (RtableStarttime 
isAutoAllin	 (RisAutoAllin/
seats
 (2.network.cmd.PBQiuQiuSeatRseats"K
PBQiuQiuUpdateSeat5
seatInfo (2.network.cmd.PBQiuQiuSeatRseatInfo"€
PBQiuQiuShowDealCard
showType (RshowType
sid (Rsid
	handcards (R	handcards
	cardsType (R	cardsType"·
PBQiuQiuReviewItem-
player (2.network.cmd.PBPlayerRplayer<
	handcards (2.network.cmd.PBQiuQiuHandCardsR	handcards$
bestcardstype (Rbestcardstype
win (Rwin*
roundchipintypes (Rroundchipintypes,
roundchipinmoneys (Rroundchipinmoneys"
showhandcard (Rshowhandcard"w
PBQiuQiuReview
	buttonuid (R	buttonuid
pot (Rpot5
items (2.network.cmd.PBQiuQiuReviewItemRitems"K
PBQiuQiuReviewResp5
reviews (2.network.cmd.PBQiuQiuReviewRreviews"y
PBQiuQiuCardSaveReqResp,
idx (2.network.cmd.RoomIndexDataRidx
code (Rcode
	handcards (R	handcards"½
PBQiuQiuPotInfo
potID (RpotID
sid (Rsid
potMoney (RpotMoney
winMoney (RwinMoney
	seatMoney (R	seatMoney
mark (Rmark
winType (RwinType"…
PBQiuQiuFinalGame8
potInfos (2.network.cmd.PBQiuQiuPotInfoRpotInfos
profits (Rprofits
	seatMoney (R	seatMoney"[
PBQiuQiuConfirmNotify(
confirmLeftTime (RconfirmLeftTime
sidlist (Rsidlist"~
PBQiuQiuConfirmReqResp,
idx (2.network.cmd.RoomIndexDataRidx
code (Rcode
sid (Rsid
uid (Ruid"Š
PBQiuQiuPlayerSit5
seatInfo (2.network.cmd.PBQiuQiuSeatRseatInfo 
clientBuyin (RclientBuyin
	buyinTime (R	buyinTime"Q
PBQiuQiuDealCardOnlyRobot4
cards (2.network.cmd.PBQiuQiuHandCardsRcards*ã
PBQiuQiuCardWinType 
PBQiuQiuCardWinType_HIGHCARD
PBQiuQiuCardWinType_QIUQIU!
PBQiuQiuCardWinType_BIGSERIES#
PBQiuQiuCardWinType_SMALLSERIES"
PBQiuQiuCardWinType_TWINSERIES
PBQiuQiuCardWinType_SIXGOD*í
PBQiuQiuTableState
PBQiuQiuTableState_None
PBQiuQiuTableState_Start
PBQiuQiuTableState_PreChips
PBQiuQiuTableState_PreFlop
PBQiuQiuTableState_River
PBQiuQiuTableState_Confirm
PBQiuQiuTableState_Finish*ì
PBQiuQiuChipinType
PBQiuQiuChipinType_NULL
PBQiuQiuChipinType_FOLD
PBQiuQiuChipinType_CHECK
PBQiuQiuChipinType_CALL
PBQiuQiuChipinType_RAISE!
PBQiuQiuChipinType_SMALLBLIND
PBQiuQiuChipinType_BIGBLIND
PBQiuQiuChipinType_ALL_IN
PBQiuQiuChipinType_BETING	
PBQiuQiuChipinType_WAIT
#
PBQiuQiuChipinType_CLEAR_STATUS
PBQiuQiuChipinType_REBUYING
PBQiuQiuChipinType_PRECHIPS
PBQiuQiuChipinType_BUYING
PBQiuQiuChipinType_LATE_BB