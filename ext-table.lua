local MyTable = {}

MyTable.new = function (self, o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	o.var1 = 10
	return o
end

MyTable.request_from_uloop = function (self)
	print("function from MyTable: " .. tostring(self.var1))
end

MyTable.query_if_telegram_avilable = function (self)
	local var1 = 22
	self:request_from_uloop()
end

return MyTable