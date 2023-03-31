
ù
domino.protonetwork.cmdcommon.proto"â
PBDominoSeat+
seat (2.network.cmd.PBSeatInfoRseat
	isPlaying (R	isPlaying
	seatMoney (R	seatMoney

chipinType (R
chipinType 
chipinValue (RchipinValue

chipinTime (R
chipinTime
	totalTime (R	totalTime
	handcards (R	handcards
pot	 (Rpot$
currentBetPos
 (RcurrentBetPos 
addtimeCost (RaddtimeCost"
addtimeCount (RaddtimeCount&
lastOutCardSid (RlastOutCardSid*
lastOutCardMoney (RlastOutCardMoney 
passCardPay (RpassCardPay"∏
PBDominoTableInfo
gameId (RgameId
	seatCount (R	seatCount
	tableName (	R	tableName
	gameState (R	gameState
	buttonSid (R	buttonSid
pot (Rpot7
	seatInfos (2.network.cmd.PBDominoSeatR	seatInfos
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
discardCard (RdiscardCard$
readyLeftTime (RreadyLeftTime
minbuyin (Rminbuyin 
middlebuyin (Rmiddlebuyin
maxbuyin (Rmaxbuyin
maxinto (Rmaxinto"U
PBDominoTableInfoResp<
	tableInfo (2.network.cmd.PBDominoTableInfoR	tableInfo"ä
PBDominoPlayerSit5
seatInfo (2.network.cmd.PBDominoSeatRseatInfo 
clientBuyin (RclientBuyin
	buyinTime (R	buyinTime"D
PBDominoSituationReq,
idx (2.network.cmd.RoomIndexDataRidx"~
PBDominoSituation-
player (2.network.cmd.PBPlayerRplayer

totalbuyin (R
totalbuyin
totalwin (Rtotalwin"W
PBDominoSituationResp>

situations (2.network.cmd.PBDominoSituationR
situations"É
PBDominoReviewItem-
player (2.network.cmd.PBPlayerRplayer
sid (Rsid
	handcards (R	handcards
wintype (Rwintype
win (Rwin
showcard (Rshowcard
point (Rpoint
passcnt (Rpasscnt
profit	 (Rprofit"ã
PBDominoReview
	buttonsid (R	buttonsid
ante (Rante
pot (Rpot5
items (2.network.cmd.PBDominoReviewItemRitems"K
PBDominoReviewResp5
reviews (2.network.cmd.PBDominoReviewRreviews"9
PBDominoGameReady$
readyLeftTime (RreadyLeftTime"Ó
PBDominoGameStart
gameId (RgameId
	gameState (R	gameState
	buttonSid (R	buttonSid
ante (Rante
minChip (RminChip&
tableStarttime (RtableStarttime/
seats (2.network.cmd.PBDominoSeatRseats"K
PBDominoUpdateSeat5
seatInfo (2.network.cmd.PBDominoSeatRseatInfo"C
PBDominoHandCards
sid (Rsid
	handcards (R	handcards"H
PBDominoDealCard4
cards (2.network.cmd.PBDominoHandCardsRcards"&
PBDominoUpdatePots
pot (Rpot"©
PBDominoPotInfo
sid (Rsid
winMoney (RwinMoney
	seatMoney (R	seatMoney
winType (RwinType
score (Rscore
nickname (	Rnickname
nickurl (	Rnickurl
	handcards (R	handcards
passcnt	 (Rpasscnt
profit
 (Rprofit
point (Rpoint"À
PBDominoFinalGame
potMoney (RpotMoney8
potInfos (2.network.cmd.PBDominoPotInfoRpotInfos$
readyLeftTime (RreadyLeftTime

finishType (R
finishType
winTimes (RwinTimes*Ö
PBDominoLeaveToSitState"
PBDominoLeaveToSitState_Cancel!
PBDominoLeaveToSitState_Leave#
PBDominoLeaveToSitState_Reserve*Ó
PBDominoChipinType
PBDominoChipinType_NULL
PBDominoChipinType_DISCARD
PBDominoChipinType_PASS
PBDominoChipinType_BETING
PBDominoChipinType_REBUYING

PBDominoChipinType_PRECHIPS
PBDominoChipinType_BUYING*Q
PBDominoFinishType
PBDominoFinishType_Normal
PBDominoFinishType_Death*–
PBDominoTableState
PBDominoTableState_None
PBDominoTableState_Start
PBDominoTableState_PreChips
PBDominoTableState_HandCard
PBDominoTableState_Betting
PBDominoTableState_Finish