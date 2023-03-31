
ßM
texas.protonetwork.cmdcommon.proto"û
PBTexasSeat+
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
chipinTime
card1 (Rcard1
card2 (Rcard2
onePot (RonePot 
reserveSeat (RreserveSeat
	totalTime (R	totalTime 
addtimeCost (RaddtimeCost"
addtimeCount (RaddtimeCount"®
PBTexasTableInfo
gameId (RgameId
	seatCount (R	seatCount

smallBlind (R
smallBlind
bigBlind (RbigBlind
	tableName (	R	tableName
	gameState (R	gameState
	buttonSid (R	buttonSid$
smallBlindSid (RsmallBlindSid 
bigBlindSid	 (RbigBlindSid 
publicCards
 (RpublicCards
roundNum (RroundNum 
publicPools (RpublicPools6
	seatInfos (2.network.cmd.PBTexasSeatR	seatInfos

minbuyinbb (R
minbuyinbb

maxbuyinbb (R
maxbuyinbb

create_uid (R	createUid
ante (Rante 
bettingtime (Rbettingtime
code (Rcode
	matchType (R	matchType

matchState (R
matchStateL
blindLevelInfos (2".network.cmd.PBTexasBlindLevelInfoRblindLevelInfos
roomType (RroomType 
addtimeCost (RaddtimeCost0
peekWinnerCardsCost (RpeekWinnerCardsCost*
peekPubCardsCost (RpeekPubCardsCost
toolCost (RtoolCost
jpid (Rjpid
jp (Rjp
	jp_ratios (RjpRatios 
middlebuyin (Rmiddlebuyin
maxinto  (Rmaxinto"W
PBTexasTableInfoReq,
idx (2.network.cmd.RoomIndexDataRidx
lang (	Rlang"S
PBTexasTableInfoResp;
	tableInfo (2.network.cmd.PBTexasTableInfoR	tableInfo"•
PBTexasBlindInfo
sb (Rsb
ante (Rante
next_sb (RnextSb
	next_ante (RnextAnte
	left_secs (RleftSecs
curLevel (RcurLevel"g
PBTexasBlindLevelInfo
lv (Rlv
sb (Rsb
ante (Rante
duration (Rduration"C
PBTexasBlindInfoReq,
idx (2.network.cmd.RoomIndexDataRidx"S
PBTexasBlindInfoResp;
	blindInfo (2.network.cmd.PBTexasBlindInfoR	blindInfo"V
PBTexasNotifyRiaseBlind;
	blindInfo (2.network.cmd.PBTexasBlindInfoR	blindInfo"p
PBTexasNotifyMatchResultInfo
rank (Rrank 
resultState (RresultState
winMoney (RwinMoney":
PBTexasNotifyUpdateMatch

matchState (R
matchState"O
PBTexasSitReq,
idx (2.network.cmd.RoomIndexDataRidx
sid (Rsid"à
PBTexasPlayerSit4
seatInfo (2.network.cmd.PBTexasSeatRseatInfo 
clientBuyin (RclientBuyin
	buyinTime (R	buyinTime"&
PBTexasSitFailed
code (Rcode"Y
PBTexasReservationReq,
idx (2.network.cmd.RoomIndexDataRidx
type (Rtype"B
PBTexasReservationResp
sid (Rsid
result (Rresult"?
PBTexasStandReq,
idx (2.network.cmd.RoomIndexDataRidx":
PBTexasPlayerStand
sid (Rsid
type (Rtype"(
PBTexasStandFailed
code (Rcode"A
PBTexasAddTimeReq,
idx (2.network.cmd.RoomIndexDataRidx"V
PBTexasAddTimeResp,
idx (2.network.cmd.RoomIndexDataRidx
code (Rcode"~
PBTexasChipinReq,
idx (2.network.cmd.RoomIndexDataRidx
chipType (RchipType 
chipinMoney (RchipinMoney"ñ
PBTexasShowDealCardReq,
idx (2.network.cmd.RoomIndexDataRidx
sid (Rsid
uid (Ruid
card1 (Rcard1
card2 (Rcard2"J
PBTexasCanShowDealCard
sid (Rsid

canReqShow (R
canReqShow"ì
PBTexasBuyinReq,
idx (2.network.cmd.RoomIndexDataRidx
context (Rcontext

buyinMoney (R
buyinMoney
autoBuy (RautoBuy"B
PBTexasBuyinFailed
code (Rcode
context (Rcontext"®
PBTexasPlayerBuyin
sid (Rsid
chips (Rchips
money (Rmoney
autoBuy (RautoBuy
context (Rcontext 
immediately (Rimmediately"e
PBTexasPopupBuyin 
clientBuyin (RclientBuyin
	buyinTime (R	buyinTime
sid (Rsid"
PBTexasClearTable"C
PBTexasSituationReq,
idx (2.network.cmd.RoomIndexDataRidx"}
PBTexasSituation-
player (2.network.cmd.PBPlayerRplayer

totalbuyin (R
totalbuyin
totalwin (Rtotalwin"U
PBTexasSituationResp=

situations (2.network.cmd.PBTexasSituationR
situations"@
PBTexasReviewReq,
idx (2.network.cmd.RoomIndexDataRidx"≠
PBTexasReviewItem-
player (2.network.cmd.PBPlayerRplayer;
	handcards (2.network.cmd.PBTexasHandCardsR	handcards
	bestcards (R	bestcards$
bestcardstype (Rbestcardstype
win (Rwin*
roundchipintypes (Rroundchipintypes,
roundchipinmoneys (Rroundchipinmoneys"
showhandcard (Rshowhandcard,
efshowhandcarduid	 (Refshowhandcarduid*
usershowhandcard
 (Rusershowhandcard"Ω
PBTexasReview
	buttonuid (R	buttonuid
sbuid (Rsbuid
bbuid (Rbbuid
pot (Rpot
pubcards (Rpubcards4
items (2.network.cmd.PBTexasReviewItemRitems"I
PBTexasReviewResp4
reviews (2.network.cmd.PBTexasReviewRreviews"Z
PBTexasPreOperateReq,
idx (2.network.cmd.RoomIndexDataRidx
preop (Rpreop"-
PBTexasPreOperateResp
preop (Rpreop"ì
PBTexasGameStart
gameId (RgameId
	gameState (R	gameState
	buttonSid (R	buttonSid$
smallBlindSid (RsmallBlindSid 
bigBlindSid (RbigBlindSid

smallBlind (R
smallBlind
bigBlind (RbigBlind
ante (Rante
minChip	 (RminChip'
table_starttime
 (RtableStarttime 
isAutoAllin (RisAutoAllin.
seats (2.network.cmd.PBTexasSeatRseats"I
PBTexasUpdateSeat4
seatInfo (2.network.cmd.PBTexasSeatRseatInfo"P
PBTexasHandCards
sid (Rsid
card1 (Rcard1
card2 (Rcard2"F
PBTexasDealCard3
cards (2.network.cmd.PBTexasHandCardsRcards"ã
PBTexasDealCardOnlyRobot3
cards (2.network.cmd.PBTexasHandCardsRcards
	leftcards (R	leftcards
	isControl (R	isControl"Z
PBTexasDealPublicCards
cards (Rcards
state (Rstate
delay (Rdelay"Q
PBTexasUpdatePots
roundNum (RroundNum 
publicPools (RpublicPools"o
PBTexasShowDealCard
showType (RshowType
sid (Rsid
card1 (Rcard1
card2 (Rcard2"º
PBTexasPotInfo
potID (RpotID
sid (Rsid
potMoney (RpotMoney
winMoney (RwinMoney
	seatMoney (R	seatMoney
mark (Rmark
winType (RwinType"É
PBTexasFinalGame7
potInfos (2.network.cmd.PBTexasPotInfoRpotInfos
profits (Rprofits
	seatMoney (R	seatMoney"]
PBTexasNotifyBestHand_N$
bestcardstype (Rbestcardstype
	bestcards (R	bestcards"I
PBTexasEnforceShowCardReq,
idx (2.network.cmd.RoomIndexDataRidx"d
PBTexasEnforceShowCardResp
code (Rcode
	winnersid (R	winnersid
cards (Rcards">
PBTexasNotifyEnforceShowCardBt
	countdown (R	countdown"J
PBTexasNextRoundPubCardReq,
idx (2.network.cmd.RoomIndexDataRidx"G
PBTexasNextRoundPubCardResp
code (Rcode
cards (Rcards"?
PBTexasNotifyNextRoundPubCardBt
	countdown (R	countdown"
PBTexasTableListInfoReq
gameid (Rgameid
matchid (Rmatchid
roomid (Rroomid
serverid (Rserverid"Õ
PBTexasTableListInfoResp,
idx (2.network.cmd.RoomIndexDataRidx
ante (Rante
bigBlind (RbigBlind
	miniBuyin (R	miniBuyin5
	seatInfos (2.network.cmd.PBSeatInfoR	seatInfos*‰
PBTexasRoomType
PBTexasRoomType_New
PBTexasRoomType_Low
PBTexasRoomType_Mid
PBTexasRoomType_High
PBTexasRoomType_Earl
PBTexasRoomType_Duke
PBTexasRoomType_Monarch
PBTexasRoomType_Extreme*l
PBTexasMatchType
PBTexasMatchType_Regular
PBTexasMatchType_SNG 
PBTexasMatchType_SelfRegular*à
PBTexasMatchState
PBTexasMatchState_None
PBTexasMatchState_Wait
PBTexasMatchState_Playing
PBTexasMatchState_Finish*Å
PBTexasLeaveToSitState!
PBTexasLeaveToSitState_Cancel 
PBTexasLeaveToSitState_Leave"
PBTexasLeaveToSitState_Reserve*‹
PBTexasChipinType
PBTexasChipinType_NULL
PBTexasChipinType_FOLD
PBTexasChipinType_CHECK
PBTexasChipinType_CALL
PBTexasChipinType_RAISE 
PBTexasChipinType_SMALLBLIND
PBTexasChipinType_BIGBLIND
PBTexasChipinType_ALL_IN
PBTexasChipinType_BETING	
PBTexasChipinType_WAIT
"
PBTexasChipinType_CLEAR_STATUS
PBTexasChipinType_REBUYING
PBTexasChipinType_PRECHIPS
PBTexasChipinType_BUYING
PBTexasChipinType_LATE_BB*Ç
PBTexasCardWinType
PBTexasCardWinType_WINNING
PBTexasCardWinType_HIGHCARD
PBTexasCardWinType_ONEPAIR
PBTexasCardWinType_TWOPAIRS 
PBTexasCardWinType_THRREKAND
PBTexasCardWinType_STRAIGHT
PBTexasCardWinType_FLUSH 
PBTexasCardWinType_FULLHOUSE
PBTexasCardWinType_FOURKAND	$
 PBTexasCardWinType_STRAIGHTFLUSH
 
PBTexasCardWinType_ROYALFLUS*˛
PBTexasTableState
PBTexasTableState_None
PBTexasTableState_Start
PBTexasTableState_PreChips
PBTexasTableState_PreFlop
PBTexasTableState_Flop
PBTexasTableState_Turn
PBTexasTableState_River
PBTexasTableState_Finish*≈
PBTexasStandType 
PBTexasStandType_PlayerStand#
PBTexasStandType_MoneyNotEnough*
&PBTexasStandType_ReservationTimesLimit
PBTexasStandType_Kickout 
PBTexasStandType_BuyinFailed*‹
PBTexasBuyinResultType!
PBTexasBuyinResultType_Failed &
"PBTexasBuyinResultType_InvalidUser&
"PBTexasBuyinResultType_InvalidSeat)
%PBTexasBuyinResultType_NotEnoughMoney$
 PBTexasBuyinResultType_OverLimit*é
PBTexasPreOPType
PBTexasPreOPType_None  
PBTexasPreOPType_CheckOrFold
PBTexasPreOPType_AutoCheck
PBTexasPreOPType_RaiseAny