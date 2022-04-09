#!/usr/bin/env lua

-- require("mobdebug").start()
local uloop = require("uloop")
local modbus_server = require('pure-lua-modbus-server')
local log4l = require('log4l.file'); local log = log4l('/tmp/log/modbus-server.log', '%Y.%m.%d-%H:%M:%S')

local mb = require('libmodbus')
local sleep = require('socket').sleep

local mbs = modbus_server:new({unit_id=100})
mbs:add_holding_registers({base_address=1,258,772,3,4})
mbs:add_input_registers({base_address=10,258,772,3,4})
mbs:start_server()

local ok, err

local init_slave = function (slave)
	if (slave.dev) then
		slave.dev:close()
		sleep(0.1)
	end
	if (type(slave) == 'table') then
		if (slave['variant'] == 'rtu') then
			slave.dev = mb.new_rtu(conf['port'], slave['baud'], slave['parity'], slave['byte_size'], slave['stop_bit'])
			slave.dev:rtu_set_serial_mode(2)
		else
			slave.dev = mb.new_tcp_pi(slave['ip'], slave['port'])
		end
	end
	slave.dev:set_byte_timeout(2)
	slave.dev:set_response_timeout(1)
-- 	conf.dev:set_debug()
	ok, err = slave.dev:connect()
	slave.dev:set_slave(slave['unit_id'])
end

local config_slave = {ip="192.168.102.1", port=502, unit_id=1}
init_slave(config_slave)

mbs.request_from_extern_unit = function (self)
	local unit_id = self:get_unit_id_from_request()
	local fc = self:get_function_code_from_request()
	local register_address = self:get_register_address_from_request()
	local register_number = self:get_register_number_from_request()
	local return_register = {}

--	print("Request ->  u:" .. tostring(unit_id) .. " fc:" .. tostring(fc) .. " ra:" .. tostring(register_address) .. " rn:" .. tostring(register_number))
	for i=1, 2 do
		return_register, err = config_slave.dev:read_input_registers(register_address+((unit_id-1) * 20), register_number)
		if (return_register ~= nil) then
			return_register['base_address'] = register_address
			self:add_to_local_registers(return_register , fc)
			break
		else
			init_slave(config_slave)
		end
	end
end

uloop.init()
local timer
local i = i or 0

local function t()
	ok, err = pcall(mbs.query_if_telegram_avilable, mbs)
	if (not ok) then
		log:error(err)
		sleep(5)
		init_slave(config_slave)
		mbs:start_server()
	end
    timer:set(10)
end
timer = uloop.timer(t, 10)

uloop.run()
