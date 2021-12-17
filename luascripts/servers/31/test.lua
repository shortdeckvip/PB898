require("luascripts/servers/31/cowboy")

local cjson = require("cjson")
local rand = require(CLIBS["c_rand"])

local function testPoker()
	local cb = Cowboy:new()

	print('-------printCards-------')
	cb:printCards(cb:getNCard(2,2))
	
	print('-------printCards-------')
	local cardsA, cardsB = cb:getMNCard(2,2)
	cb:printCards(cardsA)
	cb:printCards(cardsB)
	
	print('-------cardColor--------')
	print(cb:cardColor(0x203))--2
	print(cb:cardColor(0x107))--1

	print('-------cardValue--------')
	print(cb:cardValue(0x203))--3
	print(cb:cardValue(0x107))--7
	
	print('-------getPokersType----')
	print(cb:getPokersType({0x104, 0x303}, {0x30B, 0x209, 0x107, 0x105, 0x40A}))
	print(cb:getPokersType({0x107, 0x303}, {0x308, 0x209, 0x106, 0x402, 0x204}))
	print(cb:getPokersType({0x203, 0x103}, {0, 0, 0, 0, 0}))
	print(cb:getPokersType({0x104, 0x10D}, {0x30B, 0x30E, 0x30C, 0x106, 0x207}))
	print(cb:getPokersType({0x302, 0x304}, {0x30B, 0x30E, 0x30C, 0x106, 0x207}))

	print('------------------')
	print(cb:isFlush(0x203, 0x103)) -- false
	print(cb:isFlush(0x103, 0x103))	-- true
	print(cb:isFlush(0x303, 0x305)) -- true
	
	print('------------------')
	print(cb:isInrow(0x303, 0x205)) -- false
	print(cb:isInrow(0x403, 0x303)) -- false
	print(cb:isInrow(0x202, 0x303)) -- true
	print(cb:isInrow(0x202, 0x40E)) -- false
	print(cb:isInrow(0x20D, 0x40E)) -- true
	
	print('------------------')
	print(cb:isPair(0x202, 0x102)) -- true
	print(cb:isPair(0x103, 0x202)) -- false
	print(cb:isPair(0x10E, 0x20E)) -- true

	print('------------------')
	print(cb:isPairA(0x202, 0x102)) -- false
	print(cb:isPairA(0x10E, 0x20E)) -- true

	print('-------getWinTypes----')
	local wintypes, winpokertype = cb:getWinTypes({0x104, 0x106,}, {0x307, 0x308,}, {0x10D, 0x102, 0x204, 0x10B, 0x305,})
	print(cjson.encode(wintypes), winpokertype)
	wintypes, winpokertype = cb:getWinTypes({0x10E, 0x20E}, {0x307, 0x308,}, {0x10D, 0x102, 0x204, 0x10B, 0x305,})
	print(cjson.encode(wintypes), winpokertype)

	local fname = tostring('test') .. os.date('%Y%m%d%H%M%S') .. '.txt'
	local f = io.open(fname, 'a+')
	--print('~~~~~~~~随机发牌~~~~~~~')
	--for i = 1, 10 do
		--f:write('------------------------\n')
		--cb:reset()
		--f:write(cb:getLeftCardsCnt() .. '\n')
		--f:write(cb:formatCards(cb.cards))
	--end
	print('~~~~~~~~随机牌型~~~~~~~')
	local winTypesCntStatistic = {}
	for i = 1, 100000 do
		f:write('------------------------\n')
		cb:reset()
		f:write(cb:getLeftCardsCnt() .. '\n')
		local cardsA, cardsB = cb:getMNCard(2, 2)
		local cardsPub = cb:getNCard(5)
		f:write('cardsA\t' .. cb:formatCards(cardsA) .. '\tcardsB\t' .. cb:formatCards(cardsB) .. '\tcardsPub\t' .. cb:formatCards(cardsPub) .. '\n')
		local pokertypeA = cb:getPokersType(cardsA, cardsPub)
		local pokertypeB = cb:getPokersType(cardsB, cardsPub)
		local winTypes, winPokerType, besthands = cb:getWinTypes(cardsA, cardsB, cardsPub)
		for _,v in ipairs(winTypes) do
			winTypesCntStatistic[v] = (winTypesCntStatistic[v] or 0) + 1
		end
		f:write('pokertypeA\t' .. pokertypeA .. '\tpokertypeB\t' .. pokertypeB .. '\twinTypes\t' .. cjson.encode(winTypes) .. '\twinPokerType\t' .. winPokerType .. '\tbesthands\t' .. cb:formatCards(besthands) .. '\n')
		f:flush()
	end
	f:write(cjson.encode(winTypesCntStatistic) .. '\n')
	f:flush()
end

--testPoker()
