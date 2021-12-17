
ž 
samgong.protonetwork.cmdcommon.proto"’
PBSamGongSeat+
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
addtimeCount (RaddtimeCount"Ù
PBSamGongTableInfo
gameId (RgameId
	seatCount (R	seatCount

smallBlind (R
smallBlind
bigBlind (RbigBlind
	tableName (	R	tableName
	gameState (R	gameState
	buttonSid (R	buttonSid
roundNum (RroundNum 
publicPools	 (RpublicPools8
	seatInfos
 (2.network.cmd.PBSamGongSeatR	seatInfos

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
	jp_ratios (RjpRatios"W
PBSamGongTableInfoResp=
	tableInfo (2.network.cmd.PBSamGongTableInfoR	tableInfo"Œ
PBSamGongHandCards
sid (Rsid
state (Rstate
	handcards (R	handcards
cardtype (Rcardtype
point (Rpoint"J
PBSamGongDealCard5
cards (2.network.cmd.PBSamGongHandCardsRcards"Ï
PBSamGongGameStart
gameId (RgameId
	gameState (R	gameState
	buttonSid (R	buttonSid

smallBlind (R
smallBlind
bigBlind (RbigBlind
ante (Rante
minChip (RminChip'
table_starttime (RtableStarttime 
isAutoAllin	 (RisAutoAllin0
seats
 (2.network.cmd.PBSamGongSeatRseats"M
PBSamGongUpdateSeat6
seatInfo (2.network.cmd.PBSamGongSeatRseatInfo"•
PBSamGongShowDealCard
showType (RshowType
sid (Rsid
	handcards (R	handcards
cardtype (Rcardtype
point (Rpoint"¹
PBSamGongReviewItem-
player (2.network.cmd.PBPlayerRplayer=
	handcards (2.network.cmd.PBSamGongHandCardsR	handcards$
bestcardstype (Rbestcardstype
win (Rwin*
roundchipintypes (Rroundchipintypes,
roundchipinmoneys (Rroundchipinmoneys"
showhandcard (Rshowhandcard"y
PBSamGongReview
	buttonuid (R	buttonuid
pot (Rpot6
items (2 .network.cmd.PBSamGongReviewItemRitems"M
PBSamGongReviewResp6
reviews (2.network.cmd.PBSamGongReviewRreviews"¾
PBSamGongPotInfo
potID (RpotID
sid (Rsid
potMoney (RpotMoney
winMoney (RwinMoney
	seatMoney (R	seatMoney
mark (Rmark
winType (RwinType"‡
PBSamGongFinalGame9
potInfos (2.network.cmd.PBSamGongPotInfoRpotInfos
profits (Rprofits
	seatMoney (R	seatMoney"Œ
PBSamGongPlayerSit6
seatInfo (2.network.cmd.PBSamGongSeatRseatInfo 
clientBuyin (RclientBuyin
	buyinTime (R	buyinTime*Ý
PBSamGongCardWinType 
SamGongCardWinType_PointCard
SamGongCardWinType_Flush
SamGongCardWinType_Straight
SamGongCardWinType_JQKCard$
 SamGongCardWinType_FlushStraight
SamGongCardWinType_SamGong*Ô
PBSamGongTableState
PBSamGongTableState_None
PBSamGongTableState_Start 
PBSamGongTableState_PreChips
PBSamGongTableState_PreFlop
PBSamGongTableState_River
PBSamGongTableState_Finish*ü
PBSamGongChipinType
PBSamGongChipinType_NULL
PBSamGongChipinType_FOLD
PBSamGongChipinType_CHECK
PBSamGongChipinType_CALL
PBSamGongChipinType_RAISE"
PBSamGongChipinType_SMALLBLIND 
PBSamGongChipinType_BIGBLIND
PBSamGongChipinType_ALL_IN
PBSamGongChipinType_BETING	
PBSamGongChipinType_WAIT
$
 PBSamGongChipinType_CLEAR_STATUS 
PBSamGongChipinType_REBUYING 
PBSamGongChipinType_PRECHIPS
PBSamGongChipinType_BUYING
PBSamGongChipinType_LATE_BB