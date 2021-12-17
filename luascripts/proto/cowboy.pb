
Ø 
cowboy.protonetwork.cmdcommon.proto"Å
PBCowboyNotifyStart_N
t (Rt
roundid (Rroundid"
needclearlog (Rneedclearlog
	onlinenum (R	onlinenum"#
PBCowboyNotifyBet_N
t (Rt"µ
PBCowboyBetArea
bettype (Rbettype
betvalue (Rbetvalue$
userareatotal (Ruserareatotal
	areatotal (R	areatotal
iswin (Riswin
odds (Rodds"ì
PBCowboyBetData
uid (Ruid
	usertotal (R	usertotal6
areabet (2.network.cmd.PBCowboyBetAreaRareabet
balance (Rbalance"r
PBCowboyBetReq_C,
idx (2.network.cmd.RoomIndexDataRidx0
data (2.network.cmd.PBCowboyBetDataRdata"Y
PBCowboyBetResp_S
code (Rcode0
data (2.network.cmd.PBCowboyBetDataRdata"e
PBCowboyTypeStatisticData
type (Rtype
hitcount (Rhitcount
lasthit (Rlasthit"O
PBCowboyLogData
wintype (Rwintype"
winpokertype (Rwinpokertype"S
PBCowboyPokerData*
cards (2.network.cmd.PBPokerRcards
type (Rtype"†
PBCowboyNotifyShow_N6
cowboy (2.network.cmd.PBCowboyPokerDataRcowboy2
bull (2.network.cmd.PBCowboyPokerDataRbull0
pub (2.network.cmd.PBCowboyPokerDataRpub8
areainfo (2.network.cmd.PBCowboyBetAreaRareainfo0
bestFive (2.network.cmd.PBPokerRbestFive"≠
PBCowboyNotifyFinish_N)
ranks (2.network.cmd.PBRankRranks.
log (2.network.cmd.PBCowboyLogDataRlog8
sta (2&.network.cmd.PBCowboyTypeStatisticDataRsta"O
PBCowboyNotifyBettingInfo_N0
bets (2.network.cmd.PBCowboyBetDataRbets"D
PBCowboyHistoryReq_C,
idx (2.network.cmd.RoomIndexDataRidx"É
PBCowboyHistoryResp_S0
logs (2.network.cmd.PBCowboyLogDataRlogs8
sta (2&.network.cmd.PBCowboyTypeStatisticDataRsta"G
PBCowboyOnlineListReq_C,
idx (2.network.cmd.RoomIndexDataRidx"w
PBCowboyOnlineList-
player (2.network.cmd.PBPlayerRplayer
wincnt (Rwincnt
totalbet (Rtotalbet"O
PBCowboyOnlineListResp_S3
list (2.network.cmd.PBCowboyOnlineListRlist"§
PBCowboyData
state (Rstate
lefttime (Rlefttime
roundid (Rroundid
jackpot (Rjackpot-
player (2.network.cmd.PBPlayerRplayer-
seats (2.network.cmd.PBSeatInfoRseats0
logs (2.network.cmd.PBCowboyLogDataRlogs8
sta (2&.network.cmd.PBCowboyTypeStatisticDataRsta6
betdata	 (2.network.cmd.PBCowboyBetDataRbetdata6
cowboy
 (2.network.cmd.PBCowboyPokerDataRcowboy2
bull (2.network.cmd.PBCowboyPokerDataRbull0
pub (2.network.cmd.PBCowboyPokerDataRpub 
configchips (Rconfigchips
	onlinenum (R	onlinenum
odds (Rodds:
bestFive (2.network.cmd.PBCowboyPokerDataRbestFive"°
PBIntoCowboyRoomResp_S
code (Rcode
gameid (Rgameid,
idx (2.network.cmd.RoomIndexDataRidx-
data (2.network.cmd.PBCowboyDataRdata*É
EnumCowboyPokerCount
EnumCowboyPokerCount_2
EnumCowboyPokerCount_3
EnumCowboyPokerCount_4
EnumCowboyPokerCount_5
EnumCowboyPokerCount_6
EnumCowboyPokerCount_7
EnumCowboyPokerCount_8
EnumCowboyPokerCount_9	
EnumCowboyPokerCount_10

EnumCowboyPokerCount_J
EnumCowboyPokerCount_Q
EnumCowboyPokerCount_K
EnumCowboyPokerCount_A*Í
EnumCowboyPokerType 
EnumCowboyPokerType_HighCard
EnumCowboyPokerType_Pair
EnumCowboyPokerType_TwoPair!
EnumCowboyPokerType_ThreeKind 
EnumCowboyPokerType_Straight
EnumCowboyPokerType_Flush!
EnumCowboyPokerType_FullHouse 
EnumCowboyPokerType_FourKind	%
!EnumCowboyPokerType_StraightFlush
"
EnumCowboyPokerType_RoyalFlush*ö
EnumCowboyState
EnumCowboyState_Check
EnumCowboyState_Start
EnumCowboyState_Betting
EnumCowboyState_Show
EnumCowboyState_Finish*“
EnumCowboyType
EnumCowboyType_Cowboy
EnumCowboyType_Bull
EnumCowboyType_Draw
EnumCowboyType_FlushInRow
EnumCowboyType_Pair
EnumCowboyType_PairA
EnumCowboyType_HighCardPair
EnumCowboyType_TwoPair#
EnumCowboyType_ThrKndStrghtFlsh	
EnumCowboyType_FullHouse
!
EnumCowboyType_BeyondFourKind