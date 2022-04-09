#!/usr/bin/env lua

--------------- private ---------------
local bit = require("bit")
local math = require("math")
local socket = require("socket")

local MbSrv = {}

--- constants ---
local START_BYTE_PAYLOAD = 10

--------------- public ---------------
MbSrv.new = function (self, o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	-- instants variables
	o.unit_id = o.unit_id or 1
	o.request = {}
	o.response = {}
	o.input_registers = {}
	o.holding_registers = {}
	o.byte_number_register = 0
	return o
end

--- beginn functions for request telegram ---
MbSrv.verify_request = function (self)
	return (self.request[3] + self.request[4] == 0) and (self.request[5] * 0x100 + self.request[6] == #self.request - 6)
end

MbSrv.get_transaction_id_from_request = function (self)
	return self.request[1] * 0x100 + self.request[2]
end

MbSrv.get_message_length_from_request = function (self)
	return self.request[5] * 0x100 + self.request[6]
end

MbSrv.get_unit_id_from_request = function (self)
	return self.request[7]
end

MbSrv.get_function_code_from_request = function (self)
	return self.request[8]
end

MbSrv.get_register_address_from_request = function (self)
	return self.request[9] * 0x100 + self.request[10]
end

MbSrv.get_register_number_from_request = function (self)
	return self.request[11] * 0x100 + self.request[12]
end

MbSrv.convert_request = function (self)
	self.request = {}
	string.gsub(self.request_raw, "(.)", function(s) self.request[#self.request + 1] = string.byte(s) end)
	return self.request
end

--- beginn functions for add to intern registers ---
MbSrv.add_to_local_registers = function (self, register, fc)
	local register_base_address = register.base_address
	local register_number = #register
	local unit_id = self:get_unit_id_from_request() or self.unit_id

	for i,v in ipairs(register) do
		if (fc == 3) then
			self.holding_registers[unit_id] = self.holding_registers[unit_id] or {}
			self.holding_registers[unit_id][register_base_address + (i-1)] = tonumber(v)
		elseif (fc == 4) then
			self.input_registers[unit_id] = self.input_registers[unit_id] or {}
			self.input_registers[unit_id][register_base_address + (i-1)] = tonumber(v)
		end
	end
end

MbSrv.add_holding_registers = function (self, register)
       self:add_to_local_registers(register, 3)
end

MbSrv.add_input_registers = function (self, register)
       self:add_to_local_registers(register, 4)
end

--- beginn functions for response telegram ---
MbSrv.init_response_telegram = function (self, as_exception)
	self.response = {}
	local l = 0
	if (not as_exception) then
		l = self:calc_response_payload_length()
	end
	
	self.response[1] = self.request[1]						-- transaction -> high
	self.response[2] = self.request[2]						-- transaction -> low
	self.response[3] = self.request[3]						-- protocol -> high
	self.response[4] = self.request[4]						-- protocol -> low
	self.response[5] = bit.rshift(bit.band(l, 0xff00), 8)	-- length header and payload -> high
	self.response[6] = bit.band(l, 0xff) + 3				-- length header and payload -> low
	self.response[7] = self.request[7]     					-- unit_id
	if (as_exception) then									-- function_code
		self.response[8] = bit.bor(self.request[8] ,0x80)
	else
		self.response[8] = self.request[8]
		self.response[9] = l								-- length payload
	end

	return self.response
end

MbSrv.calc_response_payload_length = function (self)
	local fc = self:get_function_code_from_request()
	if (fc == 1 or fc == 2) then

	elseif (fc == 3 or fc == 4) then
		self.byte_number_register = self:get_register_number_from_request() * 2
	else

	end
	return self.byte_number_register
end

MbSrv.add_payload_to_response = function (self)
	-- delete old registers
	for i=START_BYTE_PAYLOAD, #self.response do
		self.response[i] = nil
	end

	local ret_value = true
	local ui = self:get_unit_id_from_request()
	local addr = self:get_register_address_from_request()
	local n = self:get_register_number_from_request()
	local fc = self:get_function_code_from_request()
	
	if (ui ~= self.unit_id) then
		self:request_from_extern_unit()
	end
	local id = START_BYTE_PAYLOAD
	if (fc == 3) then
		for i=addr, addr + n - 1 do
			local v = self.holding_registers[ui][i]
			if (type(v) == 'number') then
				self.response[id] = bit.rshift(v, 8)
				self.response[id+1] = bit.band(v, 0xff)
			else
				self:set_response_exception_code(2)
				ret_value = false
				break
			end
			id = id + 2
		end
	elseif (fc == 4) then
		for i=addr, addr + n - 1 do		
			local v = self.input_registers[ui][i]
			if (type(v) == 'number') then
				self.response[id] = bit.rshift(v, 8)
				self.response[id+1] = bit.band(v, 0xff)
			else
				self:set_response_exception_code(2)
				ret_value = false
				break
			end
			id = id + 2
		end
	else
		self:set_response_exception_code(1)
		ret_value = false
	end
	return ret_value
end

MbSrv.set_response_exception_code = function (self, exception_code)
	self:init_response_telegram(true)
	self.response[9] = tonumber(exception_code)
	return true
end

MbSrv.request_from_extern_unit = function (self)
        self:set_response_exception_code(1)
end

--[[ throw exception
    MODBUS_EXCEPTION_ILLEGAL_FUNCTION = 0x01,
    MODBUS_EXCEPTION_ILLEGAL_DATA_ADDRESS,
    MODBUS_EXCEPTION_ILLEGAL_DATA_VALUE,
    MODBUS_EXCEPTION_SLAVE_OR_SERVER_FAILURE,
    MODBUS_EXCEPTION_ACKNOWLEDGE,
    MODBUS_EXCEPTION_SLAVE_OR_SERVER_BUSY,
    MODBUS_EXCEPTION_NEGATIVE_ACKNOWLEDGE,
    MODBUS_EXCEPTION_MEMORY_PARITY,
    MODBUS_EXCEPTION_NOT_DEFINED,
    MODBUS_EXCEPTION_GATEWAY_PATH,
    MODBUS_EXCEPTION_GATEWAY_TARGET,
    MODBUS_EXCEPTION_MAX
--]]

MbSrv.replay = function (self)
	local s = ""
	local debug_s = ""
	for i,v in ipairs(self.response) do
		s = s .. string.char(v)
		debug_s = debug_s .. tostring(v) .. ":"
	end
	self.client:send(s)
--	print("response: " .. debug_s)
end

MbSrv.start_server = function (self, port)
	port = port or 502
	
	if (self.client) then
		self.client:close()
	end
	if (self.server) then
		self.server:close()
	end

	self.server = assert(socket.bind("*", port))

	self.client = self.server:accept()
	self.client:settimeout(0, 'b')
	self.client:settimeout(10, 't')

	return true
end

MbSrv.query_if_telegram_avilable = function (self)
	local ret_msg, req = nil, {}
	req[1], ret_msg  = self.client:receive(6)
	if (ret_msg == 'closed') then
		self.client = self.server:accept()
	else
		if (req[1]) then
			if (#req[1] == 6) then
				local message_length = string.byte(string.sub(req[1], 6, 6))
				req[2], ret_msg = self.client:receive(message_length)
				if (req[2]) then
					if (#req[2] == message_length) then
						self.request_raw = req[1] .. req[2]
						self:convert_request()
						if (self:verify_request()) then
							self:init_response_telegram()
							self:add_payload_to_response()
							self:replay()
						else
							error("verify error")
						end
					else
						error("request to short")
					end
				else
					error("request to short")
				end
			else
				error("request to short")
			end
		end
	end
end

return MbSrv

