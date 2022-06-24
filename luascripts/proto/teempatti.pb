
∂)
teempatti.protonetwork.cmdcommon.proto"‡
PBTeemPattiSeat+
seat (2.network.cmd.PBSeatInfoRseat
	isPlaying (R	isPlaying
	seatMoney (R	seatMoney

chipinType (R
chipinType 
chipinMoney (RchipinMoney

chipinTime (R
chipinTime
	totalTime (R	totalTime
	handcards (R	handcards
pot	 (Rpot
needcall
 (Rneedcall
	needraise (R	needraise
isckeck (Risckeck
duelcard (Rduelcard$
currentBetPos (RcurrentBetPos 
addtimeCost (RaddtimeCost"
addtimeCount (RaddtimeCount
ischall (Rischall 
totalChipin (RtotalChipin
	cardsType (R	cardsType"–
PBTeemPattiTableInfo
gameId (RgameId
	seatCount (R	seatCount
	tableName (	R	tableName
	gameState (R	gameState
	buttonSid (R	buttonSid
pot (Rpot:
	seatInfos (2.network.cmd.PBTeemPattiSeatR	seatInfos
ante (Rante
minbuyin	 (Rminbuyin
maxbuyin
 (Rmaxbuyin 
bettingtime (Rbettingtime
	matchType (R	matchType

matchState (R
matchState
roomType (RroomType
toolCost (RtoolCost
jpid (Rjpid
jp (Rjp
jpRatios (RjpRatios
betLimit (RbetLimit
potLimit (RpotLimit 
addtimeCost (RaddtimeCost
	duelerPos (R	duelerPos
	dueledPos (R	dueledPos 
middlebuyin (Rmiddlebuyin"[
PBTeemPattiTableInfoResp?
	tableInfo (2!.network.cmd.PBTeemPattiTableInfoR	tableInfo"ê
PBTeemPattiPlayerSit8
seatInfo (2.network.cmd.PBTeemPattiSeatRseatInfo 
clientBuyin (RclientBuyin
	buyinTime (R	buyinTime"™
PBTeemPattiShowDealCardReq,
idx (2.network.cmd.RoomIndexDataRidx
sid (Rsid
uid (Ruid
	handcards (R	handcards
	cardsType (R	cardsType"N
PBTeemPattiCanShowDealCard
sid (Rsid

canReqShow (R
canReqShow"G
PBTeemPattiSituationReq,
idx (2.network.cmd.RoomIndexDataRidx"Å
PBTeemPattiSituation-
player (2.network.cmd.PBPlayerRplayer

totalbuyin (R
totalbuyin
totalwin (Rtotalwin"]
PBTeemPattiSituationRespA

situations (2!.network.cmd.PBTeemPattiSituationR
situations"¿
PBTeemPattiReviewItem-
player (2.network.cmd.PBPlayerRplayer
sid (Rsid
	handcards (R	handcards
cardtype (Rcardtype
win (Rwin
showcard (Rshowcard"ë
PBTeemPattiReview
	buttonsid (R	buttonsid
ante (Rante
pot (Rpot8
items (2".network.cmd.PBTeemPattiReviewItemRitems"Q
PBTeemPattiReviewResp8
reviews (2.network.cmd.PBTeemPattiReviewRreviews"Ù
PBTeemPattiGameStart
gameId (RgameId
	gameState (R	gameState
	buttonSid (R	buttonSid
ante (Rante
minChip (RminChip&
tableStarttime (RtableStarttime2
seats (2.network.cmd.PBTeemPattiSeatRseats"Q
PBTeemPattiUpdateSeat8
seatInfo (2.network.cmd.PBTeemPattiSeatRseatInfo"d
PBTeemPattiHandCards
sid (Rsid
	handcards (R	handcards
	cardsType (R	cardsType"N
PBTeemPattiDealCard7
cards (2!.network.cmd.PBTeemPattiHandCardsRcards")
PBTeemPattiUpdatePots
pot (Rpot"É
PBTeemPattiShowDealCard
showType (RshowType
sid (Rsid
	handcards (R	handcards
	cardsType (R	cardsType"z
PBTeemPattiPotInfo
sid (Rsid
winMoney (RwinMoney
	seatMoney (R	seatMoney
winType (RwinType"o
PBTeemPattiFinalGame
potMoney (RpotMoney;
potInfos (2.network.cmd.PBTeemPattiPotInfoRpotInfos"a
PBTeemPattiNotifyBestHand_N$
bestcardstype (Rbestcardstype
	bestcards (R	bestcards"ß
PBTeemPattiNotifyDuelCard_N
type (Rtype
	winnerSid (R	winnerSid
loserSid (RloserSid:
cards (2$.network.cmd.PBTeemPattiShowDealCardRcards"è
PBTeemPattiDealCardOnlyRobot7
cards (2!.network.cmd.PBTeemPattiHandCardsRcards
isJoker (RisJoker
	isSpecial (R	isSpecial"M
PBTeemPattiNotifyCharge
uid (Ruid 
chargeMoney (RchargeMoney*ë
PBTeemPattiLeaveToSitState%
!PBTeemPattiLeaveToSitState_Cancel$
 PBTeemPattiLeaveToSitState_Leave&
"PBTeemPattiLeaveToSitState_Reserve*ø
PBTeemPattiChipinType
PBTeemPattiChipinType_NULL
PBTeemPattiChipinType_FOLD
PBTeemPattiChipinType_CHECK
PBTeemPattiChipinType_CALL
PBTeemPattiChipinType_RAISE
PBTeemPattiChipinType_DUEL"
PBTeemPattiChipinType_DUEL_YES!
PBTeemPattiChipinType_DUEL_NO 
PBTeemPattiChipinType_BETING	
PBTeemPattiChipinType_WAIT
&
"PBTeemPattiChipinType_CLEAR_STATUS"
PBTeemPattiChipinType_REBUYING"
PBTeemPattiChipinType_PRECHIPS 
PBTeemPattiChipinType_BUYING%
!PBTeemPattiChipinType_BETING_LACK"
PBTeemPattiChipinType_CHARGING*°
PBTeemPattiCardWinType#
PBTeemPattiCardWinType_HIGHCARD"
PBTeemPattiCardWinType_ONEPAIR 
PBTeemPattiCardWinType_FLUSH#
PBTeemPattiCardWinType_STRAIGHT(
$PBTeemPattiCardWinType_STRAIGHTFLUSH$
 PBTeemPattiCardWinType_THRREKAND'
#PBTeemPattiCardWinType_THRREKANDACE*à
PBTeemPattiTableState
PBTeemPattiTableState_None
PBTeemPattiTableState_Start"
PBTeemPattiTableState_PreChips"
PBTeemPattiTableState_HandCard!
PBTeemPattiTableState_Betting!
PBTeemPattiTableState_Dueling 
PBTeemPattiTableState_Finish