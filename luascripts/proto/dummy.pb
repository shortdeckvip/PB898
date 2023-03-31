
ü*
dummy.protonetwork.cmdcommon.proto"#
PBDummyHole
cards (Rcards"=
PBDummyZone.
holes (2.network.cmd.PBDummyHoleRholes"Ã
PBDummySeat+
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
discardCard (RdiscardCard
drawcard (Rdrawcard
score (Rscore
	leftcards (R	leftcards,
zone (2.network.cmd.PBDummyZoneRzone
iscreate (Riscreate
	showcards (R	showcards 
handcardcnt (Rhandcardcnt
	canshow2q (R	canshow2q

handcreate (R
handcreate"∆
PBDummyTableInfo
gameId (RgameId
	seatCount (R	seatCount
	tableName (	R	tableName
	gameState (R	gameState
	buttonSid (R	buttonSid
pot (Rpot6
	seatInfos (2.network.cmd.PBDummySeatR	seatInfos
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
discardCard (RdiscardCard$
readyLeftTime (RreadyLeftTime(
leftDeclareTime (RleftDeclareTime

minbuyinbb (R
minbuyinbb

maxbuyinbb (R
maxbuyinbb
maxinto (Rmaxinto"S
PBDummyTableInfoResp;
	tableInfo (2.network.cmd.PBDummyTableInfoR	tableInfo"H
PBDummyPlayerSit4
seatInfo (2.network.cmd.PBDummySeatRseatInfo"C
PBDummyGroupSaveReq,
idx (2.network.cmd.RoomIndexDataRidx"C
PBDummySituationReq,
idx (2.network.cmd.RoomIndexDataRidx"}
PBDummySituation-
player (2.network.cmd.PBPlayerRplayer

totalbuyin (R
totalbuyin
totalwin (Rtotalwin"U
PBDummySituationResp=

situations (2.network.cmd.PBDummySituationR
situations"∫
PBDummyReviewItem-
player (2.network.cmd.PBPlayerRplayer
sid (Rsid
	handcards (R	handcards
wintype (Rwintype
win (Rwin
showcard (Rshowcard"â
PBDummyReview
	buttonsid (R	buttonsid
ante (Rante
pot (Rpot4
items (2.network.cmd.PBDummyReviewItemRitems"I
PBDummyReviewResp4
reviews (2.network.cmd.PBDummyReviewRreviews"8
PBDummyGameReady$
readyLeftTime (RreadyLeftTime"t
PBDummyReShuffleCard 
discardCard (RdiscardCard
	foldcards (R	foldcards
	leftcards (R	leftcards"Ï
PBDummyGameStart
gameId (RgameId
	gameState (R	gameState
	buttonSid (R	buttonSid
ante (Rante
minChip (RminChip&
tableStarttime (RtableStarttime.
seats (2.network.cmd.PBDummySeatRseats"c
PBDummyUpdateSeat4
seatInfo (2.network.cmd.PBDummySeatRseatInfo
context (	Rcontext"B
PBDummyHandCards
sid (Rsid
	handcards (R	handcards"Ü
PBDummyDealCard3
cards (2.network.cmd.PBDummyHandCardsRcards 
discardCard (RdiscardCard
	leftcards (R	leftcards"=
PBDummyPotScore
cards (Rcards
score (Rscore"‡
PBDummyPotInfo
sid (Rsid
winMoney (RwinMoney
	seatMoney (R	seatMoney
winType (RwinType2
score (2.network.cmd.PBDummyPotScoreRscore
nickname (	Rnickname
nickurl (	Rnickurl"©
PBDummyFinalGame
potMoney (RpotMoney7
potInfos (2.network.cmd.PBDummyPotInfoRpotInfos$
readyLeftTime (RreadyLeftTime
winerSid (RwinerSid"÷
PBDummyKnockChipin
chipType (RchipType
	chipValue (R	chipValue
tosid (Rtosid
tozoneid (Rtozoneid
	foldcards (R	foldcards
	handcards (R	handcards
context (	Rcontext"π
PBDummyChipinReq,
idx (2.network.cmd.RoomIndexDataRidx
chipType (RchipType
	chipValue (R	chipValue
tosid (Rtosid
tozoneid (Rtozoneid
	foldcards (R	foldcards
	handcards (R	handcards
context (	Rcontext5
knock	 (2.network.cmd.PBDummyKnockChipinRknock*Å
PBDummyLeaveToSitState!
PBDummyLeaveToSitState_Cancel 
PBDummyLeaveToSitState_Leave"
PBDummyLeaveToSitState_Reserve*·
PBDummyChipinType
PBDummyChipinType_NULL
PBDummyChipinType_FOLD
PBDummyChipinType_DRAW
PBDummyChipinType_CREATE
PBDummyChipinType_DISCARD
PBDummyChipinType_PLACE
PBDummyChipinType_SAVE
PBDummyChipinType_KNOCK 
PBDummyChipinType_BATCHKNOCK	
PBDummyChipinType_Show2Q

PBDummyChipinType_HandCard
PBDummyChipinType_BETING
PBDummyChipinType_BUYING
PBDummyChipinType_FirstCard
PBDummyChipinType_DropScore
PBDummyChipinType_DropDummy 
PBDummyChipinType_FirstBlast"
PBDummyChipinType_SpecialBlast
PBDummyChipinType_SaveLast
PBDummyChipinType_Stupid
PBDummyChipinType_Unlucky"
PBDummyChipinType_SpecialKnock 
PBDummyChipinType_FlushKnock
PBDummyChipinType_OnceKnock 
PBDummyChipinType_SuperKnock
PBDummyChipinType_SpetTo
PBDummyChipinType_FINISH*…
PBDummyTableState
PBDummyTableState_None
PBDummyTableState_Start
PBDummyTableState_PreChips
PBDummyTableState_HandCard
PBDummyTableState_Betting
PBDummyTableState_Finish