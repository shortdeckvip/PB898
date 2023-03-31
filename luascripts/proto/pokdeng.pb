
≤,
pokdeng.protonetwork.cmdcommon.proto"¢
PBPokDengSeat+
seat (2.network.cmd.PBSeatInfoRseat
	isPlaying (R	isPlaying
	seatMoney (R	seatMoney

chipinType (R
chipinType 
chipinValue (RchipinValue
	handcards (R	handcards
pot (Rpot
cardtype (Rcardtype
wintimes	 (Rwintimes"ˆ
PBPokDengTableInfo
gameId (RgameId
	seatCount (R	seatCount
	tableName (	R	tableName
	gameState (R	gameState$
stateLeftTime (RstateLeftTime
	buttonSid (R	buttonSid8
	seatInfos (2.network.cmd.PBPokDengSeatR	seatInfos
chips (Rchips(
serialBankTimes	 (RserialBankTimes
	matchType
 (R	matchType

matchState (R
matchState
roomType (RroomType
toolCost (RtoolCost
ante (Rante

minbuyinbb (R
minbuyinbb

maxbuyinbb (R
maxbuyinbb 
bankertimes (Rbankertimes
	bankeruid (R	bankeruid
	addBetMin (R	addBetMin
	addBetMax (R	addBetMax&
bankerMinMoney (RbankerMinMoney(
stateTimeLength (RstateTimeLength
maxinto (Rmaxinto"W
PBPokDengTableInfoResp=
	tableInfo (2.network.cmd.PBPokDengTableInfoR	tableInfo"ã
PBPokDengOperateReq_C,
idx (2.network.cmd.RoomIndexDataRidx 
operateType (RoperateType"
operateValue (RoperateValue"ò
PBPokDengOperateResp_S
code (Rcode 
operateType (RoperateType"
operateValue (RoperateValue$
operateValue2 (RoperateValue2"]
PBPokDengBetReq_C,
idx (2.network.cmd.RoomIndexDataRidx
betValue (RbetValue"ê
PBPokDengBetResp_S
code (Rcode
sid (Rsid
betValue (RbetValue

totalValue (R
totalValue
balance (Rbalance"`
PBPokDengGetThirdCardReq_C,
idx (2.network.cmd.RoomIndexDataRidx
value (Rvalue"À
PBPokDengGetThirdCardResp_S
code (Rcode
value (Rvalue
cards (Rcards
totalBet (RtotalBet
balance (Rbalance
cardtype (Rcardtype
wintimes (Rwintimes"{
PBPokDengGetThirdCardNotify
sid (Rsid
value (Rvalue
totalBet (RtotalBet
balance (Rbalance"å
PBPokDengPlayerSit6
seatInfo (2.network.cmd.PBPokDengSeatRseatInfo 
clientBuyin (RclientBuyin
	buyinTime (R	buyinTime"E
PBPokDengSituationReq,
idx (2.network.cmd.RoomIndexDataRidx"
PBPokDengSituation-
player (2.network.cmd.PBPlayerRplayer

totalbuyin (R
totalbuyin
totalwin (Rtotalwin"Y
PBPokDengSituationResp?

situations (2.network.cmd.PBPokDengSituationR
situations"º
PBPokDengReviewItem-
player (2.network.cmd.PBPlayerRplayer
sid (Rsid
	handcards (R	handcards
wintype (Rwintype
win (Rwin
showcard (Rshowcard"ç
PBPokDengReview
	buttonsid (R	buttonsid
ante (Rante
pot (Rpot6
items (2 .network.cmd.PBPokDengReviewItemRitems"M
PBPokDengReviewResp6
reviews (2.network.cmd.PBPokDengReviewRreviews":
PBPokDengGameReady$
readyLeftTime (RreadyLeftTime"≤
PBPokDengGameStart
gameId (RgameId
	gameState (R	gameState
	buttonSid (R	buttonSid
ante (Rante
chiplist (Rchiplist&
tableStarttime (RtableStarttime0
seats (2.network.cmd.PBPokDengSeatRseats 
bankertimes (Rbankertimes
	bankeruid	 (R	bankeruid"?
PBPokDengUpdateBanker
sid (Rsid
count (Rcount"P
PBPokDengStateInfo
state (Rstate$
stateLeftTime (RstateLeftTime"M
PBPokDengUpdateSeat6
seatInfo (2.network.cmd.PBPokDengSeatRseatInfo"|
PBPokDengHandCards
sid (Rsid
	handcards (R	handcards
cardtype (Rcardtype
wintimes (Rwintimes"É
PBPokDengCardInfo
uid (Ruid
sid (Rsid
card (Rcard
cardtype (Rcardtype
wintimes (Rwintimes"Ü
PBPokDengDealCard5
cards (2.network.cmd.PBPokDengHandCardsRcards:
allCards (2.network.cmd.PBPokDengCardInfoRallCards"'
PBPokDengUpdatePots
pot (Rpot"Ë
PBPokDengPotInfo
sid (Rsid
winMoney (RwinMoney
	seatMoney (R	seatMoney
winType (RwinType
winTimes (RwinTimes
nickname (	Rnickname
nickurl (	Rnickurl
	handcards (R	handcards"u
PBPokDengFinalGame9
potInfos (2.network.cmd.PBPokDengPotInfoRpotInfos$
readyLeftTime (RreadyLeftTime"v
PBPokDengBetData
uid (Ruid
	usertotal (R	usertotal
betarea (Rbetarea
balance (Rbalance"Q
PBPokDengNotifyBettingInfo_N1
bets (2.network.cmd.PBPokDengBetDataRbets"O
PBPokDengShowCard:
allCards (2.network.cmd.PBPokDengCardInfoRallCards*è
PBPokDengCardType
PokDengCardType_Normal%
!PokDengCardType_TwoSameColorValue
PokDengCardType_SameColor
PokDengCardType_Serial#
PokDengCardType_SameColorSerial
PokDengCardType_ThreeYellow"
PokDengCardType_ThreeSamePoint'
#PokDengCardType_8_NotSameColorValue$
 PokDengCardType_8_SameColorValue	"
PokDengCardType_9_NotSameColor

PokDengCardType_9_SameColor*Ô
PBPokDengChipinType
PBPokDengChipinType_NULL
PBPokDengChipinType_BETING
PBPokDengChipinType_BET
PBPokDengChipinType_Getting
PBPokDengChipinType_Get
PBPokDengChipinType_Buying
PBPokDengChipinType_Showing*s
PBPokDengGetType
PBPokDengGetType_Double!
PBPokDengGetType_GetThirdCard
PBPokDengGetType_NotGetCard*ˆ
PBPokDengTableState
PBPokDengTableState_None
PBPokDengTableState_Start
PBPokDengTableState_Bet 
PBPokDengTableState_DealCard!
PBPokDengTableState_ThirdCard 
PBPokDengTableState_ShowCard
PBPokDengTableState_Finish