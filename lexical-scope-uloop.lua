#!/usr/bin/env lua

require("mobdebug").start()
local my_table = require("ext-table"):new()
local uloop = require("uloop")

local var1 = 12
local var2 = 123
my_table.var2 = 13


my_table.request_from_uloop = function (self)
	do
		print("function from my_table: " .. tostring(self.var1))
		print("local var: " .. tostring(var1))
	end
end

uloop.init()
local timer

local function t()
	local ok, err
	ok, err = pcall(my_table.query_if_telegram_avilable, my_table)
	print(var1)
	if (not ok) then
		print(err)
	end
    timer:set(1000)
end
timer = uloop.timer(t, 10)

uloop.run()
