
�6
seotda.protonetwork.cmdcommon.proto"h
PBSeotdaBlindLevelInfo
lv (
sb (Rsb
ante (Rante
duration (
PBSeotdaGroupItem
card1 (Rcard1
card2 (Rcard2
	cardsType (R	cardsType"�

PBSeotdaSeat+
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
onePot
reserveSeat (
	totalTime (R	totalTime 
addtimeCost (RaddtimeCost"
addtimeCount (RaddtimeCount
hasCheck (RhasCheck
	handcards (R	handcards$

totalChipin (RtotalChipin
	cardsType (R	cardsType
raise (Rraise
	raiseHalf (R	raiseHalf"
raiseQuarter (RraiseQuarter 
playerState (RplayerState 
replayChips (RreplayChips&
replayLeftTime (RreplayLeftTime
cardsNum (RcardsNum
showCard (RshowCard6
groups (2.network.cmd.PBSeotdaGroupItemRgroups 
roundMaxBet  (RroundMaxBet"
operateTypes! (RoperateTypes,
operateTypesRound" (RoperateTypesRound
canCheck# (RcanCheck
canCall$ (RcanCall
canFold% (RcanFold
	canMinBet& (R	canMinBet
canRaise' (RcanRaise"
canRaiseHalf( (RcanRaiseHalf(
canRaiseQuarter) (RcanRaiseQuarter"�

PBSeotdaTableInfo
gameId (RgameId
	seatCount (R	seatCount
	tableName (	R	tableName
	gameState (R	gameState
	buttonSid (R	buttonSid
pot (Rpot7
	seatInfos (2.network.cmd.PBSeotdaSeatR	seatInfos
ante (Rante

minbuyinbb	 (
minbuyinbb

maxbuyinbb
 (
maxbuyinbb 
middlebuyin (Rmiddlebuyin 
bettingtime (Rbettingtime
	matchType

matchState (
matchState
roomType (
toolCost (RtoolCost
jpid (Rjpid
jp (Rjp
jpRatios (RjpRatios 
addtimeCost (RaddtimeCost

operatePos (R
operatePos
roundNum (RroundNum
betLimit (RbetLimit
potLimit (RpotLimit
	duelerPos (R	duelerPos
	dueledPos (R	dueledPos

smallBlind (R
smallBlind
bigBlind (RbigBlind0
peekWinnerCardsCost (RpeekWinnerCardsCost 
publicPools (RpublicPools$

bigBlindSid  (RbigBlindSid 
publicCards! (RpublicCards
	createUID" (R	createUID
code# (
peekPubCardsCost$ (RpeekPubCardsCostM
blindLevelInfos% (2#.network.cmd.PBSeotdaBlindLevelInfoRblindLevelInfos
leftTime& (RleftTime

replayType' (R
replayType 
roundMaxBet( (RroundMaxBet"U
PBSeotdaTableInfoResp<
	tableInfo (2.network.cmd.PBSeotdaTableInfoR	tableInfo"�
PBSeotdaPlayerSit5
seatInfo (2.network.cmd.PBSeotdaSeatRseatInfo 
clientBuyin (RclientBuyin
	buyinTime (R	buyinTime"�
PBSeotdaGameStart
gameId (RgameId
	gameState (R	gameState
	buttonSid (R	buttonSid$

bigBlindSid (RbigBlindSid

smallBlind (R
smallBlind
bigBlind (RbigBlind
ante (Rante
minChip	 (RminChip&
tableStarttime
 (RtableStarttime 
isAutoAllin (
seats (2.network.cmd.PBSeotdaSeatRseats"a
PBSeotdaUpdateSeat5
seatInfo (2.network.cmd.PBSeotdaSeatRseatInfo
state (Rstate"�
PBSeotdaHandCards
sid (Rsid
card1 (Rcard1
card2 (Rcard2
	cardsType (R	cardsType
cardsNum (RcardsNum
	handcards (R	handcards6
groups (2.network.cmd.PBSeotdaGroupItemRgroups
	firstCard (R	firstCard 
replayCards	 (RreplayCards
roundNum
 (RroundNum

secondCard (R
secondCard"d
PBSeotdaDealCard4
cards (2.network.cmd.PBSeotdaHandCardsRcards
isReplay (RisReplay"�
PBSeotdaPotInfo
potID (RpotID
sid (Rsid
potMoney (RpotMoney
winMoney (RwinMoney
	seatMoney (R	seatMoney
mark (Rmark
winType (RwinType"�
PBSeotdaFinalGame8
potInfos (2.network.cmd.PBSeotdaPotInfoRpotInfos
profits (Rprofits
	seatMoney (R	seatMoney"�
PBSeotdaReplayReq
	needChips (R	needChips
chips (Rchips
leftTime (RleftTime"
playerNumMin (RplayerNumMin"
playerNumMax (RplayerNumMax
uid (Ruid"Z
PBSeotdaReplayResp,
idx (2.network.cmd.RoomIndexDataRidx
replay (Rreplay"G
PBSeotdaSeatState
sid (Rsid 
playerState (RplayerState"q
PBSeotdaReplayState:
allSeats (2.network.cmd.PBSeotdaSeatStateRallSeats

replayType (R
replayType"Z
PBSeotdaShowOneCardReq,
idx (2.network.cmd.RoomIndexDataRidx
card (Rcard"?
PBSeotdaShowOneCardItem
sid (Rsid
card (Rcard"[
PBSeotdaShowOneCardResp@
allSeats (2$.network.cmd.PBSeotdaShowOneCardItemRallSeats"E
PBSeotdaRoomState
state (Rstate
leftTime (RleftTime"s
PBSeotdaCompareCardsReq,
idx (2.network.cmd.RoomIndexDataRidx
card1 (Rcard1
card2 (Rcard2"�
PBSeotdaReviewItem-
player (2.network.cmd.PBPlayerRplayer<
	handcards (2.network.cmd.PBSeotdaHandCardsR	handcards$

win (Rwin*
roundchipintypes (Rroundchipintypes,
roundchipinmoneys (Rroundchipinmoneys$

PBSeotdaReview
	buttonuid (R	buttonuid
pot (Rpot5
items (2.network.cmd.PBSeotdaReviewItemRitems"K
PBSeotdaReviewResp5
reviews (2.network.cmd.PBSeotdaReviewRreviews*�
PBSeotdaChipinType
PBSeotdaChipinType_NULL
PBSeotdaChipinType_FOLD
PBSeotdaChipinType_CHECK
PBSeotdaChipinType_CALL
PBSeotdaChipinType_RAISE!
PBSeotdaChipinType_SMALLBLIND
PBSeotdaChipinType_BIGBLIND
PBSeotdaChipinType_ALL_IN
PBSeotdaChipinType_BETING	
PBSeotdaChipinType_WAIT
#
PBSeotdaChipinType_CLEAR_STATUS
PBSeotdaChipinType_REBUYING
PBSeotdaChipinType_PRECHIPS
PBSeotdaChipinType_BUYING
PBSeotdaChipinType_LATE_BB
PBSeotdaChipinType_BET
PBSeotdaChipinType_RAISE2
PBSeotdaChipinType_RAISE3
PBSeotdaChipinType_COMPARE
PBSeotdaChipinType_Show*�
PBSeotdaTableState
PBSeotdaTableState_None
PBSeotdaTableState_Start
PBSeotdaTableState_PreChips!
PBSeotdaTableState_DealCards1"
PBSeotdaTableState_ShowOneCard
PBSeotdaTableState_Betting1 
PBSeotdaTableState_DealCard2
PBSeotdaTableState_Betting2"
PBSeotdaTableState_SelectCards	
PBSeotdaTableState_Dueling
"
PBSeotdaTableState_ReplayChips"
PBSeotdaTableState_ReDealCards
PBSeotdaTableState_Betting3
PBSeotdaTableState_Finish