CfgCard = CfgCard or {}

function CfgCard:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
    o:init(o.handcards, o.bordcards)
	return o
end

function CfgCard:init(handcards, boardcards)
	self.handcards = self.handcards or handcards
	self.boardcards = self.boardcards or boardcards
	self.handcards_idx = 0
	self.boardcards_idx = 0
end

function CfgCard:popHand(handcards)
	self.handcards_idx = self.handcards_idx + 1
	return self.handcards[self.handcards_idx]
end

function CfgCard:popBoard()
	self.boardcards_idx = self.boardcards_idx + 1
	return self.boardcards[self.boardcards_idx]
end

function CfgCard:getOne(idx)
	return self.boardcards[idx]
end


return CfgCard
