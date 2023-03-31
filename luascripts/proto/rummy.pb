
¢$
rummy.protonetwork.cmdcommon.proto"*
RummyGroupCardData
cards (Rcards"É
PBRummySeat+
seat (2.network.cmd.PBSeatInfoRseat
	isPlaying (R	isPlaying
	seatMoney (R	seatMoney

chipinType (R
chipinType 
chipinValue (RchipinValue

chipinTime (R
chipinTime
	totalTime (R	totalTime
	handcards (R	handcards
pot	 (Rpot$
currentBetPos
 (RcurrentBetPos 
addtimeCost (RaddtimeCost"
addtimeCount (RaddtimeCount 
discardCard (RdiscardCard
drawcard (Rdrawcard5
group (2.network.cmd.RummyGroupCardDataRgroup
score (Rscore
	foldcards (R	foldcards
	leftcards (R	leftcards(
leftDeclareTime (RleftDeclareTime"Ë
PBRummyTableInfo
gameId (RgameId
	seatCount (R	seatCount
	tableName (	R	tableName
	gameState (R	gameState
	buttonSid (R	buttonSid
pot (Rpot6
	seatInfos (2.network.cmd.PBRummySeatR	seatInfos
ante (Rante 
bettingtime	 (Rbettingtime
	matchType
 (R	matchType

matchState (R
matchState
roomType (RroomType
toolCost (RtoolCost
jpid (Rjpid
jp (Rjp
jpRatios (RjpRatios 
addtimeCost (RaddtimeCost 
discardCard (RdiscardCard
	magicCard (R	magicCard$
magicCardList (RmagicCardList$
readyLeftTime (RreadyLeftTime(
leftDeclareTime (RleftDeclareTime

minbuyinbb (R
minbuyinbb

maxbuyinbb (R
maxbuyinbb
	foldcards (R	foldcards
	leftcards (R	leftcards 
middlebuyin (Rmiddlebuyin
maxinto (Rmaxinto"S
PBRummyTableInfoResp;
	tableInfo (2.network.cmd.PBRummyTableInfoR	tableInfo"à
PBRummyPlayerSit4
seatInfo (2.network.cmd.PBRummySeatRseatInfo 
clientBuyin (RclientBuyin
	buyinTime (R	buyinTime"z
PBRummyGroupSaveReq,
idx (2.network.cmd.RoomIndexDataRidx5
group (2.network.cmd.RummyGroupCardDataRgroup"C
PBRummySituationReq,
idx (2.network.cmd.RoomIndexDataRidx"}
PBRummySituation-
player (2.network.cmd.PBPlayerRplayer

totalbuyin (R
totalbuyin
totalwin (Rtotalwin"U
PBRummySituationResp=

situations (2.network.cmd.PBRummySituationR
situations"Ò
PBRummyReviewItem-
player (2.network.cmd.PBPlayerRplayer
sid (Rsid=
	handcards (2.network.cmd.RummyGroupCardDataR	handcards
wintype (Rwintype
win (Rwin
showcard (Rshowcard
score (Rscore"Ø
PBRummyReview
	buttonsid (R	buttonsid
ante (Rante
pot (Rpot4
items (2.network.cmd.PBRummyReviewItemRitems$
magicCardList (RmagicCardList"I
PBRummyReviewResp4
reviews (2.network.cmd.PBRummyReviewRreviews"8
PBRummyGameReady$
readyLeftTime (RreadyLeftTime"t
PBRummyReShuffleCard 
discardCard (RdiscardCard
	foldcards (R	foldcards
	leftcards (R	leftcards"“
PBRummyGameStart
gameId (RgameId
	gameState (R	gameState
	buttonSid (R	buttonSid
ante (Rante
minChip (RminChip&
tableStarttime (RtableStarttime.
seats (2.network.cmd.PBRummySeatRseats 
discardCard (RdiscardCard
	magicCard	 (R	magicCard$
magicCardList
 (RmagicCardList"I
PBRummyUpdateSeat4
seatInfo (2.network.cmd.PBRummySeatRseatInfo"y
PBRummyHandCards
sid (Rsid
	handcards (R	handcards5
group (2.network.cmd.RummyGroupCardDataRgroup"F
PBRummyDealCard3
cards (2.network.cmd.PBRummyHandCardsRcards"%
PBRummyUpdatePots
pot (Rpot"˘
PBRummyPotInfo
sid (Rsid
winMoney (RwinMoney
	seatMoney (R	seatMoney
winType (RwinType
score (Rscore
nickname (	Rnickname
nickurl (	Rnickurl5
group (2.network.cmd.RummyGroupCardDataRgroup"ç
PBRummyFinalGame
potMoney (RpotMoney7
potInfos (2.network.cmd.PBRummyPotInfoRpotInfos$
readyLeftTime (RreadyLeftTime*Å
PBRummyLeaveToSitState!
PBRummyLeaveToSitState_Cancel 
PBRummyLeaveToSitState_Leave"
PBRummyLeaveToSitState_Reserve*Ω
PBRummyChipinType
PBRummyChipinType_NULL
PBRummyChipinType_FOLD
PBRummyChipinType_DRAW1
PBRummyChipinType_DRAW2
PBRummyChipinType_DISCARD
PBRummyChipinType_FINISH
PBRummyChipinType_DECLARE
PBRummyChipinType_DECLARED
PBRummyChipinType_BETING	
PBRummyChipinType_BUYING
*Ë
PBRummyTableState
PBRummyTableState_None
PBRummyTableState_Start
PBRummyTableState_PreChips
PBRummyTableState_HandCard
PBRummyTableState_Betting
PBRummyTableState_Declare
PBRummyTableState_Finish