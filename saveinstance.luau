--!optimize 1
-- * optimize 1, not 2: Luau's -O2 inliner miscompiles code like `x = f({ obj = x })` (the new table is
-- * written into x before x is read), which broke the built-in decompiler on executors. No --!native
-- * either: it switches the compiler to -O2 by itself.
--!divine-intellect
-- https://discord.gg/wx4ThpAsmw

local function string_find(s, pattern)
	return string.find(s, pattern, nil, true)
end

local function ArrayToDict(t, hydridMode, valueOverride, typeStrict)
	local tmp = {}

	if hydridMode then
		for any1, any2 in t do
			if type(any1) == "number" then
				tmp[any2] = valueOverride or true
			elseif type(any2) == "table" then
				tmp[any1] = ArrayToDict(any2, hydridMode) -- any1 is Class, any2 is Name
			else
				tmp[any1] = any2
			end
		end
	else
		for _, key in t do
			if not typeStrict or typeStrict and type(key) == typeStrict then
				tmp[key] = true
			end
		end
	end

	return tmp
end

local global_container
do
	local filename = "UniversalMethodFinder"

	local finder
	finder, global_container = loadstring(
		game:HttpGet("https://raw.githubusercontent.com/luau/SomeHub/main/" .. filename .. ".luau", true),
		filename
	)()

	finder({
		-- readbinarystring = 'string.find(...,"bin",nil,true)', -- ! Could match some unwanted stuff (getbinaryindex)
		-- request = 'string.find(...,"request",nil,true) and not string.find(...,"internal",nil,true)',
		base64encode = 'local a={...}local b=a[1]local function c(a,b)return string.find(a,b,nil,true)end;return c(b,"encode")and(c(b,"base64")or c(string.lower(tostring(a[2])),"base64"))',
		-- cloneref = 'string.find(...,"clone",nil,true) and string.find(...,"ref",nil,true)',
		-- decompile = '(string.find(...,"decomp",nil,true) and string.sub(...,#...) ~= "s")',
		gethiddenproperty = 'string.find(...,"get",nil,true) and string.find(...,"h",nil,true) and string.find(...,"prop",nil,true) and string.sub(...,#...) ~= "s"',
		gethui = 'string.find(...,"get",nil,true) and string.find(...,"h",nil,true) and string.find(...,"ui",nil,true)',
		-- getcon = 'string.find(...,"get",nil,true) and (string.find(...,"conn",nil,true) or string.find(...,"sig",nil,true)) and string.sub(...,#(...))=="s"',
		getnilinstances = 'string.find(...,"nil",nil,true) and string.find(...,"get",nil,true) and string.sub(...,#...) == "s"', -- ! Could match some unwanted stuff
		getscriptbytecode = 'string.find(...,"get",nil,true) and string.find(...,"bytecode",nil,true)', --  or string.find(...,"dump",nil,true) and string.find(...,"string",nil,true) due to Fluxus (dumpstring returns a function)
		hash = 'local a={...}local b=a[1]local function c(a,b)return string.find(a,b,nil,true)end;return c(b,"hash")and c(string.lower(tostring(a[2])),"crypt")',
		protectgui = 'string.find(...,"protect",nil,true) and string.find(...,"ui",nil,true) and not string.find(...,"un",nil,true)',
		setthreadidentity = 'string.find(...,"identity",nil,true) and string.find(...,"set",nil,true)',
	}, true, 10)
end

local identify_executor = identifyexecutor or getexecutorname or whatexecutor

local EXECUTOR_NAME = identify_executor and identify_executor() or ""

-- local cloneref = global_container.cloneref
local gethiddenproperty = global_container.gethiddenproperty

-- These should be universal enough
local appendfile = appendfile
local readfile = readfile
local writefile = writefile

local getscriptbytecode = global_container.getscriptbytecode -- * A lot of assumptions are made based on whether this function is defined or not. So in certain edge cases, like if the executor defines "decompile" or "getscripthash" function yet doesn't define this function there might be loss of functionality of the saveinstance. Although that would be very rare and weird
local base64encode = global_container.base64encode
local sha384

local service = setmetatable({}, {
	__index = function(self, serviceName)
		local o, s = pcall(Instance.new, serviceName)
		local Service = o and s
			or game:GetService(serviceName)
			or settings():GetService(serviceName)
			or UserSettings():GetService(serviceName)

		-- if cloneref then
		-- 	Service = cloneref(Service)
		-- end
		if Service then
			self[serviceName] = Service
		end
		return Service
	end,
})

local gethiddenproperty_fallback
do -- * Load Region of Déjà Vu
	local UGCValidationService -- = service.UGCValidationService

	gethiddenproperty_fallback = function(instance, propertyName)
		if not UGCValidationService then
			UGCValidationService = service.UGCValidationService
		end
		return UGCValidationService:GetPropertyValue(instance, propertyName) -- TODO Sadly there's no way to tell whether value is actually nil or the function just couldn't read it (always returns nil for "Class" category properties)
		-- TODO `category ~= "Class"` causes WeldConstraint Part1Internal to be read as nil and not get unfiltered. Currently, there are no properties of category "Class" that match the following: NotScriptable, can be read with gethiddenproperty_fallback accurately (it always outputs nil for "Class" category, making that check useless anyway) & don't have a NotScriptableFix.
	end
	if gethiddenproperty and EXECUTOR_NAME ~= "Velocity" then -- Velocity fails due to enums not being supported, but BinaryString and SharedString still are (handled later)
		local o, r = pcall(gethiddenproperty, workspace, "StreamOutBehavior")
		if not o or r ~= nil and typeof(r) ~= "EnumItem" then -- * Tests if gethiddenproperty is broken
			gethiddenproperty = nil
		else
			o, r = pcall(gethiddenproperty, Instance.new("AnimationRigData", Instance.new("Folder")), "parent") -- * Tests how it reacts to property overlap (shadowing) due to AnimationRigData.parent; expected BinaryString

			if o and r ~= nil and type(r) ~= "string" then
				gethiddenproperty = nil
			end
		end
	end
	
	--if getspecialinfo and not gethiddenproperty then
	--	local specialinfoindex = {
	--		MeshPart = {"PhysicsData", "InitialSize"},
	--		UnionOperation = {"AssetId", "ChildData", "FormFactor", "InitialSize", "MeshData", "PhysicsData"}, -- MeshData is no longer used, superseded by MeshData2, but ill leave it in. More info: https://devforum.roblox.com/t/research-on-csg/3554504
	--		Terrain = { "SmoothGrid", "MaterialColors" },
	--	}
	--	local function getspecialinfo_benchmark()
	--		local success, returned = pcall(getspecialinfo, workspace.Terrain)
	--		if success then
	--			return true
	--		end
	--	end
	--	if getspecialinfo_benchmark() == true then
	--		getspecinfo_ghp_fallback = function(instance, propertyName)
	--			if specialinfoindex[instance.ClassName] and ArrayToDict(specialinfoindex[instance.ClassName])[propertyName] then
	--				local ok, result = pcall(getspecialinfo, instance)
	--				if ok then
	--					return result[propertyName], true
	--				else
	--					return "can't get value" -- forces filterPropVal to fail
	--				end	
	--			else
	--				return "can't get value"
	--			end
	--		end
	--	end
	--end
	
	local function benchmark(f1, f2, ...)
		local ranking = table.create(2)
		for i, f in { f1, f2 } do
			local start = os.clock()
			for _ = 1, 50 do
				f(...)
			end
			ranking[i] = { t = os.clock() - start, f = f }
		end
		table.sort(ranking, function(a, b)
			return a.t < b.t
		end)
		return ranking[1].f
	end

	local test_str = string.rep("\1\0\0\0\1\2\3\4\5\6\7", 50)

	do
		if not bit32.byteswap or not pcall(bit32.byteswap, 1) then -- Because Fluxus is missing byteswap
			bit32 = table.clone(bit32)

			local function tobit(num)
				num %= (bit32.bxor(num, 32))
				if 0x80000000 < num then
					num -= bit32.bxor(num, 32)
				end
				return num
			end

			bit32.byteswap = function(num)
				local BYTE_SIZE = 8
				local MAX_BYTE_VALUE = 255

				num %= bit32.bxor(2, 32)

				local a = bit32.band(num, MAX_BYTE_VALUE)
				num = bit32.rshift(num, BYTE_SIZE)

				local b = bit32.band(num, MAX_BYTE_VALUE)
				num = bit32.rshift(num, BYTE_SIZE)

				local c = bit32.band(num, MAX_BYTE_VALUE)
				num = bit32.rshift(num, BYTE_SIZE)

				local d = bit32.band(num, MAX_BYTE_VALUE)
				num = tobit(bit32.lshift(bit32.lshift(bit32.lshift(a, BYTE_SIZE) + b, BYTE_SIZE) + c, BYTE_SIZE) + d)
				return num
			end

			table.freeze(bit32)
		end

		-- Credits @Reselim
		local reselim_base64encode
		pcall(function()
			local b64_enc_buf = loadstring(
				game:HttpGet("https://raw.githubusercontent.com/Reselim/Base64/master/Base64.lua", true),
				"Base64"
			)().encode
			reselim_base64encode = function(raw)
				return buffer.tostring(b64_enc_buf(buffer.fromstring(raw)))
			end
		end)

		-- * Tests if base64encode exists and works properly then benchmark it
		if base64encode and base64encode("\1\0\0\0\1") == "AQAAAAE=" then
			if reselim_base64encode then
				base64encode = benchmark(base64encode, reselim_base64encode, test_str)
			end
		else
			base64encode = reselim_base64encode
		end

		assert(base64encode, "base64encode not found")
	end

	do
		local hash = global_container.hash

		if hash then
			-- * only if it hashes the whole input (a C-string implementation stops at the first zero byte)
			local ok, same = pcall(function()
				return hash("a\0b", "sha384") == hash("a\0c", "sha384")
			end)
			if ok and same == false then
				sha384 = function(data)
					return hash(data, "sha384")
				end
			end
		end

		local filename = "RequireOnlineModule"

		-- Credits @boatbomber
		local hashlib_sha384
		pcall(function()
			hashlib_sha384 = loadstring(
				game:HttpGet("https://raw.githubusercontent.com/luau/SomeHub/main/" .. filename .. ".luau", true),
				filename
			)()(4544052033).sha384
		end)

		-- * Tests if sha384 exists then benchmark it
		if hashlib_sha384 then
			if sha384 then
				sha384 = benchmark(sha384, hashlib_sha384, test_str)
			else
				sha384 = hashlib_sha384
			end
		end

		assert(sha384, "sha384 hash function not found")
	end
end

local SharedStrings = {}
local SharedString_identifiers = setmetatable({
	identifier = 1e15, -- 1 quadrillion, up to 9.(9) quadrillion, in theory this shouldn't ever run out and be enough for all sharedstrings ever imaginable
	-- TODO: worst case, add fallback to str randomizer once numbers run out : )
}, {
	__index = function(self, str)
		local Identifier = base64encode(tostring(self.identifier)) -- tostring is only needed for built-in base64encode, Reselim's doesn't need it as buffers autoconvert
		self.identifier += 1

		self[str] = Identifier -- ? The value of the md5 attribute is a Base64-encoded key. <SharedString> type elements use this key to refer to the value of the string. The value is the text content, which is Base64-encoded. Historically, the key was the MD5 hash of the string value. However, this is not required; the key can be any value that will uniquely identify the shared string. Roblox currently uses BLAKE2b truncated to 16 bytes..
		return Identifier
	end,
})

local inherited_properties = {}
local notsaveable_inherited_properties = {}
local notcreatablefixes_inherited_properties = {}
local default_instances = {}
local referents, ref_size = {}, 0 -- ? Roblox encodes all <Item> elements with a referent attribute. Each value is generated by starting with the prefix RBX, followed by a UUID version 4, with - characters removed, and all characters converted to uppercase.

local function __BIT(...) -- * Credits to Friend (you know yourself)
	local Value = 0

	for i, bit in { ... } do
		if bit then
			Value += 2 ^ (i - 1)
		end
	end

	return Value
end

local function GetRef(instance)
	local ref = referents[instance]
	if not ref then
		ref = ref_size
		referents[instance] = ref
		ref_size += 1
	end
	return ref
end

local function index(self, index_name)
	return self[index_name]
end

local function gsubCaseInsensitive(input, search, replacement) -- * Credits to friends
	local inputLower = string.lower(input)

	search = string.lower(search)

	local lastFinish = 0
	local subStrings = {}
	local search_len = #search
	local input_len = #input
	while search_len <= input_len - lastFinish do
		local init = lastFinish + 1

		local start, finish = string.find(inputLower, search, init, true)

		if start == nil then
			break
		end

		table.insert(subStrings, string.sub(input, init, start - 1))

		lastFinish = finish
	end

	if lastFinish == 0 then
		return input
	end

	table.insert(subStrings, string.sub(input, lastFinish + 1))

	return table.concat(subStrings, replacement)
end

local CLIENT_VERSION = tonumber(string.split(version(), ".")[2])

local attr_Type_IDs = {
	string = 0x02,
	boolean = 0x03,
	-- int32 = 0x04,
	-- float = 0x05,
	number = 0x06,
	-- Array = 0x07,
	-- Dictionary = 0x08,
	UDim = 0x09,
	UDim2 = 0x0A,
	Ray = 0x0B,
	Faces = 0x0C,
	Axes = 0x0D,
	BrickColor = 0x0E,
	Color3 = 0x0F,
	Vector2 = 0x10,
	Vector3 = 0x11,
	Vector2int16 = 0x12,
	Vector3int16 = 0x13,
	CFrame = 0x14,
	EnumItem = 0x15,
	NumberSequence = 0x17,
	NumberSequenceKeypoint = 0x18,
	ColorSequence = 0x19,
	ColorSequenceKeypoint = 0x1A,
	NumberRange = 0x1B,
	Rect = 0x1C,
	PhysicalProperties = 0x1D,
	Region3 = 0x1F,
	Region3int16 = 0x20,
	Font = 0x21,
}
local CFrame_Rotation_IDs = {
	["\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63"] = 0x02,
	["\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0\0\0\128\63\0\0\0\0"] = 0x03,
	["\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191"] = 0x05,
	["\0\0\128\63\0\0\0\0\0\0\0\128\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0\0\0\128\191\0\0\0\0"] = 0x06,
	["\0\0\0\0\0\0\128\63\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191"] = 0x07,
	["\0\0\0\0\0\0\0\0\0\0\128\63\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0"] = 0x09,
	["\0\0\0\0\0\0\128\191\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\128\0\0\0\0\0\0\0\0\0\0\128\63"] = 0x0a,
	["\0\0\0\0\0\0\0\0\0\0\128\191\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0"] = 0x0c,
	["\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63\0\0\128\63\0\0\0\0\0\0\0\0"] = 0x0d,
	["\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0\0\0\128\63\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\0"] = 0x0e,
	["\0\0\0\0\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191\0\0\128\63\0\0\0\0\0\0\0\0"] = 0x10,
	["\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0\0\0\128\191\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\128"] = 0x11,
	["\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191"] = 0x14,
	["\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0\0\0\128\63\0\0\0\128"] = 0x15,
	["\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63"] = 0x17,
	["\0\0\128\191\0\0\0\0\0\0\0\128\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0\0\0\128\191\0\0\0\128"] = 0x18,
	["\0\0\0\0\0\0\128\63\0\0\0\128\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63"] = 0x19,
	["\0\0\0\0\0\0\0\0\0\0\128\191\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0"] = 0x1b,
	["\0\0\0\0\0\0\128\191\0\0\0\128\0\0\128\191\0\0\0\0\0\0\0\128\0\0\0\0\0\0\0\0\0\0\128\191"] = 0x1c,
	["\0\0\0\0\0\0\0\0\0\0\128\63\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0"] = 0x1e,
	["\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191\0\0\128\191\0\0\0\0\0\0\0\0"] = 0x1f,
	["\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0\0\0\128\63\0\0\0\128\0\0\128\191\0\0\0\0\0\0\0\0"] = 0x20,
	["\0\0\0\0\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63\0\0\128\191\0\0\0\0\0\0\0\0"] = 0x22,
	["\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0\0\0\128\191\0\0\0\128\0\0\128\191\0\0\0\0\0\0\0\128"] = 0x23,
}
local Binary_Descriptors
Binary_Descriptors = {
	__SEQUENCE = function(raw, valueFormatter, keypointSize, Envelope)
		local Keypoints = raw.Keypoints
		local Keypoints_n = #Keypoints

		local len = 4 + (keypointSize or 12) * Keypoints_n
		local b = buffer.create(len)
		local offset = 0

		buffer.writeu32(b, offset, Keypoints_n)
		offset += 4

		for _, keypoint in Keypoints do
			buffer.writef32(b, offset, Envelope or keypoint.Envelope)
			offset += 4
			buffer.writef32(b, offset, keypoint.Time)
			offset += 4

			local Value = keypoint.Value
			if valueFormatter then
				offset += valueFormatter(Value, b, offset)
			else
				buffer.writef32(b, offset, Value)
				offset += 4
			end
		end

		return b, len
	end,
	--------------------------------------------------------------
	--------------------------------------------------------------
	--------------------------------------------------------------
	["string"] = function(raw)
		local raw_len = #raw
		local len = 4 + raw_len

		local b = buffer.create(len)

		buffer.writeu32(b, 0, raw_len)
		buffer.writestring(b, 4, raw)

		return b, len
	end,
	["boolean"] = function(raw)
		local b = buffer.create(1)

		buffer.writeu8(b, 0, raw and 1 or 0)

		return b, 1
	end,
	["number"] = function(raw) -- double
		local b = buffer.create(8)

		buffer.writef64(b, 0, raw)

		return b, 8
	end,
	["UDim"] = function(raw)
		local b = buffer.create(8)

		buffer.writef32(b, 0, raw.Scale)
		buffer.writei32(b, 4, raw.Offset)

		return b, 8
	end,
	["UDim2"] = function(raw)
		local b = buffer.create(16)

		local UDim__descriptor = Binary_Descriptors.UDim
		local X = UDim__descriptor(raw.X)
		buffer.copy(b, 0, X)
		local Y = UDim__descriptor(raw.Y)
		buffer.copy(b, 8, Y)

		return b, 16
	end,
	["Ray"] = function(raw)
		local b = buffer.create(24)

		local Vector3__descriptor = Binary_Descriptors.Vector3
		local Origin = Vector3__descriptor(raw.Origin)
		buffer.copy(b, 0, Origin)
		local Direction = Vector3__descriptor(raw.Direction)
		buffer.copy(b, 12, Direction)

		return b, 24
	end,
	["Faces"] = function(raw)
		local b = buffer.create(4)

		buffer.writeu32(b, 0, __BIT(raw.Right, raw.Top, raw.Back, raw.Left, raw.Bottom, raw.Front))

		return b, 4
	end,
	["Axes"] = function(raw)
		local b = buffer.create(4)

		buffer.writeu32(b, 0, __BIT(raw.X, raw.Y, raw.Z))

		return b, 4
	end,
	["BrickColor"] = function(raw)
		local b = buffer.create(4)

		buffer.writeu32(b, 0, raw.Number)

		return b, 4
	end,
	["Color3"] = function(raw)
		local b = buffer.create(12)

		buffer.writef32(b, 0, raw.R)
		buffer.writef32(b, 4, raw.G)
		buffer.writef32(b, 8, raw.B)

		return b, 12
	end,
	["Vector2"] = function(raw)
		local b = buffer.create(8)

		buffer.writef32(b, 0, raw.X)
		buffer.writef32(b, 4, raw.Y)

		return b, 8
	end,
	["Vector3"] = function(raw)
		local b = buffer.create(12)

		buffer.writef32(b, 0, raw.X)
		buffer.writef32(b, 4, raw.Y)
		buffer.writef32(b, 8, raw.Z)

		return b, 12
	end,
	["Vector2int16"] = function(raw)
		local b = buffer.create(4)

		buffer.writei16(b, 0, raw.X)
		buffer.writei16(b, 2, raw.Y)

		return b, 4
	end,
	["Vector3int16"] = function(raw)
		local b = buffer.create(6)

		buffer.writei16(b, 0, raw.X)
		buffer.writei16(b, 2, raw.Y)
		buffer.writei16(b, 4, raw.Z)

		return b, 6
	end,
	["CFrame"] = function(raw)
		local X, Y, Z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = raw:GetComponents()

		local rotation_ID = CFrame_Rotation_IDs[string.pack("<fffffffff", R00, R01, R02, R10, R11, R12, R20, R21, R22)]

		local len = rotation_ID and 13 or 49
		local b = buffer.create(len)

		-- ? TODO cleaner but slower ?
		-- local write_vector3 = Descriptors.Vector3
		-- local pos = write_vector3(raw.Position)
		-- buffer.copy(b, 0, pos)

		buffer.writef32(b, 0, X)
		buffer.writef32(b, 4, Y)
		buffer.writef32(b, 8, Z)

		if rotation_ID then
			buffer.writeu8(b, 12, rotation_ID)
		else
			buffer.writeu8(b, 12, 0x0)

			-- ? TODO cleaner but slower ?
			-- buffer.copy(b, 13, write_vector3(raw.XVector)) -- R00, R10, R20
			-- buffer.copy(b, 13 + 12, write_vector3(raw.YVector)) -- R01, R11, R21
			-- buffer.copy(b, 13 + 24, write_vector3(raw.ZVector)) -- R02, R12, R22

			buffer.writef32(b, 13, R00)
			buffer.writef32(b, 17, R01)
			buffer.writef32(b, 21, R02)

			buffer.writef32(b, 25, R10)
			buffer.writef32(b, 29, R11)
			buffer.writef32(b, 33, R12)

			buffer.writef32(b, 37, R20)
			buffer.writef32(b, 41, R21)
			buffer.writef32(b, 45, R22)
		end

		return b, len
	end,
	["EnumItem"] = function(raw)
		local b_Name, Name_size = Binary_Descriptors.string(tostring(raw.EnumType))

		local len = Name_size + 4
		local b = buffer.create(len)

		buffer.copy(b, 0, b_Name)
		buffer.writeu32(b, Name_size, raw.Value)

		return b, len
	end,
	["NumberSequence"] = nil,
	-- ["NumberSequenceKeypoint"] = nil, -- TODO Only impl. if necessary because NumberSequence will reference this therefore slowing down itself
	["ColorSequence"] = function(raw)
		return Binary_Descriptors.__SEQUENCE(raw, function(color3, b, offset)
			buffer.copy(b, offset, Binary_Descriptors.Color3(color3))
			return 12
		end, 20, 0)
	end,
	-- ["ColorSequenceKeypoint"] = nil, -- TODO Only impl. if necessary because ColorSequence will reference this therefore slowing down itself
	["NumberRange"] = function(raw)
		local b = buffer.create(8)

		buffer.writef32(b, 0, raw.Min)
		buffer.writef32(b, 4, raw.Max)

		return b, 8
	end,
	["Rect"] = function(raw)
		local b = buffer.create(16)

		local Vector2__descriptor = Binary_Descriptors.Vector2
		local Min = Vector2__descriptor(raw.Min)
		buffer.copy(b, 0, Min)
		local Max = Vector2__descriptor(raw.Max)
		buffer.copy(b, 8, Max)

		return b, 16
	end,
	["PhysicalProperties"] = function(raw) -- ? Not sure yet (https://github.com/RobloxAPI/spec/blob/master/properties/drafts/AttributesSerializeFull.md#physicalproperties)
		local len = 1
		if raw then
			len += 20
		end
		local b = buffer.create(len)

		buffer.writeu8(b, 0, raw and 1 or 0)

		if raw then
			buffer.writef32(b, 1, raw.Density)
			buffer.writef32(b, 5, raw.Friction)
			buffer.writef32(b, 9, raw.Elasticity)
			buffer.writef32(b, 13, raw.FrictionWeight)
			buffer.writef32(b, 17, raw.ElasticityWeight)
		end

		return b, len
	end,
	["Region3"] = function(raw)
		local b = buffer.create(24)

		local Vector3__descriptor = Binary_Descriptors.Vector3
		local Min = Vector3__descriptor(raw.Min)
		buffer.copy(b, 0, Min)
		local Max = Vector3__descriptor(raw.Max)
		buffer.copy(b, 12, Max)

		return b, 24
	end,
	["Region3int16"] = function(raw)
		local b = buffer.create(12)

		local Vector3int16__descriptor = Binary_Descriptors.Vector3int16
		local Min = Vector3int16__descriptor(raw.Min)
		buffer.copy(b, 0, Min)
		local Max = Vector3int16__descriptor(raw.Max)
		buffer.copy(b, 6, Max)

		return b, 12
	end,
	["Font"] = 636 < CLIENT_VERSION and function(raw)
		local string__descriptor = Binary_Descriptors.string

		local b_Family, Family_size = string__descriptor(raw.Family)
		local b_CachedFaceId, CachedFaceId_size = string__descriptor("")

		local len = 3 + Family_size + CachedFaceId_size
		local b = buffer.create(len)

		local ok_w, weight = pcall(index, raw, "Weight")
		local ok_s, style = pcall(index, raw, "Style")

		buffer.writeu16(b, 0, ok_w and weight.Value or 0)
		buffer.writeu8(b, 2, ok_s and style.Value or 0)

		buffer.copy(b, 3, b_Family)
		buffer.copy(b, 3 + Family_size, b_CachedFaceId)

		return b, len
	end or function(raw)
		local string__descriptor = Binary_Descriptors.string

		local b_Family, Family_size = string__descriptor(raw.Family)
		local b_CachedFaceId, CachedFaceId_size = string__descriptor("")

		local len = 3 + Family_size + CachedFaceId_size
		local b = buffer.create(len)

		local FontString = tostring(raw)

		local EmptyWeight = string_find(FontString, "Weight = ,")
		local EmptyStyle = string_find(FontString, "Style =  }")

		buffer.writeu16(b, 0, EmptyWeight and 0 or raw.Weight.Value)
		buffer.writeu8(b, 2, EmptyStyle and 0 or raw.Style.Value)

		buffer.copy(b, 3, b_Family)
		buffer.copy(b, 3 + Family_size, b_CachedFaceId)

		return b, len
	end,
}
do
	Binary_Descriptors.NumberSequence = Binary_Descriptors.__SEQUENCE
end

-- ! Bytes 128-255 must NOT be escaped: they are pieces of UTF-8 characters, and `&#195;&#169;` would load as "Ã©" instead of "é" (every accent/emoji/non-English text got corrupted whenever a string or script contained "]]>")
local ESCAPES_PATTERN = "[&<>\"'\0\1-\9\11-\12\14-\31\127]" -- * The safe way is to escape all five characters in text. However, the three characters " ' and > needn't be escaped in text
-- %z (\0 aka NULL) might not be needed as Roblox automatically converts it to space everywhere it seems like
-- Characters from: https://create.roblox.com/docs/en-us/ui/rich-text#escape-forms
-- * EscapesPattern should be ordered from most common to least common characters for sake of speed
-- * Might wanna use their numerical codes instead of named codes for reduced file size (Could be an Option)
-- TODO Maybe we should invert the pattern to only allow certain characters (future-proof)
local ESCAPES = {
	["&"] = "&amp;", -- 38
	["<"] = "&lt;", -- 60
	[">"] = "&gt;", -- 62
	['"'] = "&#34;", --  quot
	["'"] = "&#39;", -- apos
	["\0"] = "",
}

for rangeStart, rangeEnd in string.gmatch(ESCAPES_PATTERN, "(.)%-(.)") do
	for charCode = string.byte(rangeStart), string.byte(rangeEnd) do
		ESCAPES[string.char(charCode)] = "&#" .. charCode .. ";"
	end
end

local XML_Descriptors
XML_Descriptors = {
	__CDATA = function(raw) -- ? Normally Roblox doesn't use CDATA unless the string has newline characters (\n); We rather CDATA everything for sake of speed
		return "<![CDATA[" .. raw .. "]]>"
	end,
	__ENUM = function(raw)
		return raw.Value, "token"
	end,
	__NORMALIZE_NUMBER = function(raw)
		if raw ~= raw then
			return "NAN"
		elseif raw == math.huge then
			return "INF"
		elseif raw == -math.huge then
			return "-INF"
		end

		return raw
	end,
	__NORMALIZE_RANGE = function(raw)
		return raw ~= raw and "0" or raw -- Normally we should return "-nan(ind)" instead of "0" but this adds more compatibility
	end,
	__MINMAX = function(min, max, descriptor)
		return "<min>" .. descriptor(min) .. "</min><max>" .. descriptor(max) .. "</max>"
	end,
	__PROTECTEDSTRING = function(raw) -- ? its purpose is to "protect" data from being treated as ordinary character data during processing;
		return string_find(raw, "]]>") and string.gsub(raw, ESCAPES_PATTERN, ESCAPES) or XML_Descriptors.__CDATA(raw)
	end,
	__SEQUENCE = function(raw, valueFormatter)
		-- The value is the text content, formatted as a space-separated list of floating point numbers.
		-- tostring(raw) also works (but way slower rn)
		local __NORMALIZE_RANGE = XML_Descriptors.__NORMALIZE_RANGE

		local sequence = ""

		for _, keypoint in raw.Keypoints do
			local Value = keypoint.Value

			sequence ..= keypoint.Time .. " " .. (valueFormatter and valueFormatter(Value) or __NORMALIZE_RANGE(Value) .. " " .. __NORMALIZE_RANGE(
				keypoint.Envelope
			) .. " ") -- ? Trailing whitespace is only needed for lune compatibility
		end

		return sequence
	end,
	__VECTOR = function(X, Y, Z) -- Each element is a <float>
		local Value = "<X>" .. X .. "</X><Y>" .. Y .. "</Y>" -- There is no Vector without at least two Coordinates.. (Vector1, at least on Roblox)

		if Z then
			Value ..= "<Z>" .. Z .. "</Z>"
		end

		return Value
	end,
	--------------------------------------------------------------
	--------------------------------------------------------------
	--------------------------------------------------------------
	Axes = function(raw)
		-- The text of this element is formatted as an integer between 0 and 7

		return "<axes>" .. __BIT(raw.X, raw.Y, raw.Z) .. "</axes>"
	end,

	-- ? Roblox uses CDATA only for these (try to prove this wrong): CollisionGroupData, SmoothGrid, MaterialColors, PhysicsGrid
	-- ! Assuming all base64 encoded strings won't have newlines

	BinaryString = function(raw)
		return raw == "" and "" or base64encode(raw)
	end,

	BrickColor = function(raw)
		return raw.Number -- * Roblox encodes the tags as "int", but this is not required for Roblox to properly decode the type. For better compatibility, it is preferred that third-party implementations encode and decode "BrickColor" tags instead. Could also use "int" or "Color3uint8"
	end,
	CFrame = function(raw)
		local X, Y, Z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = raw:GetComponents()
		return XML_Descriptors.__VECTOR(X, Y, Z)
			.. "<R00>"
			.. R00
			.. "</R00><R01>"
			.. R01
			.. "</R01><R02>"
			.. R02
			.. "</R02><R10>"
			.. R10
			.. "</R10><R11>"
			.. R11
			.. "</R11><R12>"
			.. R12
			.. "</R12><R20>"
			.. R20
			.. "</R20><R21>"
			.. R21
			.. "</R21><R22>"
			.. R22
			.. "</R22>",
			"CoordinateFrame"
	end,
	Color3 = function(raw) -- Each element is a <float>
		return "<R>" .. raw.R .. "</R><G>" .. raw.G .. "</G><B>" .. raw.B .. "</B>" -- ? It is recommended that Color3 is encoded with elements instead of text.
	end,
	Color3uint8 = function(raw)
		-- https://github.com/rojo-rbx/rbx-dom/blob/master/docs/xml.md#color3uint8
		-- ? It is recommended that Color3uint8 is encoded with text instead of elements.

		return 0xFF000000
			+ (math.floor(raw.R * 255) * 0x10000)
			+ (math.floor(raw.G * 255) * 0x100)
			+ math.floor(raw.B * 255)
		-- return bit32.bor(
		-- 	bit32.bor(bit32.bor(bit32.lshift(0xFF, 24), bit32.lshift(0xFF * raw.R, 16)), bit32.lshift(0xFF * raw.G, 8)),
		-- 	0xFF * raw.B
		-- )

		-- return tonumber(string.format("0xFF%02X%02X%02X",raw.R*255,raw.G*255,raw.B*255))
	end,
	ColorSequence = function(raw)
		-- The value is the text content, formatted as a space-separated list of FLOATing point numbers.

		return XML_Descriptors.__SEQUENCE(raw, function(color3)
			local __NORMALIZE_RANGE = XML_Descriptors.__NORMALIZE_RANGE

			return __NORMALIZE_RANGE(color3.R)
				.. " "
				.. __NORMALIZE_RANGE(color3.G)
				.. " "
				.. __NORMALIZE_RANGE(color3.B)
				.. " 0 "
		end)
	end,
	Content = function(raw)
		local SourceType = raw.SourceType
		return SourceType == Enum.ContentSourceType.None and "<null></null>"
			or SourceType == Enum.ContentSourceType.Uri and "<uri>" .. XML_Descriptors.string(raw.Uri) .. "</uri>"
			or SourceType == Enum.ContentSourceType.Object and "<Ref>" .. GetRef(raw.Object)
			.. "</Ref>" -- TODO Not sure, run tests
	end,
	ContentId = function(raw)
		return raw == "" and "<null></null>" or "<url>" .. XML_Descriptors.string(raw) .. "</url>", "Content" -- TODO Remove "Content" str once Roblox fully releases Content DataType
	end,
	CoordinateFrame = function(raw)
		return "<CFrame>" .. XML_Descriptors.CFrame(raw) .. "</CFrame>"
	end,
	-- DateTime = function(raw) return raw.UnixTimestampMillis end, -- ? Not sure
	Faces = function(raw)
		-- The text of this element is formatted as an integer between 0 and 63
		return "<faces>" .. __BIT(raw.Right, raw.Top, raw.Back, raw.Left, raw.Bottom, raw.Front) .. "</faces>"
	end,
	Font = 636 < CLIENT_VERSION
			and function(raw)
				-- TODO (OPTIONAL ELEMENT): Figure out how to determine (ContentId) <CachedFaceId><url>rbxasset://fonts/GothamSSm-Medium.otf</url></CachedFaceId>
				--[[
		? game:GetService("TextService"):GetFontMemoryData()
		? rbxasset://fonts/families/{Enum.Font.BuilderSans.Name}.json
		]]

				local ok_w, weight = pcall(index, raw, "Weight")
				local ok_s, style = pcall(index, raw, "Style")

				return "<Family>"
					.. XML_Descriptors.ContentId(raw.Family)
					.. "</Family><Weight>"
					.. (ok_w and XML_Descriptors.__ENUM(weight) or "")
					.. "</Weight><Style>"
					.. (ok_s and style.Name or "") -- Weird but this field accepts .Name of enum instead..
					.. "</Style>"
			end
		or function(raw)
			local FontString = tostring(raw) -- TODO: Temporary fix

			local EmptyWeight = string_find(FontString, "Weight = ,")
			local EmptyStyle = string_find(FontString, "Style =  }")

			return "<Family>"
				.. XML_Descriptors.ContentId(raw.Family)
				.. "</Family><Weight>"
				.. (EmptyWeight and "" or XML_Descriptors.__ENUM(raw.Weight))
				.. "</Weight><Style>"
				.. (EmptyStyle and "" or raw.Style.Name) -- Weird but this field accepts .Name of enum instead..
				.. "</Style>"
		end,
	NumberRange = function(raw) -- tostring(raw) also works
		-- The value is the text content, formatted as a space-separated list of floating point numbers.
		local __NORMALIZE_RANGE = XML_Descriptors.__NORMALIZE_RANGE

		return __NORMALIZE_RANGE(raw.Min) .. " " .. __NORMALIZE_RANGE(raw.Max) --[[.. " "]] -- ! This might be required for compatibility; __NORMALIZE_RANGE is not needed here but it fixes the issue where "nan 10" value would reset to "0 0"
	end,
	NumberSequence = nil,
	-- NumberSequence = Descriptors.__SEQUENCE,

	-- Path2DControlPoint = function(raw)  -- ? Not sure
	-- 	local udim2 = XML_Descriptors.UDim2
	-- 	return "<Position>"
	-- 		.. udim2(raw.Position)
	-- 		.. "</Position>"
	-- 		.. "<LeftTangent>"
	-- 		.. udim2(raw.LeftTangent)
	-- 		.. "</LeftTangent>"
	-- 		.. "<RightTangent>"
	-- 		.. udim2(raw.RightTangent)
	-- 		.. "</RightTangent>"
	-- end,

	PhysicalProperties = function(raw)
		--[[
			Contains at least one CustomPhysics element, which is interpreted according to the bool type. If this value is true, then the tag also contains an element for each component of the PhysicalProperties:

			Density
			Friction
			Elasticity
			FrictionWeight
			ElasticityWeight

			The value of each component is represented by the text content formatted as a 32-bit floating point number (see float)
		]]

		local CustomPhysics = "<CustomPhysics>" .. XML_Descriptors.bool(raw and true or false) .. "</CustomPhysics>"

		return raw
				and CustomPhysics .. "<Density>" .. raw.Density .. "</Density><Friction>" .. raw.Friction .. "</Friction><Elasticity>" .. raw.Elasticity .. "</Elasticity><FrictionWeight>" .. raw.FrictionWeight .. "</FrictionWeight><ElasticityWeight>" .. raw.ElasticityWeight .. "</ElasticityWeight>"
			or CustomPhysics
	end,
	-- ProtectedString = function(raw) return tostring(raw), "ProtectedString" end,
	Ray = function(raw)
		local vector3 = XML_Descriptors.Vector3

		return "<origin>" .. vector3(raw.Origin) .. "</origin><direction>" .. vector3(raw.Direction) .. "</direction>"
	end,
	Rect = function(raw)
		return XML_Descriptors.__MINMAX(raw.Min, raw.Max, XML_Descriptors.Vector2), "Rect2D"
	end,
	Region3 = function(raw) -- ? Not sure yet (/Network/Replicator.cpp#L1306)
		local Translation = raw.CFrame.Position
		local HalfSize = raw.Size * 0.5

		return XML_Descriptors.__MINMAX(
			Translation - HalfSize, -- /App/util/Region3.cpp#L38
			Translation + HalfSize, -- /App/util/Region3.cpp#L42
			XML_Descriptors.Vector3
		)
	end,
	Region3int16 = function(raw) -- ? Not sure yet (/App/v8tree/EnumProperty.cpp#L346)
		return XML_Descriptors.__MINMAX(raw.Min, raw.Max, XML_Descriptors.Vector3int16)
	end,
	SharedString = function(raw)
		raw = raw == "" and "" or base64encode(raw)

		local Identifier = SharedString_identifiers[raw]

		if SharedStrings[Identifier] == nil then
			SharedStrings[Identifier] = raw
		end

		return Identifier
	end,
	SecurityCapabilities = nil,
	-- SystemAddress = function(raw) return raw end, -- PeerId?  -- ? Not sure
	-- TweenInfo = function(raw) -- ? Not sure
	-- 	local __NORMALIZE_NUMBER = XML_Descriptors.__NORMALIZE_NUMBER
	-- 	local enum = XML_Descriptors.__ENUM

	-- 	return "<Time>"
	-- 		.. __NORMALIZE_NUMBER(raw.Time)
	-- 		.. "</Time><DelayTime>"
	-- 		.. __NORMALIZE_NUMBER(raw.DelayTime)
	-- 		.. "</DelayTime><RepeatCount>"
	-- 		.. __NORMALIZE_NUMBER(raw.RepeatCount)
	-- 		.. "</RepeatCount><Reverses>"
	-- 		.. XML_Descriptors.bool(raw.Reverses)
	-- 		.. "</Reverses><EasingDirection>"
	-- 		.. enum(raw.EasingDirection)
	-- 		.. "</EasingDirection><EasingStyle>"
	-- 		.. enum(raw.EasingStyle)
	-- 		.. "</EasingStyle>"
	-- end,
	UDim = function(raw)
		--[[
			S: Represents the Scale component. Interpreted as a <float>.
			O: Represents the Offset component. Interpreted as an <int>.
		]]

		return "<S>" .. raw.Scale .. "</S><O>" .. raw.Offset .. "</O>"
	end,
	UDim2 = function(raw)
		--[[
			XS: Represents the X.Scale component. Interpreted as a <float>.
			XO: Represents the X.Offset component. Interpreted as an <int>.
			YS: Represents the Y.Scale component. Interpreted as a <float>.
			YO: Represents the Y.Offset component. Interpreted as an <int>.
		]]

		local X, Y = raw.X, raw.Y

		return "<XS>"
			.. X.Scale
			.. "</XS><XO>"
			.. X.Offset
			.. "</XO><YS>"
			.. Y.Scale
			.. "</YS><YO>"
			.. Y.Offset
			.. "</YO>"
	end,

	-- UniqueId = function(raw) -- ? Not sure  -- ? No idea if this even needs a Descriptor
	-- 	--[[
	-- 		UniqueId properties might be random everytime Studio saves a place file
	-- 		and don't have a use right now outside of packages, which SSI doesn't
	-- 		account for anyway. They generate diff noise, so we shouldn't serialize
	-- 		them until we have to.
	-- 	]]
	-- 	-- https://github.com/MaximumADHD/Roblox-Client-Tracker/blob/roblox/LuaPackages/Packages/_Index/ApolloClientTesting/ApolloClientTesting/utilities/common/makeUniqueId.lua#L62
	-- 	return ""
	-- end,

	Vector2 = function(raw)
		--[[
			X: Represents the X component. Interpreted as a <float>.
			Y: Represents the Y component. Interpreted as a <float>.
		]]
		return XML_Descriptors.__VECTOR(raw.X, raw.Y)
	end,
	Vector2int16 = nil,
	-- Vector2int16 = Descriptors.Vector2, -- except as <int>
	Vector3 = function(raw)
		--[[
			X: Represents the X component. Interpreted as a <float>.
			Y: Represents the Y component. Interpreted as a <float>.
			Z: Represents the Z component. Interpreted as a <float>.
		]]
		return XML_Descriptors.__VECTOR(raw.X, raw.Y, raw.Z)
	end,
	Vector3int16 = nil,
	-- Vector3int16 = Descriptors.Vector3, -- except as <int>\
	bool = function(raw)
		return raw and "true" or "false"
	end,
	double = nil, -- Float64
	float = nil, -- Float32
	int = nil, -- Int32
	int64 = nil, -- Int64 (long)
	string = function(raw)
		return (raw == nil or raw == "") and ""
			or string_find(raw, "]]>") and string.gsub(raw, ESCAPES_PATTERN, ESCAPES)
			or XML_Descriptors.__CDATA(string.gsub(raw, "\0", ""))
	end,

	--------------------------------------------------------------
	-----------%localappdata%/Roblox/GlobalSettings_13.xml--------
	--------------------------------------------------------------
	-- QDir = function(raw) -- ? Not sure
	-- 	return raw
	-- end,
	-- QFont = function(raw) -- ? Not sure
	-- 	return raw
	-- end,
}

do
	local BASE_CAPABILITIES
	pcall(function()
		BASE_CAPABILITIES = SecurityCapabilities.new()
	end)
	if BASE_CAPABILITIES then
		local CAPABILITY_BITS = {
			Plugin = 2 ^ 0, ----------------  0
			LocalUser = 2 ^ 1, -------------  1
			WritePlayer = 2 ^ 2, -----------  2
			RobloxScript = 2 ^ 3, ----------  3
			RobloxEngine = 2 ^ 4, ----------  4
			NotAccessible = 2 ^ 5, ---------  5
			RunClientScript = 2 ^ 8, -------  8
			RunServerScript = 2 ^ 9, -------  9
			AccessOutsideWrite = 2 ^ 11, ---  11 (0xb)
			Unassigned = 2 ^ 15, -----------  15 (0xf)
			AssetRequire = 2 ^ 16, ---------  16 (0x10)
			LoadString = 2 ^ 17, -----------  17 (0x11)
			ScriptGlobals = 2 ^ 18, --------  18 (0x12)
			CreateInstances = 2 ^ 19, ------  19 (0x13)
			Basic = 2 ^ 20, ----------------  20 (0x14)
			Audio = 2 ^ 21, ----------------  21 (0x15)
			DataStore = 2 ^ 22, ------------  22 (0x16)
			Network = 2 ^ 23, --------------  23 (0x17)
			Physics = 2 ^ 24, --------------  24 (0x18)
			UI = 2 ^ 25, -------------------  25 (0x19)
			CSG = 2 ^ 26, ------------------  26 (0x1a)
			Chat = 2 ^ 27, -----------------  27 (0x1b)
			Animation = 2 ^ 28, ------------  28 (0x1c)
			Avatar = 2 ^ 29, ---------------  29 (0x1d)
			Input = 2 ^ 30, ----------------  30 (0x1e)
			Environment = 2 ^ 31, ----------  31 (0x1f)
			RemoteEvent = 2 ^ 32, ----------  32 (0x20)
			LegacySound = 2 ^ 33, ----------  33 (0x21)
			Players = 2 ^ 34, --------------  34 (0x22)
			CapabilityControl = 2 ^ 35, ----  35 (0x23)
			InternalTest = 2 ^ 60, ---------  60 (0x3c), Related to TestingGameScript
			PluginOrOpenCloud = 2 ^ 61, ----  61 (0x3d)
			Assistant = 2 ^ 62, ------------  62 (0x3e)
			-- Restricted = 2 ^ 63, -----------  for negative (highest bit for signed integers)
		}

		XML_Descriptors.SecurityCapabilities = function(raw)
			-- TODO tostring & string.split aren't ideal but this is the only way until the feature is out of the experimental phase

			if raw == BASE_CAPABILITIES then
				return 0
			end

			local result = 0

			for _, flag in string.split(tostring(raw), " | ") do
				local bit = CAPABILITY_BITS[flag]
				if bit then
					result += bit
				end
			end

			return result
		end
	end
end

for descriptorName, redirectName in
	{
		NumberSequence = "__SEQUENCE",
		Vector2int16 = "Vector2",
		Vector3int16 = "Vector3",
		double = "__NORMALIZE_NUMBER",
		float = "__NORMALIZE_NUMBER",
		int = "__NORMALIZE_NUMBER",
		int64 = "__NORMALIZE_NUMBER",
	}
do
	XML_Descriptors[descriptorName] = XML_Descriptors[redirectName]
end
if CLIENT_VERSION < math.huge then -- math.huge because unknown yet
	-- ! For sake of compatibility with older clients, Roblox currently does this too but it WILL probably change in the future so keep track of that. ONCE ROBLOX MOVES AWAY FROM THIS, MAKE SURE TO KEEP SUPPORT FOR VERY OLD CLIENTS; 645 <= CLIENT Ver < ??? (ver when roblox moves away), THIS IS COMPLICATED SO PROBABLY NO SUPPORT, JUST USE OLDER VER OF USSI; NEWEST CLIENTS
	XML_Descriptors.Content = XML_Descriptors.ContentId
end

local ClassList

do
	local ClassPropertyExceptions = {
		Whitelist = { TriangleMeshPart = ArrayToDict({ "CollisionFidelity" }) },
		Blacklist = {
			LuaSourceContainer = ArrayToDict({ "ScriptGuid" }),
			Instance = ArrayToDict({ "UniqueId", "HistoryId" }),
		},
	}

	local NotScriptableFixes = { --[[
		For more info: 
		- https://github.com/luau/UniversalSynSaveInstance/blob/main/Tools/NotScriptable-Related/Potentially%20Missing%20Properties%20Dumper/Potentially%20Missing%20Properties%20Dumper.luau
		- https://github.com/luau/UniversalSynSaveInstance/blob/main/Tools/NotScriptable-Related/NotScriptable%20Dumper/NotScriptable%20Dumper.py
		]]
		Instance = {
			AttributesSerialize = function(instance)
				-- * There are certain restrictions for names of attributes
				-- https://create.roblox.com/docs/reference/engine/classes/Instance#SetAttribute
				-- But it seems like even if those are present, Studio still opens the file just fine
				-- So there is no need to check for them currently

				-- TODO: merge sequence Descriptors and some other descriptors where possible (check xml descriptors)
				-- ? Return early for empty tags (this proved equally as fast when done using counter/next)

				local attrs = instance:GetAttributes()

				if not next(attrs) then
					return ""
				end

				local attrs_n = 0
				local buffer_size = 4
				local attrs_sorted = {}
				local attrs_formatted = table.clone(attrs)
				for attr, val in attrs do
					attrs_n += 1
					attrs_sorted[attrs_n] = attr

					local Type = typeof(val)

					local Descriptor = Binary_Descriptors[Type]
					local attr_size

					attrs_formatted[attr], attr_size = Descriptor(val)

					buffer_size += 5 + #attr + attr_size
				end

				table.sort(attrs_sorted)

				local b = buffer.create(buffer_size)

				local offset = 0

				buffer.writeu32(b, offset, attrs_n)
				offset += 4

				local string__descriptor = Binary_Descriptors.string
				for _, attr in attrs_sorted do
					local b_Name, Name_size = string__descriptor(attr)

					buffer.copy(b, offset, b_Name)
					offset += Name_size

					buffer.writeu8(b, offset, attr_Type_IDs[typeof(attrs[attr])])
					offset += 1

					local bb = attrs_formatted[attr]

					buffer.copy(b, offset, bb)
					offset += buffer.len(bb)
				end

				return buffer.tostring(b)
			end,
			DefinesCapabilities = "Sandboxed",
			Tags = function(instance)
				-- https://github.com/RobloxAPI/spec/blob/master/properties/Tags.md

				local tags = instance:GetTags()

				if #tags == 0 then
					return ""
				end

				return table.concat(tags, "\0")
			end,
		},

		-- DebuggerBreakpoint = {line="Line"}, -- ? This shouldn't appear in live games (try to prove this wrong)
		BallSocketConstraint = { MaxFrictionTorqueXml = "MaxFrictionTorque" },
		BasePart = {
			Color3uint8 = "Color",
			MaterialVariantSerialized = "MaterialVariant",
			size = "Size",
		},
		DoubleConstrainedValue = { value = "Value" },
		IntConstrainedValue = { value = "Value" },

		-- CustomEvent = {PersistedCurrentValue=function(instance) -- * Class is Deprecated and :SetValue doesn't seem to affect GetCurrentValue anymore
		-- 	local Receiver  = instance:GetAttachedReceivers()[1]
		-- 	if Receiver then
		-- 		return Receiver:GetCurrentValue()
		-- 	else
		-- 		error("No Receiver", 2)
		-- 	end
		-- end},
		Terrain = {
			AcquisitionMethod = "LastUsedModificationMethod", -- ? Not sure
			MaterialColors = function(instance) -- https://github.com/RobloxAPI/spec/blob/master/properties/MaterialColors.md
				local TERRAIN_MATERIAL_COLORS =
					{ --https://github.com/rojo-rbx/rbx-dom/blob/master/rbx_dom_lua/src/customProperties.lua#L5
						Enum.Material.Grass,
						Enum.Material.Slate,
						Enum.Material.Concrete,
						Enum.Material.Brick,
						Enum.Material.Sand,
						Enum.Material.WoodPlanks,
						Enum.Material.Rock,
						Enum.Material.Glacier,
						Enum.Material.Snow,
						Enum.Material.Sandstone,
						Enum.Material.Mud,
						Enum.Material.Basalt,
						Enum.Material.Ground,
						Enum.Material.CrackedLava,
						Enum.Material.Asphalt,
						Enum.Material.Cobblestone,
						Enum.Material.Ice,
						Enum.Material.LeafyGrass,
						Enum.Material.Salt,
						Enum.Material.Limestone,
						Enum.Material.Pavement,
					}

				local b = buffer.create(69) -- 69 bytes: 6 reserved + 63 for colors (21 materials * 3 components)
				local offset = 6 -- 6 reserved bytes

				local RGB_components = { "R", "G", "B" }

				for _, material in TERRAIN_MATERIAL_COLORS do
					local color = instance:GetMaterialColor(material)
					for _, component in RGB_components do
						buffer.writeu8(b, offset, math.floor(color[component] * 255)) -- ? math.floor seems unneeded but it makes it faster
						offset += 1
					end
				end

				return buffer.tostring(b)
			end,
		},
		TriangleMeshPart = {
			FluidFidelityInternal = "FluidFidelity",
		},
		MeshPart = { InitialSize = "MeshSize" },
		PartOperation = { InitialSize = "MeshSize" },
		Part = { shape = "Shape" },
		TrussPart = { style = "Style" },
		FormFactorPart = {
			formFactorRaw = "FormFactor",
		},
		Fire = { heat_xml = "Heat", size_xml = "Size" },
		Humanoid = { Health_XML = "Health" },
		HumanoidDescription = {
			EmotesDataInternal = function(instance)
				local emotes_data = ""
				for name, ids in instance:GetEmotes() do
					emotes_data ..= name .. "^" .. table.concat(ids, "^") .. "^\\"
				end
				return emotes_data
			end,
			EquippedEmotesDataInternal = function(instance)
				local equipped_emotes_data = ""
				for _, emote in instance:GetEquippedEmotes() do
					equipped_emotes_data ..= emote.Slot .. "^" .. emote.Name .. "\\"
				end
				return equipped_emotes_data
			end,
		},
		LocalizationTable = {
			Contents = function(instance)
				return instance:GetContents() --service.HttpService:JSONEncode(instance:GetEntries())
			end,
		},
		MaterialService = { Use2022MaterialsXml = "Use2022Materials" },

		Model = {
			ScaleFactor = function(instance)
				return instance:GetScale()
			end,
			WorldPivotData = "WorldPivot", -- TODO This doesn't accurately represent whether optional type property is present or not (it's never nil), gethiddenproperty or gethiddenproperty_fallback is preferred
		},
		PackageLink = { PackageIdSerialize = "PackageId", VersionIdSerialize = "VersionNumber" },
		Players = { MaxPlayersInternal = "MaxPlayers", PreferredPlayersInternal = "PreferredPlayers" }, -- ? Only needed for execs that lack LocalUserSecurity (Level 2, 5, 9), even so, it's a pretty useless information as it can be viewed elsewhere

		StarterPlayer = { AvatarJointUpgrade_Serialized = "AvatarJointUpgrade" },
		Smoke = { size_xml = "Size", opacity_xml = "Opacity", riseVelocity_xml = "RiseVelocity" },
		Sound = {
			xmlRead_MaxDistance_3 = "RollOffMaxDistance", -- * Also MaxDistance
		},
		-- ViewportFrame = { -- * Pointless because these reflect CurrentCamera's properties
		-- 	CameraCFrame = function(instance) -- *
		-- 		local CurrentCamera = instance.CurrentCamera
		-- 		if CurrentCamera then
		-- 			return CurrentCamera.CFrame
		-- 		else
		-- 			error("No CurrentCamera", 2)
		-- 		end
		-- 	end,
		-- 	-- CameraFieldOfView =
		-- },
		WeldConstraint = {
			Part0Internal = "Part0",
			Part1Internal = "Part1",
			-- State = function(instance)
			-- 	-- If untouched then default state is 3 (default true)
			-- 	return instance.Enabled and 1 or 0
			-- end,
		},
		Workspace = {
			-- SignalBehavior2 = "SignalBehavior", -- * Both are NotScriptable so it doesn't make sense to keep
			CollisionGroupData = function()
				local collision_groups = game:GetService("PhysicsService"):GetRegisteredCollisionGroups()

				local col_groups_n = #collision_groups

				if col_groups_n == 0 then
					return "\1\0"
				end

				local buffer_size = 2 -- Initial size

				for _, group in collision_groups do
					buffer_size += 7 + #group.name
				end

				local b = buffer.create(buffer_size)

				local offset = 0

				buffer.writeu8(b, offset, 1) -- ? [CONSTANT] Version byte (likely)
				offset += 1
				buffer.writeu8(b, offset, col_groups_n) -- Group count
				offset += 1

				for i, group in collision_groups do
					local name, id, mask = group.name, i - 1, group.mask
					local name_len = #name

					buffer.writeu8(b, offset, id) -- ID
					offset += 1

					buffer.writeu8(b, offset, 4) -- ? [CONSTANT] Not sure what this is (also not sure about u8, could be i8)
					offset += 1

					buffer.writei32(b, offset, mask) -- Mask value as signed 32-bit integer
					offset += 4

					buffer.writeu8(b, offset, name_len) -- Name length
					offset += 1
					buffer.writestring(b, offset, name) -- Name
					offset += name_len
				end

				return buffer.tostring(b)
			end,
		},
	}

	local function FetchAPI()
		-- Credits @MaximumADHD

		local API_Dump

		local ok, err = pcall(function()
			if EXECUTOR_NAME == "Zenith" then -- TODO Temp fix as it crashes on HttpGet for sites that return 403 code
 				return
 			end
			local CLIENT_VERSION_str = tostring(CLIENT_VERSION)
			local ok, result = pcall(readfile, CLIENT_VERSION_str)
			if
				ok
				and result
				and result ~= ""
				and pcall(service.HttpService.JSONDecode, service.HttpService, result)
			then
				API_Dump = result
				return
			end

			local matching_versions, is_matched = {}

			-- * https://setup.rbxcdn.com/versionQTStudio seems to be a bit behind DeployHistory.txt
			local DeployHistory = string.split(game:HttpGet("https://setup.rbxcdn.com/DeployHistory.txt", true), "\n")
			for i = #DeployHistory, 1, -1 do
				local line = DeployHistory[i]

				local file_version = string.match(line, "file version: ([%d, ]+)")
				if file_version then
					if string.split(file_version, ", ")[2] == CLIENT_VERSION_str then
						is_matched = true

						local version_hash = string.match(line, "(version%-[^%s]+)")
						if version_hash and version_hash ~= "version-hidden" then -- * Roblox hides the hash on recent deploys, there is no API dump to fetch for those
							matching_versions[version_hash] = true
						end
					elseif is_matched then
						break
					end
				end
			end

			for version_hash in matching_versions do
				ok, result = pcall(
					game.HttpGet,
					game,
					"https://setup.rbxcdn.com/" .. version_hash .. "-Full-API-Dump.json",
					true
				)
				if ok then
					local o, r = pcall(service.HttpService.JSONDecode, service.HttpService, result)
					if o then
						API_Dump = service.HttpService:JSONEncode(r.Classes) -- minify it
						break
					end
				end
			end

			if API_Dump then -- * Without a dump there is nothing to cache, and writefile(path, nil) would throw
				writefile(CLIENT_VERSION_str, API_Dump)
			end
		end)

		if not ok or not API_Dump then
			warn("[DEBUG] Failed to get " .. version() .. " API Dump, trying latest..")
			warn("[DEBUG]", err)
			API_Dump = service.HttpService:JSONEncode(
				service.HttpService:JSONDecode(
					game:HttpGet(
						"https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/Mini-API-Dump.json",
						true
					)
				).Classes
			)
		end

		local classList = {}

		local ClassesWhitelist, ClassesBlacklist = ClassPropertyExceptions.Whitelist, ClassPropertyExceptions.Blacklist

		for _, API_Class in service.HttpService:JSONDecode(API_Dump) do
			local ClassProperties, NotSaveableClassProperties, ClassProperties_size, NotSaveableClassProperties_size  = {}, {}, 1, 1
			local Class = {
				Properties = ClassProperties,
				NotSaveableProperties = NotSaveableClassProperties, -- Contains properties that are canload or cansave false in the api dump
				Superclass = API_Class.Superclass,
			}

			local ClassTags = API_Class.Tags
			local ClassName = API_Class.Name

			if ClassTags then
				Class.Tags = ArrayToDict(ClassTags, nil, nil, "string") -- or {}
			end

			local NotScriptableFixClass = NotScriptableFixes[ClassName]

			-- ? Check 96ea8b2a755e55a78aedb55a7de7e83980e11077 commit - If a NotScriptableFix is needed that relies on another NotScriptable Property (which doesn't really make sense in the first place)

			local ClassWhitelist, ClassBlacklist = ClassesWhitelist[ClassName], ClassesBlacklist[ClassName]

			for _, Member in API_Class.Members do
				-- ? print(game:GetService("ReflectionService"):GetPropertyNames("TextBox"))
				if Member.MemberType == "Property" then
					local Serialization = Member.Serialization

					--[[
						-- ! CanSave replaces "Tags.Deprecated" check because there are some old properties which are deprecated yet have CanSave.
						Example: Humanoid.Health is CanSave false due to Humanoid.Health_XML being CanSave true (obsolete properties basically) - in this case both of them will Load. (aka PropertyPatches)
						CanSave being on same level as CanLoad also fixes potential issues with overlapping properties like Color, Color3 & Color3uint8 of BasePart, out of which only Color3uint8 should save
						This also fixes everything in IgnoreClassProperties automatically without need to hardcode :)
						A very simple fix for many problems that saveinstance scripts encounter!
					--]]
					local PropertyName = Member.Name

					local MemberTags = Member.Tags

					local ValueType = Member.ValueType
					local ValueType_Name = ValueType.Name

					if (645 <= CLIENT_VERSION and ValueType_Name == "Content") or (MemberTags and ArrayToDict(MemberTags)["WriteOnly"]) then -- TODO: Remove the content part after Roblox adds a descriptor for it
						continue
					end

					local Special, PreferredDescriptorName

					if MemberTags then
						for _, tag in MemberTags do
							if type(tag) == "table" then
								PreferredDescriptorName = tag.PreferredDescriptorName
								if PreferredDescriptorName and Special then
									break
								end
							elseif tag == "NotScriptable" then
								Special = true
								if PreferredDescriptorName then
									break
								end
							end
						end
					end

					-- if not Special then
					local Property = {
						Name = PropertyName,
						Category = ValueType.Category,
						-- Default = Member.Default,
						-- Tags = MemberTags,
						ValueType = ValueType_Name,

						Special = Special,

						CanRead = nil,
					}

					if string.sub(ValueType_Name, 1, 8) == "Optional" then
						-- Extract the string after "Optional"
						Property.Optional = string.sub(ValueType_Name, 9)
					end

					if NotScriptableFixClass then
						local NotScriptableFix = NotScriptableFixClass[PropertyName]
						if NotScriptableFix then
							Property.Fallback = type(NotScriptableFix) == "function" and NotScriptableFix
								or PreferredDescriptorName and function(instance)
									local o, r = pcall(index, instance, PreferredDescriptorName)
									if o then
										return r
									end
									return instance[NotScriptableFix]
								end
								or function(instance)
									return instance[NotScriptableFix]
								end
						end
					elseif PreferredDescriptorName then
						Property.Fallback = function(instance)
							return instance[PreferredDescriptorName]
						end
					end
					if ((Serialization.CanSave and Serialization.CanLoad) or ClassWhitelist and ClassWhitelist[PropertyName]) and not (ClassBlacklist and ClassBlacklist[PropertyName]) then
						ClassProperties[ClassProperties_size] = Property
						ClassProperties_size += 1
					else
						NotSaveableClassProperties[NotSaveableClassProperties_size] = Property
						NotSaveableClassProperties_size += 1
					end
					-- end
				end
			end

			classList[ClassName] = Class
		end

		-- classList.Instance.Properties.Parent = nil -- ? Not sure if this is a better option than filtering through properties to remove this

		return classList
	end

	local ok, result = pcall(FetchAPI)
	if ok then
		ClassList = result
	else
		warn("Failed to load the API Dump")
		warn(result)
		return
	end
end

local GLOBAL_ENV = getgenv and getgenv() or _G or shared

--[=[
  # Options Documentation
> [!NOTE]
All options are case insensitive.
- __DEBUG_MODE: `boolean`
  - This will print debug logs to console about unusual scenarios. Recommended to enable if you wish to help us improve our products and find bugs / issues with it!
  - Default: false
- Crashlog: `boolean`
  - Logs every instance saved and property read to a file. Useful for debugging crashes.
  - Default: false
- ReadMe: `boolean`
  - Includes a script parented to game in the file, containing credits, fixes, and the options used to generate the file.
  - Default: true
- SafeMode: `boolean`
  - Kicks you before Saving, which prevents you from being detected in any game.
  - Default: false
- ShutdownWhenDone: `boolean`
  - Shuts the game down after saveinstance is finished.
  - Default: false
- AntiIdle: `boolean`
  - Prevents the 20-minute-Idle Kick.
  - Default: true
- Anonymous: `boolean or table`
  - Cleans the file of any info related to your account like: Name, UserId.
  - This is useful for some games that might store that info in GUIs or other Instances.
  - Might potentially mess up parts of strings that contain characters that match your Name or parts of numbers that match your UserId.
  - By default this replaces your Name with "Roblox" and UserId with "1".
  - These replacements can be customized by providing a table with a name and userid. Ex: {Name = "Roblox", UserId = "1"}
  - Default: false
- ShowStatus: `boolean`
  - Shows what Saveinstance is currently doing in a GUI.
  - Default: true
- Callback: `function`
  - If set, the serialized data will be sent to the callback function instead of to file.
  - Default: false
- mode: `string or table`
  - Controls what instances to save.
  - Valid Modes:
    - optimized: Saves a hardcoded list of services, best for general use.
    - full: Saves all services.
    - scripts: Might be removed soon, don't use this.
    - To create a custom mode, provide a table of strings with each string being a service name to save.
  - Change this to invalid mode like "invalid" if you only want ExtraInstances.
  - "optimized" mode is NOT supported with @Object option.
  - Default: "optimized"
- noscripts: `boolean`
  - Disables scripts from decompiling.
  - Aliases: Decompile (inverse, takes priority)
  - Default: false
- scriptcache: `boolean`
  - Caches decompiled scripts, so if a script with the same bytecode appears in a game multiple times, it only needs to be decompiled once.
  - The cache is kept between runs in the same game session, and is thrown away automatically when saveinstance is updated (output from an older version is never reused).
  - Default: true
- decomptype: `string`
  - "builtin" - BetterDecompiler, included in this script: rebuilds if / elseif / while / repeat / for / break / continue, and/or expressions, `x = a and b or c`, table constructors, method calls and named functions straight from the bytecode, and never emits goto. A function whose structure cannot be rebuilt is emitted in an exact low-level form instead (marked "[low-level]"). If it cannot read a script at all (e.g. a newer bytecode version), the executor's decompiler is used for that script. Default.
  - "executor" - your executor's own decompiler.
  - "custom" - Konstant.
  - Uses Konstant 2.1, locally hosted instead of the API to increase speed. ([Konstant Discord Server](https://discord.gg/wyButjTMhM), [Konstant Decompiled Source Code](https://raw.githubusercontent.com/exacaca/BetterSaveinstance/refs/heads/main/Dependencies/Konstant%20V2.1.luau))
  - Default: "builtin"
- timeout: `number`
  - If the decompilation run time exceeds this value it gets cancelled.
  - Set to -1 to disable timeout (unreliable).
  - Aliases: DecompileTimeout
  - Default: 10
- ScriptHeaders: `boolean`
  - Adds the "-- Saved by ..." and "-- Decompiled with ..." comments at the top of every saved script.
  - Off by default: they shift every line number by 4. The saved file itself still says what saved it.
  - Default: false
- MatchLineNumbers: `boolean`
  - Built-in decompiler: puts every statement on the line it has in the original script (Roblox keeps
    line numbers in the bytecode), so errors, tracebacks and `debug.info` report the original lines.
    Code is kept on its own lines where the original had room, joined onto one line where it was denser.
  - Default: true
- RenameVariables: `boolean`
  - Renames the generic names decompilers emit (`v14`, `p1`, `s1`, `arg3`, `var_1`, ...) to names inferred from what each variable is assigned from, or how each parameter is used.
    - `local v14 = load("ClientStore")` becomes `local ClientStore = load("ClientStore")`
    - `local v28 = child:GetChildren()[1]` becomes `local firstChild = ...`
    - `function set_house_edit_mode(p2)` becomes `function set_house_edit_mode(house_edit_mode)`
    - Not used on the built-in decompiler's output, which already names variables itself (Roblox style).
  - Works with any other decompiler, because it runs on the decompiled text.
  - Only names change. Strings, comments, table keys, type annotations and formatting come out byte for byte as the decompiler produced them.
  - Each new name is unique within its function and every function enclosing it, so nothing can be shadowed.
  - Default: true
- FixGoto: `boolean`
  - Rewrites the `goto` statements some decompilers emit into Luau's `continue` / `break`. Luau has no `goto` and no `::labels::` at all, so a script containing even one fails to parse and everything that requires it fails to load.
    - A label at the end of a loop body: every `goto` to it becomes `continue`
    - A label immediately after a loop's `end`: every `goto` to it becomes `break`
    - The label itself is then removed
  - Only provably equivalent jumps are rewritten. The jump must be in the same function and the same loop as its label, and must be the last statement of its block, which is what Luau requires of `continue` / `break`. If even one jump to a label does not qualify, that label and all of its jumps are left exactly as they were. `repeat ... until` loops are skipped, as Luau restricts `continue` there.
  - A `goto l0` whose label is missing entirely cannot be rewritten (the decompiler lost the loop structure); see RebuildFromBytecode.
  - Default: true
- RebuildFromBytecode: `boolean`
  - Every decompiled script is compiled (never run) with loadstring to check it is valid Luau, and scanned for `until x == x` (a decompiler naming bug that makes a loop stop after one pass).
  - Any function that fails either check is rebuilt straight from the script's bytecode and spliced into the decompiled output. The rebuilt function behaves exactly like the original (it is low level: registers are `__R[n]`, jumps set `__pc`), and the decompiler's readable attempt is kept in a comment right above it. Search the output for "rebuilt from bytecode".
  - If the problem is in the main body of the script (not inside a function), the whole script is rebuilt this way, with the decompiler's attempt kept in a comment at the end.
  - Invalid `p1: function` / `p1: function?` type annotations are always repaired first.
  - Supports Luau bytecode versions 3 to 6 (plain and Roblox-encoded opcodes).
  - Default: true
- DecompilerFallback: `boolean`
  - If a script still does not compile after the function rebuild above, it is decompiled again with Konstant, and Konstant's output is used only if it compiles and Konstant reported no failed functions (KONSTANTERROR).
  - If nothing works, the decompiler's output is kept with a `-- WARNING: This decompiled script does NOT compile` header that says why.
  - Default: true
- DecompileJobless: `boolean`
  - Includes already decompiled code in the output. No new scripts are decompiled.
  - Enables the option ScriptCache
  - Default: false
- SaveBytecode: `boolean`
  -  Includes bytecode in the output. Useful if you wish to be able to decompile it yourself later.
  -  Default: false
- SaveCompilationErrors: `boolean`
  - If a script fails to compile, this option saves the compilation error in the script instead of trying to pass it to the decompiler (or savebytecode), which will always result in a fail.
  - Also applies when decompilation is disabled
  - Default: true
- SaveBytecodeIfDecompilerFails: `boolean`
  - Includes bytecode in the output ONLY in these cases: if the decompiler fails (works on most decompilers), if noscripts is enabled, or if the decompiler isn't found. Useful if you wish to be able to decompile it yourself later.
  - Option Savebytecode takes priority over this. 
  - Default: false
- SaveAsAttributes `boolean`
  - Saves properties that cannot be saved or loaded by roblox studio (CanSave or CanLoad = false in the api dump) by converting them into attributes.
  - These properties aren't saved otherwise, but nothing too useful is in them.
  - Creates a Configuration instance parented to game that contains game's properties called DataModelProperties.
  - Attribute Name Format: Prefix `__NotSaveable_` then the property name with all non alphanumeric characters removed besides underscores.
  - Default: false
- DecompileIgnore: `{Instance | Instance.ClassName | [Instance.ClassName]={Instance.Name}}`
  - Ignores match & its descendants by default. To Ignore only the instance itself set the value to = false. Examples: "Chat", - Matches any instance with "Chat" ClassName, Players = {"MyPlayerName"} - Matches "Players" Class AND "MyPlayerName" Name ONLY, workspace - matches Instance by reference, [workspace] = false - matches Instance by reference and only ignores the instance itself and not its descendants.
  - Default: {TextChatService}
- IgnoreList: `{Instance | Instance.ClassName | [Instance.ClassName]={Instance.Name}}`
  - Prevents instances from saving.
  - Structure is similar to @DecompileIgnore except = false meaning if you ignore one instance it will automatically ignore its descendants.
  - Default: {CoreGui, CorePackages}
- ExtraInstances: `{Instance}`
  - If used with any invalid mode (like "invalidmode") it will only save these instances.
  - Default: {}
- IgnoreProperties: `table`
  - Ignores properties by Name.
  - Default: {}
- SaveCacheInterval: `number`
  - The less the value the more often it saves, but that would mean less performance due to constantly saving.
  - Default: 0x1600 * 10
- FilePath: `string`
  - Must only contain the name of the file, no file extension.
  - EX: FilePath = "Place" not "Place.rbxlx"
  - Aliases: FileName
  - Default: false
- Object: `Instance`
  - If provided, saves as .rbxmx (Model file) instead. If Object is game, it will be saved as a .rbxl file. MUST BE AN INSTANCE REFERENCE, FOR EXAMPLE - game.Workspace. "optimized" mode is NOT supported with this option. If IsModel is set to false then Object specified here will be saved as a place file.
  - Default: false
- IsModel: `boolean`
  - Saves the file as a model (.rbxmx).
  - If Object is specified then sets to true automatically, unless you set it to false.
  - Default: false
- NilInstances: `boolean`
  - Save instances that aren't parented (parented to nil) in the folder game["Nil Instances"]
  - Enables SaveNotCreatable
  - Default: false
- NilInstancesFixes: `{[Instance.ClassName]=function}`
  - This can cause some Classes to be fixed even though they might not need the fix (better be safe than sorry though). For example, Bones inherit from Attachment if we don't define them in the NilInstancesFixes then this will catch them anyways. TO AVOID THIS BEHAVIOR USE THIS EXAMPLE: {ClassName_That_Doesnt_Need_Fix = false}.
  - Default: {Animator = function, AdPortal = function, BaseWrap = function, Attachment = function}
- IgnoreDefaultProperties: `boolean`
  - Ignores default properties during saving.
  - Aliases: IgnoreDefaultProps
  - Default: true
- IgnoreNotArchivable: `boolean`
  - Ignores the Archivable property and saves Non-Archivable instances.
  - Aliases: IgnoreArchivable 
  - Default: true
- IgnorePropertiesOfNotScriptsOnScriptsMode: `boolean`
  - Ignores properties of every instance that is not a script in "scripts" mode.
  - Default: false
- IgnoreSpecialProperties: `boolean`
  - Prevents calls to gethiddenproperty and uses fallback methods instead. This also helps with crashes. If your file is corrupted after saving, you can try turning this on.
  - Default: false (except on the executors Fluxus, Solara, Visual, WRD, and JJSploit x Xeno)
- IsolateLocalPlayer: `boolean`
  - Saves Children of LocalPlayer as separate folder and prevents any instance of ClassName Player with .Name identical to LocalPlayer.Name from saving.
  - Enables SaveNotCreatable
  - Aliases: IsolatePlayerGui
  - Default: false
- IsolateStarterPlayer: `boolean`
  - If enabled, StarterPlayer will be cleared and the saved starter player will be placed into folders.
  - Default: false
- IsolateLocalPlayerCharacter: `boolean`
  - Saves Children of LocalPlayer.Character as separate folder, and prevents the character from saving in workspace.
  - Enables SaveNotCreatable
  - Default: false
- RemovePlayerCharacters: `boolean`
  - Ignore player characters while saving.
  - Enables SaveNotCreatable automatically
  - Aliases: SavePlayerCharacters (inverse, takes priority)
  - Default: true
- SaveNotCreatable: `boolean`
  - Includes non-serializable instances as Folder objects (Name is misleading as this is mostly a fix for certain NilInstances and isn't always related to NotCreatable).
  - The instances this is applied to is controlled by NotCreatableFixes
  - Default: false
- NotCreatableFixes: `table<Instance.ClassName>`
  - The instances to convert using SaveNotCreatable
  - {"Player"} is the same as {Player = "Folder"}; Format like {SpawnLocation = "Part"} is only to be used when SpawnLocation inherits from "Part" AND "Part" is Creatable.
  - Default: { "", "Player", "PlayerScripts", "PlayerGui", "TouchTransmitter" }
 - SavePropsAsAttributesForNotCreatableFixes
   - Converts CanSave/CanLoad properties of instances with a NotCreatableFix which can't be saved otherwise into attributes.
   - Doesn't save properties when they are already saved normally. (Ex: In the spawnlocation example above, only properties that only apply to the spawnlocation, not the part will be saved)
   - Attribute Name Format: Same as SaveAsAttributes but with the prefix `__NotCreatableFix_`.
   - Default: false
- IsolatePlayers: `boolean`
  - Saves players in a seperate folder.
  - Enables SaveNotCreatable
  - Aliases: SavePlayers, RemovePlayers (inverse, takes priority)
  - Default: false
- AlternativeWritefile: `boolean`
  - Splits file content string into segments and writes them using appendfile. This might help with crashes when it starts writing to file. Though there is a risk of appendfile working incorrectly on some executors.
  - Default: true (except on the executors JJSploit, Xeno, Zorara)
- IgnoreDefaultPlayerScripts: `boolean`
  - Ignores Default PlayerScripts like PlayerModule & RbxCharacterSounds. Prevents crashes on certain Executors.
  - Default: true
- IgnoreSharedStrings: `boolean`
  - Prevents the value type "SharedString" from saving. Prevents Crashes on some executors.
  - Default: true (except on the executors Wave, Potassium, Zenith, Seliware, Volcano, Velocity and Swift, as they are confirmed to support sharedstrings.)
- SharedStringOverwrite: `boolean`
  - SharedStrings can also be used for ValueTypes that aren't SharedString, this behavior is not documented anywhere but makes sense (Could create issues though, due to potential ValueType mix-up, only works on certain types which are all base64 encoded so far).
  - Reason: Allows for potential smaller file size (can also be bigger in some cases).
  - Default: false
- TreatUnionsAsParts: `boolean`
  - Converts all UnionOperations to Parts. Useful if your Executor isn't able to save (read) Unions, because otherwise they will be invisible.
  - Default: false (except on Solara, Xeno, and JJSploit)
# Function Documentation
- SynSaveInstance.saveinstance(
  - Parameter_1: `variant<table,table<Instance>>`
    - Can either be SynSaveInstance.CustomOptions table or a filled with instances ({Instance}).
    - If it is filled with instances, then it will be treated as ExtraInstances with an invalid mode and IsModel will be true.
  - Parameter_2: `table`
    - Optional
    - If present, then Parameter_2 will be assumed to be SynSaveInstance.CustomOptions table.
    - If Parameter_1 is an Instance, then it will be assumed to be SynSaveInstance.CustomOptions table.Object.
    - If Parameter_1 is a table filled with instances ({Instance}), then it will be assumed to be SynSaveInstance.CustomOptions table.ExtraInstances and IsModel will be true
    - This exists for sake compatibility with saveinstance(game, {})
- ) → ()
]=]

-- * BytecodeLifter: turns Luau bytecode (v3-v6) back into Luau source that does exactly
-- * what the bytecode does. Every register is a slot in `__R`, every jump is an assignment
-- * to `__pc`, so ANY control flow (the kind decompilers fail on and emit `goto` for) is
-- * reproduced exactly. Registers captured by closures live in boxes (`__X`) that are
-- * swapped on CLOSEUPVALS, which is how the VM gives each loop iteration a fresh upvalue.
local BytecodeLifter = {}
do
	local band, bor, rshift = bit32.band, bit32.bor, bit32.rshift
	local fmt, concat, rep = string.format, table.concat, string.rep

	local OP_NAMES = {
		[0] = "NOP", "BREAK", "LOADNIL", "LOADB", "LOADN", "LOADK", "MOVE", "GETGLOBAL", "SETGLOBAL",
		"GETUPVAL", "SETUPVAL", "CLOSEUPVALS", "GETIMPORT", "GETTABLE", "SETTABLE", "GETTABLEKS",
		"SETTABLEKS", "GETTABLEN", "SETTABLEN", "NEWCLOSURE", "NAMECALL", "CALL", "RETURN", "JUMP",
		"JUMPBACK", "JUMPIF", "JUMPIFNOT", "JUMPIFEQ", "JUMPIFLE", "JUMPIFLT", "JUMPIFNOTEQ",
		"JUMPIFNOTLE", "JUMPIFNOTLT", "ADD", "SUB", "MUL", "DIV", "MOD", "POW", "ADDK", "SUBK", "MULK",
		"DIVK", "MODK", "POWK", "AND", "OR", "ANDK", "ORK", "CONCAT", "NOT", "MINUS", "LENGTH",
		"NEWTABLE", "DUPTABLE", "SETLIST", "FORNPREP", "FORNLOOP", "FORGLOOP", "FORGPREP_INEXT",
		"FASTCALL3", "FORGPREP_NEXT", "NATIVECALL", "GETVARARGS", "DUPCLOSURE", "PREPVARARGS",
		"LOADKX", "JUMPX", "FASTCALL", "COVERAGE", "CAPTURE", "SUBRK", "DIVRK", "FASTCALL1",
		"FASTCALL2", "FASTCALL2K", "FORGPREP", "JUMPXEQKNIL", "JUMPXEQKB", "JUMPXEQKN", "JUMPXEQKS",
		"IDIV", "IDIVK", "GETUDATAKS", "SETUDATAKS", "NAMECALLUDATA", "NEWCLASSMEMBER", "CALLFB",
		"CMPPROTO", "FASTPCALL", "NEWCLASS",
	}
	local OP = {}
	for code = 0, #OP_NAMES do
		OP[OP_NAMES[code]] = code
	end
	local OP_COUNT = #OP_NAMES + 1

	local HAS_AUX = {}
	for _, name in
		{
			"GETGLOBAL", "SETGLOBAL", "GETIMPORT", "GETTABLEKS", "SETTABLEKS", "NAMECALL", "JUMPIFEQ",
			"JUMPIFLE", "JUMPIFLT", "JUMPIFNOTEQ", "JUMPIFNOTLE", "JUMPIFNOTLT", "NEWTABLE", "SETLIST",
			"FORGLOOP", "LOADKX", "FASTCALL2", "FASTCALL2K", "FASTCALL3", "JUMPXEQKNIL", "JUMPXEQKB",
			"JUMPXEQKN", "JUMPXEQKS", "GETUDATAKS", "SETUDATAKS", "NAMECALLUDATA", "NEWCLASSMEMBER", "CALLFB",
			"CMPPROTO", "NEWCLASS",
		}
	do
		HAS_AUX[OP[name]] = true
	end

	local KEYWORDS = {}
	for word in string.gmatch(
		"and break do else elseif end false for function if in local nil not or repeat return then true until while continue",
		"%S+"
	) do
		KEYWORDS[word] = true
	end

	local function isIdent(s)
		return type(s) == "string" and string.match(s, "^[%a_][%w_]*$") ~= nil and not KEYWORDS[s]
	end
	BytecodeLifter.isIdent = isIdent

	--------------------------------------------------------------------------
	-- parsing
	--------------------------------------------------------------------------

	local function parse(bytecode)
		local buf = buffer.fromstring(bytecode)
		local size = #bytecode
		local pos = 0
		local function need(n)
			if pos + n > size then
				error("truncated bytecode", 0)
			end
		end
		local function u8()
			need(1)
			local v = buffer.readu8(buf, pos)
			pos += 1
			return v
		end
		local function u32()
			need(4)
			local v = buffer.readu32(buf, pos)
			pos += 4
			return v
		end
		local function varint64()
			local result, scale = 0, 1
			for _ = 1, 10 do
				local b = u8()
				result += band(b, 127) * scale
				if b < 128 then
					return result
				end
				scale *= 128
			end
			error("bad varint", 0)
		end
		local function varint()
			local result, scale = 0, 1
			for _ = 1, 5 do
				local b = u8()
				result += band(b, 127) * scale
				if b < 128 then
					return result
				end
				scale *= 128
			end
			error("bad varint", 0)
		end

		local version = u8()
		if version == 0 then
			error("the script failed to compile: " .. string.sub(bytecode, 2), 0)
		elseif version < 3 or version > 14 then
			error("unsupported bytecode version " .. version, 0)
		end
		local typesVersion = 0
		if version >= 4 then
			typesVersion = u8()
			if typesVersion > 3 then
				error("unsupported types version " .. typesVersion, 0)
			end
		end

		local strings = {}
		for i = 1, varint() do
			local len = varint()
			need(len)
			strings[i] = buffer.readstring(buf, pos, len)
			pos += len
		end
		if typesVersion == 3 then
			local index = u8()
			while index ~= 0 do
				varint()
				index = u8()
			end
		end

		local protos = {}
		local protoCount = varint()
		for id = 0, protoCount - 1 do
			-- * v12+: every function is prefixed with its size, so trailing data can be skipped
			local protoSize, protoStart
			if version >= 12 then
				protoSize = varint()
				protoStart = pos
			end
			local p = { id = id }
			p.maxstack = u8()
			p.numparams = u8()
			p.nups = u8()
			p.isvararg = u8() ~= 0
			if version >= 4 then
				p.flags = u8()
				local typesize = varint()
				need(typesize)
				pos += typesize
			end
			local sizecode = varint()
			p.codeOffset = pos
			local code = {}
			for i = 0, sizecode - 1 do
				code[i] = u32()
			end
			p.code, p.sizecode = code, sizecode

			local k = {}
			for i = 0, varint() - 1 do
				local t = u8()
				if t == 0 then
					k[i] = { t = "nil" }
				elseif t == 1 then
					k[i] = { t = "boolean", v = u8() ~= 0 }
				elseif t == 2 then
					need(8)
					k[i] = { t = "number", v = buffer.readf64(buf, pos) }
					pos += 8
				elseif t == 3 then
					k[i] = { t = "string", v = strings[varint()] }
				elseif t == 4 then
					k[i] = { t = "import", v = u32() }
				elseif t == 5 then
					local keys = {}
					for j = 1, varint() do
						keys[j] = varint()
					end
					k[i] = { t = "table", v = keys }
				elseif t == 8 then
					-- * v7: DUPTABLE template whose keys may come with constant values
					local keys, vals = {}, {}
					for j = 1, varint() do
						keys[j] = varint()
						need(4)
						vals[j] = buffer.readi32(buf, pos)
						pos += 4
					end
					k[i] = { t = "table", v = keys, vals = vals }
				elseif t == 9 then
					-- * v8: 64-bit integer
					local negative = u8() ~= 0
					local magnitude = varint64()
					k[i] = { t = "number", v = negative and -magnitude or magnitude }
				elseif t == 11 then
					-- * v13: double precision vector
					need(32)
					k[i] = {
						t = "vector",
						v = {
							buffer.readf64(buf, pos),
							buffer.readf64(buf, pos + 8),
							buffer.readf64(buf, pos + 16),
							buffer.readf64(buf, pos + 24),
						},
					}
					pos += 32
				elseif t == 6 then
					k[i] = { t = "closure", v = varint() }
				elseif t == 7 then
					need(16)
					k[i] = {
						t = "vector",
						v = {
							buffer.readf32(buf, pos),
							buffer.readf32(buf, pos + 4),
							buffer.readf32(buf, pos + 8),
							buffer.readf32(buf, pos + 12),
						},
					}
					pos += 16
				else
					error("unsupported constant type " .. t, 0)
				end
			end
			p.k = k

			local children = {}
			for i = 0, varint() - 1 do
				children[i] = varint()
			end
			p.p = children
			p.linedefined = varint()
			local debugname = varint()
			p.debugname = debugname ~= 0 and strings[debugname] or nil

			if u8() ~= 0 then -- line info
				local gaplog2 = u8()
				local intervals = rshift(sizecode - 1, gaplog2) + 1
				local lineinfo, abslineinfo = {}, {}
				local last = 0
				for i = 0, sizecode - 1 do
					last = (last + u8()) % 256
					lineinfo[i] = last
				end
				local lastline = 0
				for i = 0, intervals - 1 do
					need(4)
					lastline += buffer.readi32(buf, pos)
					pos += 4
					abslineinfo[i] = lastline
				end
				p.lineOf = function(pc)
					local base = abslineinfo[rshift(pc, gaplog2)]
					return base and base + lineinfo[pc] or nil
				end
			end
			if u8() ~= 0 then -- debug info (only with -g2: real local and upvalue names)
				local locvars = {}
				for n = 1, varint() do
					local name = varint()
					local startpc = varint()
					local endpc = varint()
					local reg = u8()
					locvars[n] = { name = strings[name], startpc = startpc, endpc = endpc, reg = reg }
				end
				local upvalnames = {}
				for n = 1, varint() do
					upvalnames[n] = strings[varint()]
				end
				p.locvars, p.upvalnames = locvars, upvalnames
			end
			if version >= 11 and not protoSize then
				for _ = 1, varint() do -- * feedback vector
					u8()
					varint()
				end
			end
			if protoSize then
				pos = protoStart + protoSize
			end
			protos[id] = p
		end
		local main = varint()
		if not protos[main] then
			error("bad main proto", 0)
		end

		-- * Roblox stores opcodes multiplied by 227 (mod 256). 203 is its inverse.
		local function validWith(decode)
			for id = 0, protoCount - 1 do
				local p = protos[id]
				local pc = 0
				while pc < p.sizecode do
					local op = decode(p.code[pc])
					if op >= OP_COUNT then
						return false
					end
					pc += HAS_AUX[op] and 2 or 1
				end
				if pc ~= p.sizecode then
					return false
				end
			end
			return true
		end
		local function vanilla(insn)
			return band(insn, 255)
		end
		local function encoded(insn)
			return (band(insn, 255) * 203) % 256
		end
		local first = protos[main].code[0]
		local decode
		if first and vanilla(first) == OP.PREPVARARGS and validWith(vanilla) then
			decode = vanilla
		elseif first and encoded(first) == OP.PREPVARARGS and validWith(encoded) then
			decode = encoded
		elseif validWith(vanilla) then
			decode = vanilla
		elseif validWith(encoded) then
			decode = encoded
		else
			error("could not decode the opcodes", 0)
		end

		return { version = version, protos = protos, main = main, decode = decode, strings = strings }
	end
	BytecodeLifter.parse = parse

	--------------------------------------------------------------------------
	-- source generation
	--------------------------------------------------------------------------

	local function strLit(s)
		return '"'
			.. string.gsub(s, '[%c"\\]', function(c)
				if c == "\n" then
					return "\\n"
				elseif c == "\t" then
					return "\\t"
				elseif c == "\r" then
					return "\\r"
				elseif c == '"' or c == "\\" then
					return "\\" .. c
				end
				return fmt("\\%03d", string.byte(c))
			end)
			.. '"'
	end

	local function numLit(n)
		if n ~= n then
			return "(0/0)"
		elseif n == math.huge then
			return "(1/0)"
		elseif n == -math.huge then
			return "(-1/0)"
		elseif n == 0 then
			return (1 / n < 0) and "(-0)" or "0"
		end
		local s
		if n == math.floor(n) and math.abs(n) < 1e15 then
			s = fmt("%d", n)
			return n < 0 and "(" .. s .. ")" or s
		end
		for digits = 1, 17 do
			s = fmt("%." .. digits .. "g", n)
			if tonumber(s) == n then
				break
			end
		end
		if n < 0 then
			return "(" .. s .. ")"
		end
		return s
	end

	local function constText(k)
		local t = k.t
		if t == "nil" then
			return "nil"
		elseif t == "boolean" then
			return k.v and "true" or "false"
		elseif t == "number" then
			return numLit(k.v)
		elseif t == "string" then
			return strLit(k.v)
		elseif t == "vector" then
			return fmt("Vector3.new(%s, %s, %s)", numLit(k.v[1]), numLit(k.v[2]), numLit(k.v[3]))
		end
		error("constant of type " .. t .. " used as a value", 0)
	end

	local function indexText(base, key)
		if isIdent(key) then
			return base .. "." .. key
		end
		return base .. "[" .. strLit(key) .. "]"
	end

	local function sext16(v)
		return v >= 0x8000 and v - 0x10000 or v
	end
	local function sext24(v)
		return v >= 0x800000 and v - 0x1000000 or v
	end

	-- * opts: { upnames = {[1..nups] = expression text} (top level only),
	-- *         globals = set filled with every global name the code reads/writes }
	local genProto

	local function decodeProto(chunk, p)
		local decode = chunk.decode
		local insns, byPc = {}, {}
		local pc = 0
		while pc < p.sizecode do
			local word = p.code[pc]
			local op = decode(word)
			local ins = {
				pc = pc,
				op = op,
				a = band(rshift(word, 8), 255),
				b = band(rshift(word, 16), 255),
				c = band(rshift(word, 24), 255),
				d = sext16(rshift(word, 16)),
				e = sext24(rshift(word, 8)),
			}
			if HAS_AUX[op] then
				ins.aux = p.code[pc + 1]
				ins.size = 2
			else
				ins.size = 1
			end
			if op == OP.GETUDATAKS or op == OP.SETUDATAKS or op == OP.NAMECALLUDATA then
				-- * userdata field access: same as GETTABLEKS / SETTABLEKS / NAMECALL (16 bit constant)
				ins.op = op == OP.GETUDATAKS and OP.GETTABLEKS or op == OP.SETUDATAKS and OP.SETTABLEKS or OP.NAMECALL
				ins.aux = band(ins.aux, 0xFFFF)
			elseif op == OP.CALLFB then
				ins.op = OP.CALL -- * a call that also records profiling feedback
			elseif op == OP.CMPPROTO then
				-- * speculative "is this the known function?" check: the jump goes to the general
				-- * path, which does the same thing, so always taking it is exact
				ins.op = OP.JUMP
			elseif op == OP.FASTPCALL then
				ins.op = OP.NOP -- * a hint; the CALL that follows does the work
			elseif op == OP.NEWCLASS or op == OP.NEWCLASSMEMBER then
				error("Luau classes are not supported", 0)
			end
			ins.next = pc + ins.size
			insns[#insns + 1] = ins
			byPc[pc] = ins
			pc = ins.next
		end
		return insns, byPc
	end

	function genProto(chunk, id, opts, indent)
		local p = chunk.protos[id]
		local K = p.k
		local insns, byPc = decodeProto(chunk, p)
		local globals = opts.globals
		local upnames = opts.upnames -- * only for the top level function

		-- * registers ever captured by reference live in boxes
		local captured, capturedList = {}, {}
		for _, ins in insns do
			if ins.op == OP.CAPTURE and ins.a == 1 and not captured[ins.b] then
				captured[ins.b] = true
				capturedList[#capturedList + 1] = ins.b
			end
		end
		table.sort(capturedList)
		local anyCaptured = #capturedList > 0

		local function R(r)
			if captured[r] then
				return "__X[" .. r .. "].v"
			end
			return "__R[" .. r .. "]"
		end
		local function Kt(i)
			local k = K[i]
			if not k then
				error("missing constant " .. tostring(i), 0)
			end
			if k.t == "vector" then
				globals.Vector3 = true
			end
			return constText(k)
		end
		local function Ks(i)
			local k = K[i]
			if not k or k.t ~= "string" then
				error("expected a string constant at " .. tostring(i), 0)
			end
			return k.v
		end
		local function upvalue(i)
			if upnames then
				local name = upnames[i + 1]
				if not name then
					error("no name for upvalue " .. i, 0)
				end
				return name
			end
			return "__U[" .. (i + 1) .. "].v"
		end
		local function upvalueBox(i)
			if upnames then
				local name = upvalue(i)
				globals.setmetatable = true
				return "setmetatable({}, { __index = function() return "
					.. name
					.. " end, __newindex = function(_, _, __v) "
					.. name
					.. " = __v end })"
			end
			return "__U[" .. (i + 1) .. "]"
		end
		local function global(name)
			if not isIdent(name) then
				error("global with an unusable name: " .. tostring(name), 0)
			end
			globals[name] = true
			return name
		end

		-- * jump targets / block leaders
		local leaders = { [0] = true }
		local function target(ins, offset)
			local t = ins.pc + 1 + offset
			if not byPc[t] then
				error(fmt("jump to %d from %d is not an instruction", t, ins.pc), 0)
			end
			leaders[t] = true
			return t
		end
		local CONDITIONAL = {
			[OP.JUMPIF] = true, [OP.JUMPIFNOT] = true, [OP.JUMPIFEQ] = true, [OP.JUMPIFLE] = true,
			[OP.JUMPIFLT] = true, [OP.JUMPIFNOTEQ] = true, [OP.JUMPIFNOTLE] = true, [OP.JUMPIFNOTLT] = true,
			[OP.JUMPXEQKNIL] = true, [OP.JUMPXEQKB] = true, [OP.JUMPXEQKN] = true, [OP.JUMPXEQKS] = true,
			[OP.FORNPREP] = true, [OP.FORNLOOP] = true, [OP.FORGLOOP] = true,
		}
		local UNCONDITIONAL = {
			[OP.JUMP] = true, [OP.JUMPBACK] = true, [OP.JUMPX] = true, [OP.FORGPREP] = true,
			[OP.FORGPREP_INEXT] = true, [OP.FORGPREP_NEXT] = true,
		}
		local consumedCapture = {}
		for _, ins in insns do
			local op = ins.op
			if CONDITIONAL[op] or UNCONDITIONAL[op] then
				ins.target = target(ins, op == OP.JUMPX and ins.e or ins.d)
				if ins.next < p.sizecode then
					leaders[ins.next] = true
				end
			elseif op == OP.LOADB and ins.c ~= 0 then
				ins.target = target(ins, ins.c)
				if ins.next < p.sizecode then
					leaders[ins.next] = true
				end
			elseif op == OP.RETURN then
				if ins.next < p.sizecode then
					leaders[ins.next] = true
				end
			elseif op == OP.NEWCLOSURE or op == OP.DUPCLOSURE then
				local childId
				if op == OP.NEWCLOSURE then
					childId = p.p[ins.d]
				else
					local k = K[ins.d]
					childId = k and k.t == "closure" and k.v
				end
				local child = childId and chunk.protos[childId]
				if not child then
					error("closure without a function at " .. ins.pc, 0)
				end
				ins.child = childId
				ins.captures = {}
				local cpc = ins.next
				for n = 1, child.nups do
					local cap = byPc[cpc]
					if not cap or cap.op ~= OP.CAPTURE then
						error("missing CAPTURE after closure at " .. ins.pc, 0)
					end
					ins.captures[n] = cap
					consumedCapture[cpc] = true
					cpc = cap.next
				end
			end
		end

		local leaderList = {}
		for pc in leaders do
			leaderList[#leaderList + 1] = pc
		end
		table.sort(leaderList)

		local lines = {}
		local function emit(depth, text)
			lines[#lines + 1] = rep("\t", depth) .. text
		end

		-- * read the dynamic register range [from, __T - 1] as an argument list
		local function dynamicRange(depth, from)
			if not anyCaptured then
				return "table.unpack(__R, " .. from .. ", __T - 1)"
			end
			emit(depth, "local __args = {}")
			emit(
				depth,
				"for __i = "
					.. from
					.. ", __T - 1 do __args[__i - "
					.. (from - 1)
					.. "] = if __X[__i] then __X[__i].v else __R[__i] end"
			)
			return "table.unpack(__args, 1, __T - " .. from .. ")"
		end
		local function storeMany(depth, from, packed)
			emit(depth, "__T = " .. from .. " + " .. packed .. ".n")
			if not anyCaptured then
				emit(depth, "table.move(" .. packed .. ", 1, " .. packed .. ".n, " .. from .. ", __R)")
			else
				emit(
					depth,
					"for __i = 1, "
						.. packed
						.. ".n do local __r = "
						.. (from - 1)
						.. " + __i if __X[__r] then __X[__r].v = "
						.. packed
						.. "[__i] else __R[__r] = "
						.. packed
						.. "[__i] end end"
				)
			end
		end
		local function argList(depth, from, count)
			if count < 0 then
				return dynamicRange(depth, from)
			end
			local parts = {}
			for r = from, from + count - 1 do
				parts[#parts + 1] = R(r)
			end
			return concat(parts, ", ")
		end
		local function jumpTo(depth, pc)
			emit(depth, "__pc = " .. pc)
		end
		local function branch(depth, cond, ins)
			emit(depth, "if " .. cond .. " then __pc = " .. ins.target .. " else __pc = " .. ins.next .. " end")
		end
		local function iterPrep(depth, a)
			globals.type, globals.getmetatable, globals.rawget, globals.next, globals.error, globals.typeof =
				true, true, true, true, true, true
			emit(depth, "do")
			emit(depth + 1, "local __f = " .. R(a))
			emit(depth + 1, 'if type(__f) ~= "function" then')
			emit(depth + 2, "local __mt = getmetatable(__f)")
			emit(depth + 2, 'local __iter = type(__mt) == "table" and rawget(__mt, "__iter")')
			emit(depth + 2, "if __iter then")
			emit(depth + 3, "local __a, __b, __c = __iter(__f)")
			emit(depth + 3, R(a) .. " = __a; " .. R(a + 1) .. " = __b; " .. R(a + 2) .. " = __c")
			emit(depth + 2, 'elseif type(__f) == "table" then')
			emit(depth + 3, R(a) .. " = next; " .. R(a + 1) .. " = __f; " .. R(a + 2) .. " = nil")
			emit(depth + 2, "else")
			emit(depth + 3, 'error("attempt to iterate over a " .. typeof(__f) .. " value")')
			emit(depth + 2, "end")
			emit(depth + 1, "end")
			emit(depth, "end")
		end

		local function closureText(ins, depth)
			-- * Like the VM: the new closure is stored in its register BEFORE the captures are
			-- * read, so `local function f` can capture itself
			-- * The child sees its upvalue boxes as `__U`, but filling them may need OUR `__U`,
			-- * so the child's table is only named `__U` inside a nested block.
			emit(depth, "do")
			emit(depth + 1, "local __C = {}")
			emit(depth + 1, "do")
			emit(depth + 2, "local __U = __C")
			local childText
			if opts.childHook then
				-- * let the caller (the decompiler) produce the child; its upvalues are our boxes
				local names = {}
				for n = 1, chunk.protos[ins.child].nups do
					names[n] = "__U[" .. n .. "].v"
				end
				childText = opts.childHook(ins.child, names, depth + 2)
			else
				childText = genProto(chunk, ins.child, { globals = globals }, depth + 2)
			end
			emit(depth + 2, R(ins.a) .. " = function" .. childText)
			emit(depth + 1, "end")
			for n, cap in ins.captures do
				local box
				if cap.a == 0 then
					box = "{ v = " .. R(cap.b) .. " }"
				elseif cap.a == 1 then
					box = "__X[" .. cap.b .. "]"
				elseif cap.a == 2 then
					box = upvalueBox(cap.b)
				else
					error("unknown capture type " .. cap.a, 0)
				end
				emit(depth + 1, "__C[" .. n .. "] = " .. box)
			end
			emit(depth, "end")
		end

		-- * returns true when the instruction ends the block (it set __pc or returned)
		local function emitInsn(ins, depth)
			local op, a, b, c = ins.op, ins.a, ins.b, ins.c
			if op == OP.NOP or op == OP.BREAK or op == OP.COVERAGE or op == OP.PREPVARARGS or op == OP.NATIVECALL then
				return false
			elseif op == OP.FASTCALL or op == OP.FASTCALL1 or op == OP.FASTCALL2 or op == OP.FASTCALL2K or op == OP.FASTCALL3 then
				return false -- * only an optimisation hint: the CALL that follows does the same call
			elseif op == OP.CAPTURE then
				if not consumedCapture[ins.pc] then
					error("stray CAPTURE at " .. ins.pc, 0)
				end
				return false
			elseif op == OP.LOADNIL then
				emit(depth, R(a) .. " = nil")
			elseif op == OP.LOADB then
				emit(depth, R(a) .. " = " .. (b ~= 0 and "true" or "false"))
				if c ~= 0 then
					jumpTo(depth, ins.target)
					return true
				end
			elseif op == OP.LOADN then
				emit(depth, R(a) .. " = " .. numLit(ins.d))
			elseif op == OP.LOADK then
				emit(depth, R(a) .. " = " .. Kt(ins.d))
			elseif op == OP.LOADKX then
				emit(depth, R(a) .. " = " .. Kt(ins.aux))
			elseif op == OP.MOVE then
				emit(depth, R(a) .. " = " .. R(b))
			elseif op == OP.GETGLOBAL then
				emit(depth, R(a) .. " = " .. global(Ks(ins.aux)))
			elseif op == OP.SETGLOBAL then
				emit(depth, global(Ks(ins.aux)) .. " = " .. R(a))
			elseif op == OP.GETUPVAL then
				emit(depth, R(a) .. " = " .. upvalue(b))
			elseif op == OP.SETUPVAL then
				emit(depth, upvalue(b) .. " = " .. R(a))
			elseif op == OP.CLOSEUPVALS then
				for _, r in capturedList do
					if r >= a then
						emit(depth, "__X[" .. r .. "] = { v = __X[" .. r .. "].v }")
					end
				end
			elseif op == OP.GETIMPORT then
				local aux = ins.aux
				local count = rshift(aux, 30)
				local ids = { band(rshift(aux, 20), 1023), band(rshift(aux, 10), 1023), band(aux, 1023) }
				if count < 1 or count > 3 then
					error("bad import at " .. ins.pc, 0)
				end
				local text = global(Ks(ids[1]))
				for n = 2, count do
					text = indexText(text, Ks(ids[n]))
				end
				emit(depth, R(a) .. " = " .. text)
			elseif op == OP.GETTABLE then
				emit(depth, R(a) .. " = " .. R(b) .. "[" .. R(c) .. "]")
			elseif op == OP.SETTABLE then
				emit(depth, R(b) .. "[" .. R(c) .. "] = " .. R(a))
			elseif op == OP.GETTABLEKS then
				emit(depth, R(a) .. " = " .. indexText(R(b), Ks(ins.aux)))
			elseif op == OP.SETTABLEKS then
				emit(depth, indexText(R(b), Ks(ins.aux)) .. " = " .. R(a))
			elseif op == OP.GETTABLEN then
				emit(depth, R(a) .. " = " .. R(b) .. "[" .. (c + 1) .. "]")
			elseif op == OP.SETTABLEN then
				emit(depth, R(b) .. "[" .. (c + 1) .. "] = " .. R(a))
			elseif op == OP.NEWCLOSURE or op == OP.DUPCLOSURE then
				closureText(ins, depth)
			elseif op == OP.NAMECALL then
				emit(depth, "do local __o = " .. R(b) .. "; " .. R(a + 1) .. " = __o; " .. R(a) .. " = " .. indexText("__o", Ks(ins.aux)) .. " end")
			elseif op == OP.CALL then
				emit(depth, "do")
				local args = argList(depth + 1, a + 1, b - 1)
				local call = R(a) .. "(" .. args .. ")"
				if c == 0 then
					emit(depth + 1, "local __res = table.pack(" .. call .. ")")
					storeMany(depth + 1, a, "__res")
				elseif c == 1 then
					emit(depth + 1, call)
				elseif c == 2 then
					emit(depth + 1, R(a) .. " = " .. call)
				else
					local names = {}
					for n = 1, c - 1 do
						names[n] = "__r" .. n
					end
					emit(depth + 1, "local " .. concat(names, ", ") .. " = " .. call)
					for n = 1, c - 1 do
						emit(depth + 1, R(a + n - 1) .. " = __r" .. n)
					end
				end
				emit(depth, "end")
			elseif op == OP.RETURN then
				if b == 1 then
					emit(depth, "do return end")
				else
					emit(depth, "do")
					local values = argList(depth + 1, a, b - 1)
					emit(depth + 1, "return " .. values)
					emit(depth, "end")
				end
				return true
			elseif op == OP.JUMP or op == OP.JUMPBACK or op == OP.JUMPX then
				jumpTo(depth, ins.target)
				return true
			elseif op == OP.JUMPIF then
				branch(depth, R(a), ins)
				return true
			elseif op == OP.JUMPIFNOT then
				branch(depth, "not " .. R(a), ins)
				return true
			elseif op == OP.JUMPIFEQ then
				branch(depth, R(a) .. " == " .. R(ins.aux), ins)
				return true
			elseif op == OP.JUMPIFNOTEQ then
				branch(depth, R(a) .. " ~= " .. R(ins.aux), ins)
				return true
			elseif op == OP.JUMPIFLE then
				branch(depth, R(a) .. " <= " .. R(ins.aux), ins)
				return true
			elseif op == OP.JUMPIFLT then
				branch(depth, R(a) .. " < " .. R(ins.aux), ins)
				return true
			elseif op == OP.JUMPIFNOTLE then
				branch(depth, "not (" .. R(a) .. " <= " .. R(ins.aux) .. ")", ins)
				return true
			elseif op == OP.JUMPIFNOTLT then
				branch(depth, "not (" .. R(a) .. " < " .. R(ins.aux) .. ")", ins)
				return true
			elseif op == OP.JUMPXEQKNIL or op == OP.JUMPXEQKB or op == OP.JUMPXEQKN or op == OP.JUMPXEQKS then
				local aux = ins.aux
				local negate = band(aux, 0x80000000) ~= 0
				local value
				if op == OP.JUMPXEQKNIL then
					value = "nil"
				elseif op == OP.JUMPXEQKB then
					value = band(aux, 1) ~= 0 and "true" or "false"
				else
					value = Kt(band(aux, 0xFFFFFF))
				end
				branch(depth, R(a) .. (negate and " ~= " or " == ") .. value, ins)
				return true
			elseif op == OP.ADD or op == OP.SUB or op == OP.MUL or op == OP.DIV or op == OP.MOD or op == OP.POW or op == OP.IDIV then
				local sym = ({ [OP.ADD] = "+", [OP.SUB] = "-", [OP.MUL] = "*", [OP.DIV] = "/", [OP.MOD] = "%", [OP.POW] = "^", [OP.IDIV] = "//" })[op]
				emit(depth, R(a) .. " = " .. R(b) .. " " .. sym .. " " .. R(c))
			elseif op == OP.ADDK or op == OP.SUBK or op == OP.MULK or op == OP.DIVK or op == OP.MODK or op == OP.POWK or op == OP.IDIVK then
				local sym = ({ [OP.ADDK] = "+", [OP.SUBK] = "-", [OP.MULK] = "*", [OP.DIVK] = "/", [OP.MODK] = "%", [OP.POWK] = "^", [OP.IDIVK] = "//" })[op]
				emit(depth, R(a) .. " = " .. R(b) .. " " .. sym .. " " .. Kt(c))
			elseif op == OP.SUBRK then
				emit(depth, R(a) .. " = " .. Kt(b) .. " - " .. R(c))
			elseif op == OP.DIVRK then
				emit(depth, R(a) .. " = " .. Kt(b) .. " / " .. R(c))
			elseif op == OP.AND then
				emit(depth, R(a) .. " = " .. R(b) .. " and " .. R(c))
			elseif op == OP.OR then
				emit(depth, R(a) .. " = " .. R(b) .. " or " .. R(c))
			elseif op == OP.ANDK then
				emit(depth, R(a) .. " = " .. R(b) .. " and " .. Kt(c))
			elseif op == OP.ORK then
				emit(depth, R(a) .. " = " .. R(b) .. " or " .. Kt(c))
			elseif op == OP.CONCAT then
				local parts = {}
				for r = b, c do
					parts[#parts + 1] = R(r)
				end
				emit(depth, R(a) .. " = " .. concat(parts, " .. "))
			elseif op == OP.NOT then
				emit(depth, R(a) .. " = not " .. R(b))
			elseif op == OP.MINUS then
				emit(depth, R(a) .. " = -" .. R(b))
			elseif op == OP.LENGTH then
				emit(depth, R(a) .. " = #" .. R(b))
			elseif op == OP.DUPTABLE and K[ins.d] and K[ins.d].vals then
				local tk = K[ins.d]
				local parts = {}
				for j, keyIdx in tk.v do
					local valIdx = tk.vals[j]
					local valK = valIdx >= 0 and K[valIdx]
					if valK and valK.t ~= "nil" then
						parts[#parts + 1] = "[" .. Kt(keyIdx) .. "] = " .. Kt(valIdx)
					end
				end
				emit(depth, R(a) .. " = {" .. concat(parts, ", ") .. "}")
			elseif op == OP.NEWTABLE or op == OP.DUPTABLE then
				emit(depth, R(a) .. " = {}")
			elseif op == OP.SETLIST then
				local start = ins.aux
				if c == 0 then
					emit(depth, "do")
					emit(depth + 1, "local __t = " .. R(a))
					if anyCaptured then
						emit(depth + 1, "for __i = " .. b .. ", __T - 1 do __t[__i - " .. (b - start) .. "] = if __X[__i] then __X[__i].v else __R[__i] end")
					else
						emit(depth + 1, "for __i = " .. b .. ", __T - 1 do __t[__i - " .. (b - start) .. "] = __R[__i] end")
					end
					emit(depth, "end")
				else
					for n = 0, c - 2 do
						emit(depth, R(a) .. "[" .. (start + n) .. "] = " .. R(b + n))
					end
				end
			elseif op == OP.GETVARARGS then
				if b == 0 then
					storeMany(depth, a, "__V")
				else
					for n = 0, b - 2 do
						emit(depth, R(a + n) .. " = __V[" .. (n + 1) .. "]")
					end
				end
			elseif op == OP.FORNPREP then
				globals.type, globals.tonumber, globals.error = true, true, true
				for n, what in { "limit", "step", "initial value" } do
					local r = R(a + n - 1)
					emit(depth, "if type(" .. r .. ') ~= "number" then ' .. r .. " = tonumber(" .. r .. ') or error("invalid \'for\' ' .. what .. ' (number expected)") end')
				end
				branch(
					depth,
					"(if " .. R(a + 1) .. " > 0 then " .. R(a + 2) .. " <= " .. R(a) .. " else " .. R(a) .. " <= " .. R(a + 2) .. ")",
					{ target = ins.next, next = ins.target }
				)
				return true
			elseif op == OP.FORNLOOP then
				emit(depth, R(a + 2) .. " = " .. R(a + 2) .. " + " .. R(a + 1))
				branch(
					depth,
					"(if " .. R(a + 1) .. " > 0 then " .. R(a + 2) .. " <= " .. R(a) .. " else " .. R(a) .. " <= " .. R(a + 2) .. ")",
					ins
				)
				return true
			elseif op == OP.FORGPREP or op == OP.FORGPREP_INEXT or op == OP.FORGPREP_NEXT then
				iterPrep(depth, a)
				jumpTo(depth, ins.target)
				return true
			elseif op == OP.FORGLOOP then
				local count = band(ins.aux, 255)
				local names = {}
				for n = 1, count do
					names[n] = "__r" .. n
				end
				emit(depth, "do")
				emit(depth + 1, "local " .. concat(names, ", ") .. " = " .. R(a) .. "(" .. R(a + 1) .. ", " .. R(a + 2) .. ")")
				for n = 1, count do
					emit(depth + 1, R(a + 2 + n) .. " = __r" .. n)
				end
				emit(depth, "end")
				emit(depth, "if " .. R(a + 3) .. " ~= nil then " .. R(a + 2) .. " = " .. R(a + 3) .. "; __pc = " .. ins.target .. " else __pc = " .. ins.next .. " end")
				return true
			else
				error("unsupported opcode " .. tostring(OP_NAMES[op] or op) .. " at " .. ins.pc, 0)
			end
			return false
		end

		-- * blocks, dispatched with a binary search on __pc
		local blocks = {}
		for n, start in leaderList do
			blocks[n] = { start = start, stop = leaderList[n + 1] or p.sizecode }
		end

		local function emitBlock(block, depth)
			local pc = block.start
			local ended = false
			if p.lineOf then
				local line = p.lineOf(pc)
				if line then
					emit(depth, "-- line " .. line)
				end
			end
			while pc < block.stop do
				local ins = byPc[pc]
				ended = emitInsn(ins, depth)
				pc = ins.next
			end
			if not ended then
				if block.stop >= p.sizecode then
					emit(depth, "do return end")
				else
					jumpTo(depth, block.stop)
				end
			end
		end

		local function tree(lo, hi, depth)
			if lo == hi then
				emitBlock(blocks[lo], depth)
				return
			end
			local mid = (lo + hi) // 2
			emit(depth, "if __pc < " .. blocks[mid + 1].start .. " then")
			tree(lo, mid, depth + 1)
			emit(depth, "else")
			tree(mid + 1, hi, depth + 1)
			emit(depth, "end")
		end

		local params = {}
		for n = 0, p.numparams - 1 do
			params[#params + 1] = "__a" .. n
		end
		if p.isvararg then
			params[#params + 1] = "..."
		end

		local body = indent + 1
		lines = {}
		emit(body, "local __R, __T, __pc = {}, 0, 0")
		for n = 0, p.numparams - 1 do
			emit(body, "__R[" .. n .. "] = __a" .. n)
		end
		if p.isvararg then
			emit(body, "local __V = table.pack(...)")
		end
		if anyCaptured then
			emit(body, "local __X = {}")
			for _, r in capturedList do
				emit(body, "__X[" .. r .. "] = { v = __R[" .. r .. "] }")
			end
		end
		emit(body, "while true do")
		tree(1, #blocks, body + 1)
		emit(body, "end")
		local bodyLines = lines
		globals.table = true

		return "(" .. concat(params, ", ") .. ")\n" .. concat(bodyLines, "\n") .. "\n" .. rep("\t", indent) .. "end"
	end

	-- * shared with the decompiler
	BytecodeLifter.OP = OP
	BytecodeLifter.OP_NAMES = OP_NAMES
	BytecodeLifter.HAS_AUX = HAS_AUX
	BytecodeLifter.decodeProto = decodeProto
	BytecodeLifter.constText = constText
	BytecodeLifter.numLit = numLit
	BytecodeLifter.strLit = strLit
	BytecodeLifter.indexText = indexText
	BytecodeLifter.KEYWORDS = KEYWORDS

	-- * Lifts one function. `upnames[i]` is the source text of upvalue i (1-based). Returns
	-- * "(params) ... end" (to put right after `function`) and the set of global names used.
	function BytecodeLifter.liftFunction(chunk, protoId, upnames, indent, childHook)
		local globals = {}
		local text = genProto(chunk, protoId, { upnames = upnames or {}, globals = globals, childHook = childHook }, indent or 0)
		return text, globals
	end

	-- * Lifts a whole script (the main function) as top level code.
	function BytecodeLifter.liftScript(chunk, childHook)
		local globals = {}
		local text = genProto(chunk, chunk.main, { upnames = {}, globals = globals, childHook = childHook }, -1)
		-- * strip "(...)\n" and the final "end": the main function becomes the chunk itself
		local body = string.match(text, "^%b()\n(.*)\nend$")
		if not body then
			error("could not unwrap the main function", 0)
		end
		return body, globals
	end
end

-- * BetterDecompiler: a structured Luau decompiler written in Luau.
-- *
-- * bytecode -> data flow (which register writes/reads belong to the same variable)
-- *          -> control flow (if / elseif / while / repeat / for / break / continue, and/or conditions)
-- *          -> expressions (single use temporaries are folded back, in the order the compiler emits them)
-- *          -> variables (declared in the innermost block that needs them, hoisted out of loops only
-- *             when their value or an open upvalue survives into the next iteration)
-- *          -> source
-- *
-- * Every jump in the bytecode must be explained by the structure that is built, otherwise the
-- * function is rebuilt with BytecodeLifter instead (exact, but low level). It never emits goto.
local BetterDecompiler = {}
do
	local Lifter = BytecodeLifter
	local OP = Lifter.OP
	local band, rshift = bit32.band, bit32.rshift
	local concat, insert, remove, rep = table.concat, table.insert, table.remove, string.rep
	local isIdent, strLit, numLit = Lifter.isIdent, Lifter.strLit, Lifter.numLit

	local FAIL = "BetterDecompiler: "
	local function fail(msg)
		error(FAIL .. msg, 0)
	end

	local CONDITIONAL = {
		[OP.JUMPIF] = true, [OP.JUMPIFNOT] = true, [OP.JUMPIFEQ] = true, [OP.JUMPIFLE] = true,
		[OP.JUMPIFLT] = true, [OP.JUMPIFNOTEQ] = true, [OP.JUMPIFNOTLE] = true, [OP.JUMPIFNOTLT] = true,
		[OP.JUMPXEQKNIL] = true, [OP.JUMPXEQKB] = true, [OP.JUMPXEQKN] = true, [OP.JUMPXEQKS] = true,
	}
	local TWO_REG_COMPARE = {
		[OP.JUMPIFEQ] = "==", [OP.JUMPIFLE] = "<=", [OP.JUMPIFLT] = "<",
		[OP.JUMPIFNOTEQ] = "~=", [OP.JUMPIFNOTLE] = "<=", [OP.JUMPIFNOTLT] = "<",
	}
	local NEGATED_COMPARE = { [OP.JUMPIFNOTLE] = true, [OP.JUMPIFNOTLT] = true }
	local UNCONDITIONAL = { [OP.JUMP] = true, [OP.JUMPBACK] = true, [OP.JUMPX] = true }
	local FORGPREPS = { [OP.FORGPREP] = true, [OP.FORGPREP_INEXT] = true, [OP.FORGPREP_NEXT] = true }
	local NOOPS = {
		[OP.NOP] = true, [OP.BREAK] = true, [OP.COVERAGE] = true, [OP.PREPVARARGS] = true, [OP.NATIVECALL] = true,
		[OP.FASTCALL] = true, [OP.FASTCALL1] = true, [OP.FASTCALL2] = true, [OP.FASTCALL2K] = true, [OP.FASTCALL3] = true,
	}
	local ARITH = {
		[OP.ADD] = "+", [OP.SUB] = "-", [OP.MUL] = "*", [OP.DIV] = "/", [OP.MOD] = "%", [OP.POW] = "^", [OP.IDIV] = "//",
	}
	local ARITHK = {
		[OP.ADDK] = "+", [OP.SUBK] = "-", [OP.MULK] = "*", [OP.DIVK] = "/", [OP.MODK] = "%", [OP.POWK] = "^", [OP.IDIVK] = "//",
	}

	--------------------------------------------------------------------------
	-- expressions
	--------------------------------------------------------------------------
	-- * k: const | var | upval | global | index | call | method | binop | unop | and | or | not
	-- *    | concat | vararg | closure | table | paren
	-- * The `...` keeps Luau's -O2 inliner away: it miscompiles `x = E("index", { obj = x })`
	-- * by building the new table straight into `x` before `x` is read (a node that contains itself).
	local function E(k, t, ...)
		t = t or {}
		t.k = k
		return t
	end
	local TRUE = E("const", { text = "true" })

	-- * (a or (b or (c or T))) -> (a or b or c), when T is the rightmost operand of a chain of `op`
	-- * (and/or regroup freely: same values, same evaluation order)
	local function splitTail(node, op, target)
		if node.k ~= op then
			return nil
		end
		if node.r == target then
			return node.l
		end
		local rest = splitTail(node.r, op, target)
		if rest then
			return { k = op, l = node.l, r = rest, el = node.el }
		end
		return nil
	end

	local function isSideEffectFree(e)
		local k = e.k
		return k == "const" or k == "var" or k == "upval" or k == "global" or k == "closure"
			or (k == "table" and #e.entries == 0)
	end

	-- * `not` in a boolean context (if / while / until)
	local function boolNot(e)
		if e.k == "not" then
			return e.e
		elseif e.k == "binop" and e.op == "==" then
			return E("binop", { op = "~=", l = e.l, r = e.r })
		elseif e.k == "binop" and e.op == "~=" then
			return E("binop", { op = "==", l = e.l, r = e.r })
		elseif e.k == "and" then
			return E("or", { l = boolNot(e.l), r = boolNot(e.r) })
		elseif e.k == "or" then
			return E("and", { l = boolNot(e.l), r = boolNot(e.r) })
		end
		return E("not", { e = e })
	end

	--------------------------------------------------------------------------
	-- analysis: jumps, closures, boolean materialisation, multret, data flow
	--------------------------------------------------------------------------
	local function analyze(chunk, p)
		local insns, byPc = Lifter.decodeProto(chunk, p)
		local K = p.k
		local size = p.sizecode

		for i, ins in insns do
			ins.index = i
			local op = ins.op
			if CONDITIONAL[op] or UNCONDITIONAL[op] or op == OP.FORNPREP or op == OP.FORNLOOP or op == OP.FORGLOOP or FORGPREPS[op] then
				ins.target = ins.pc + 1 + (op == OP.JUMPX and ins.e or ins.d)
			elseif op == OP.LOADB and ins.c ~= 0 then
				ins.target = ins.pc + 1 + ins.c
			end
			if ins.target and not byPc[ins.target] then
				fail("jump outside the function")
			end
			if op == OP.NEWCLOSURE or op == OP.DUPCLOSURE then
				local childId
				if op == OP.NEWCLOSURE then
					childId = p.p[ins.d]
				else
					local k = K[ins.d]
					childId = k and k.t == "closure" and k.v
				end
				local child = childId and chunk.protos[childId]
				if not child then
					fail("closure without a function")
				end
				ins.child = childId
				ins.captures = {}
				local cpc = ins.next
				for n = 1, child.nups do
					local cap = byPc[cpc]
					if not cap or cap.op ~= OP.CAPTURE then
						fail("missing CAPTURE")
					end
					cap.consumed = true
					ins.captures[n] = cap
					cpc = cap.next
				end
			end
		end

		local incoming = {}
		for _, ins in insns do
			if ins.target then
				local list = incoming[ins.target]
				if not list then
					list = {}
					incoming[ins.target] = list
				end
				list[#list + 1] = ins
			end
		end

		-- * `x = a == b` is compiled as: JUMPIFEQ a b L; LOADB x 0 +1; L: LOADB x 1
		for _, ins in insns do
			if CONDITIONAL[ins.op] and not ins.absorbed then
				local l1 = byPc[ins.next]
				local l2 = l1 and byPc[l1.next]
				if l1 and l2 and l1.op == OP.LOADB and l1.c == 1 and ins.target == l1.next
					and l2.op == OP.LOADB and l2.c == 0 and l2.a == l1.a and l1.target == l2.next
					and (l1.b ~= 0) ~= (l2.b ~= 0)
					and not incoming[l1.pc] and incoming[l2.pc] and #incoming[l2.pc] == 1
				then
					ins.boolmat = { reg = l1.a, whenJump = l2.b ~= 0 }
					ins.next = l2.next
					l1.absorbed, l2.absorbed = true, true
					incoming[l2.pc] = nil
					local into = incoming[l2.next]
					if into then
						for n = #into, 1, -1 do
							if into[n] == l1 then
								remove(into, n)
							end
						end
						if #into == 0 then
							incoming[l2.next] = nil
						end
					end
				end
			end
		end

		-- * code that can never run (the compiler leaves some, e.g. after `x and true or false`)
		do
			local reached = {}
			local stack = { 0 }
			while #stack > 0 do
				local pc = remove(stack)
				local ins = byPc[pc]
				if ins and not reached[pc] then
					reached[pc] = true
					local op = ins.op
					local function go(t)
						if t and t < size and not reached[t] then
							stack[#stack + 1] = t
						end
					end
					if ins.boolmat then
						go(ins.next)
					elseif UNCONDITIONAL[op] or FORGPREPS[op] or (op == OP.LOADB and ins.c ~= 0) then
						go(ins.target)
					elseif op == OP.RETURN then
						-- * nothing
					else
						go(ins.next)
						go(ins.target)
					end
				end
			end
			for _, ins in insns do
				if not reached[ins.pc] and not ins.absorbed and not ins.consumed then
					ins.unreachable = true
					-- * an unreachable unconditional jump still marks structure (e.g. where an else
					-- * begins) and is never executed, so it stays; other dead code is dropped
					if not UNCONDITIONAL[ins.op] then
						ins.dead = true
					end
				end
			end
			-- * dead instructions do not count as jumps into anything
			for t, list in incoming do
				for n = #list, 1, -1 do
					if list[n].dead then
						remove(list, n)
					end
				end
				if #list == 0 then
					incoming[t] = nil
				end
			end
		end

		-- * the effective instruction sequence (live code only)
		local seq, prevOf = {}, {}
		do
			local pc, prev = 0, nil
			while pc < size do
				local ins = byPc[pc]
				if not ins then
					fail("broken instruction stream")
				end
				if not ins.dead then
					seq[#seq + 1] = ins
					prevOf[pc] = prev
					prev = ins
				end
				pc = ins.next
			end
			-- * `lastBefore(pc)` for a pc after dead code: the last live instruction before it
			local lastLive
			pc = 0
			while pc < size do
				local ins = byPc[pc]
				if ins.dead then
					prevOf[pc] = lastLive
				else
					lastLive = ins
				end
				pc = ins.next
			end
		end
		local function nextLive(pc)
			while pc < size and byPc[pc] and byPc[pc].dead do
				pc = byPc[pc].next
			end
			return pc
		end

		-- * multret pairs: CALL C=0 / GETVARARGS B=0 feeding CALL B=0 / RETURN B=0 / SETLIST C=0
		do
			local producer
			for _, ins in seq do
				local op = ins.op
				local consumes = (op == OP.CALL and ins.b == 0) or (op == OP.RETURN and ins.b == 0) or (op == OP.SETLIST and ins.c == 0)
				if consumes then
					if not producer then
						fail("multret without a producer at " .. ins.pc)
					end
					ins.multretFrom = producer
					producer.multretTo = ins
				end
				if (op == OP.CALL and ins.c == 0) or (op == OP.GETVARARGS and ins.b == 0) then
					producer = ins
				elseif consumes then
					producer = nil
				elseif not NOOPS[op] and op ~= OP.CLOSEUPVALS then
					-- * `f(g())` with a builtin f loads f between g's call and f's call
					-- * `obj:m(g())` with obj not in a local: NAMECALL comes after g's call too
					local loadsBelow = producer and ins.a < producer.a
						and (op == OP.GETIMPORT or op == OP.GETGLOBAL or op == OP.MOVE or op == OP.GETUPVAL
							or (op == OP.NAMECALL and ins.a + 1 < producer.a))
					if not loadsBelow then
						producer = nil
					end
				end
			end
			for _, ins in seq do
				if ((ins.op == OP.CALL and ins.c == 0) or (ins.op == OP.GETVARARGS and ins.b == 0)) and not ins.multretTo then
					fail("unused multret")
				end
			end
		end

		-- * `FASTCALL ...; GETIMPORT f; CALL f`: the function is loaded after the arguments
		for i, ins in seq do
			if ins.op == OP.CALL and i > 2 then
				local before = seq[i - 2]
				if before.op == OP.FASTCALL or before.op == OP.FASTCALL1 or before.op == OP.FASTCALL2
					or before.op == OP.FASTCALL2K or before.op == OP.FASTCALL3
				then
					ins.fnLast = true
				end
			end
		end

		-- * register reads (in the order the compiler emits them) and writes
		local function rangeTo(ins, from)
			if ins.multretFrom then
				return ins.multretFrom.a - 1
			end
			return nil
		end
		for _, ins in seq do
			local op, a, b, c = ins.op, ins.a, ins.b, ins.c
			local uses, defs = {}, {}
			local function use(r)
				uses[#uses + 1] = r
			end
			local function def(r)
				defs[#defs + 1] = r
			end
			if ins.boolmat then
				use(a)
				if TWO_REG_COMPARE[op] then
					use(ins.aux)
				end
				def(ins.boolmat.reg)
			elseif CONDITIONAL[op] then
				use(a)
				if TWO_REG_COMPARE[op] then
					use(ins.aux)
				end
			elseif op == OP.LOADNIL or op == OP.LOADB or op == OP.LOADN or op == OP.LOADK or op == OP.LOADKX
				or op == OP.GETGLOBAL or op == OP.GETUPVAL or op == OP.GETIMPORT or op == OP.NEWTABLE or op == OP.DUPTABLE
			then
				def(a)
			elseif op == OP.MOVE then
				use(b)
				def(a)
			elseif op == OP.SETGLOBAL or op == OP.SETUPVAL then
				use(a)
			elseif op == OP.GETTABLE then
				use(b)
				use(c)
				def(a)
			elseif op == OP.SETTABLE then
				use(b)
				use(c)
				use(a)
			elseif op == OP.GETTABLEKS or op == OP.GETTABLEN then
				use(b)
				def(a)
			elseif op == OP.SETTABLEKS or op == OP.SETTABLEN then
				use(b)
				use(a)
			elseif op == OP.NEWCLOSURE or op == OP.DUPCLOSURE then
				def(a)
				for _, cap in ins.captures do
					if cap.a == 0 or cap.a == 1 then
						use(cap.b)
					end
				end
			elseif op == OP.NAMECALL then
				use(b)
				def(a)
				def(a + 1)
			elseif op == OP.CALL then
				local last = b > 0 and a + b - 1 or rangeTo(ins)
				for r = a, last do
					use(r)
				end
				if c >= 2 then
					for r = a, a + c - 2 do
						def(r)
					end
				end
			elseif op == OP.RETURN then
				local last = b > 0 and a + b - 2 or rangeTo(ins)
				for r = a, last do
					use(r)
				end
			elseif ARITH[op] or op == OP.AND or op == OP.OR then
				use(b)
				use(c)
				def(a)
			elseif ARITHK[op] or op == OP.ANDK or op == OP.ORK or op == OP.NOT or op == OP.MINUS or op == OP.LENGTH then
				use(b)
				def(a)
			elseif op == OP.SUBRK or op == OP.DIVRK then
				use(c)
				def(a)
			elseif op == OP.CONCAT then
				for r = b, c do
					use(r)
				end
				def(a)
			elseif op == OP.SETLIST then
				use(a)
				local last = c > 0 and b + c - 2 or rangeTo(ins)
				for r = b, last do
					use(r)
				end
			elseif op == OP.GETVARARGS then
				if b >= 2 then
					for r = a, a + b - 2 do
						def(r)
					end
				end
			elseif op == OP.FORNPREP then
				use(a + 2)
				use(a)
				use(a + 1)
			elseif FORGPREPS[op] then
				use(a)
				use(a + 1)
				use(a + 2)
			elseif op == OP.CAPTURE or op == OP.CLOSEUPVALS or UNCONDITIONAL[op] or NOOPS[op] or op == OP.FORNLOOP or op == OP.FORGLOOP then
				-- * loop instructions are modelled below
			else
				fail("unsupported opcode " .. tostring(Lifter.OP_NAMES[op] or op))
			end
			ins.uses, ins.defs = uses, defs
		end

		-- * basic blocks
		local leaders = { [0] = true }
		local function isTerminator(ins)
			local op = ins.op
			if ins.boolmat then
				return false
			end
			return CONDITIONAL[op] or UNCONDITIONAL[op] or op == OP.RETURN or op == OP.FORNPREP or op == OP.FORNLOOP
				or FORGPREPS[op] or op == OP.FORGLOOP or (op == OP.LOADB and ins.c ~= 0)
		end
		for _, ins in seq do
			if isTerminator(ins) then
				if ins.target then
					leaders[ins.target] = true
				end
				if ins.next < size then
					leaders[ins.next] = true
				end
			end
		end
		local blocks, blockAt = {}, {}
		for _, ins in seq do
			if leaders[ins.pc] then
				local block = { id = #blocks + 1, start = ins.pc, insns = {}, succ = {}, pred = {} }
				blocks[#blocks + 1] = block
				blockAt[ins.pc] = block
			end
			local block = blocks[#blocks]
			block.insns[#block.insns + 1] = ins
			ins.block = block
		end
		for _, block in blocks do
			local last = block.insns[#block.insns]
			local op = last.op
			local targets = {}
			if last.boolmat or not isTerminator(last) then
				targets = { last.next }
			elseif CONDITIONAL[op] or op == OP.FORNPREP or op == OP.FORNLOOP or op == OP.FORGLOOP then
				targets = { last.target, last.next }
			elseif UNCONDITIONAL[op] or FORGPREPS[op] or op == OP.LOADB then
				targets = { last.target }
			end
			for _, t in targets do
				local succ = blockAt[t]
				if succ then
					block.succ[#block.succ + 1] = succ
					succ.pred[#succ.pred + 1] = block
				end
			end
		end

		-- * definitions
		local parent = {}
		local defInfo = {}
		local function newDef(kind, ins, reg)
			local id = #defInfo + 1
			defInfo[id] = { kind = kind, ins = ins, reg = reg }
			parent[id] = id
			return id
		end
		local function find(x)
			while parent[x] ~= x do
				parent[x] = parent[parent[x]]
				x = parent[x]
			end
			return x
		end
		local function union(x, y)
			x, y = find(x), find(y)
			if x ~= y then
				parent[y] = x
			end
		end

		local paramDefs = {}
		for r = 0, p.numparams - 1 do
			paramDefs[r] = newDef("param", nil, r)
		end
		local prepOfBody = {}
		for _, ins in seq do
			ins.defIds = {}
			for _, r in ins.defs do
				ins.defIds[r] = newDef("normal", ins, r)
			end
			if ins.op == OP.FORNPREP then
				ins.lvDef = newDef("loopvar", ins, ins.a + 2)
				ins.defIds[ins.a + 2] = ins.lvDef
				ins.defIds[ins.a] = newDef("hidden", ins, ins.a)
				ins.defIds[ins.a + 1] = newDef("hidden", ins, ins.a + 1)
				prepOfBody[ins.next] = ins
			elseif FORGPREPS[ins.op] then
				for r = ins.a, ins.a + 2 do
					ins.defIds[r] = newDef("hidden", ins, r)
				end
			end
		end
		for _, ins in seq do
			if ins.op == OP.FORNLOOP then
				local prep = prepOfBody[ins.target]
				if not prep or prep.a ~= ins.a then
					fail("FORNLOOP without its FORNPREP")
				end
				ins.defIds[ins.a + 2] = prep.lvDef
				ins.defIds[ins.a] = newDef("hidden", ins, ins.a)
				ins.defIds[ins.a + 1] = newDef("hidden", ins, ins.a + 1)
			elseif ins.op == OP.FORGLOOP then
				local count = band(ins.aux, 255)
				ins.lvDefs = {}
				for n = 1, count do
					local r = ins.a + 2 + n
					ins.lvDefs[n] = newDef("loopvar", ins, r)
					ins.defIds[r] = ins.lvDefs[n]
				end
				if not ins.defIds[ins.a + 2] then
					ins.defIds[ins.a + 2] = newDef("hidden", ins, ins.a + 2)
				end
			end
		end

		-- * reaching definitions per block: OUT[reg] = last def in block, or IN[reg]
		local gen = {}
		for _, block in blocks do
			local g = {}
			for _, ins in block.insns do
				for r, id in ins.defIds do
					g[r] = id
				end
			end
			gen[block] = g
		end
		local IN, OUT = {}, {}
		for _, block in blocks do
			IN[block], OUT[block] = {}, {}
		end
		do
			local entry = blocks[1]
			for r, id in paramDefs do
				IN[entry][r] = { [id] = true }
			end
			local work, queued = {}, {}
			for _, block in blocks do
				work[#work + 1] = block
				queued[block] = true
			end
			while #work > 0 do
				local block = remove(work)
				queued[block] = nil
				-- * the entry block can be a loop header too: parameters AND its predecessors
				local inSet = {}
				if block == entry then
					for r, id in paramDefs do
						inSet[r] = { [id] = true }
					end
				end
				do
					for _, pred in block.pred do
						for r, set in OUT[pred] do
							local mine = inSet[r]
							if not mine then
								mine = {}
								inSet[r] = mine
							end
							for id in set do
								mine[id] = true
							end
						end
					end
					IN[block] = inSet
				end
				local out = {}
				for r, set in inSet do
					out[r] = set
				end
				for r, id in gen[block] do
					out[r] = { [id] = true }
				end
				local changed = false
				local old = OUT[block]
				for r, set in out do
					local o = old[r]
					if not o then
						changed = true
						break
					end
					for id in set do
						if not o[id] then
							changed = true
							break
						end
					end
					if changed then
						break
					end
				end
				if changed then
					OUT[block] = out
					for _, succ in block.succ do
						if not queued[succ] then
							queued[succ] = true
							work[#work + 1] = succ
						end
					end
				end
			end
		end

		-- * resolve every read to the definitions that reach it
		local uses = {} -- list of { ins, reg, def }
		for _, block in blocks do
			local cur = {}
			for r, set in IN[block] do
				cur[r] = set
			end
			for _, ins in block.insns do
				ins.useDef = {}
				local function resolveUses()
					for _, r in ins.uses do
						if ins.useDef[r] ~= nil then
							ins.readsTwice = ins.readsTwice or {}
							ins.readsTwice[r] = true
						end
						if ins.useDef[r] == nil then
							local set = cur[r]
							local first
							if set then
								for id in set do
									if first then
										union(first, id)
									else
										first = id
									end
								end
							end
							if not first then
								first = newDef("undefined", ins, r)
							end
							ins.useDef[r] = first
							uses[#uses + 1] = { ins = ins, reg = r, def = first }
						end
					end
				end
				local function applyDefs()
					for r, id in ins.defIds do
						cur[r] = { [id] = true }
					end
				end
				if ins.op == OP.NEWCLOSURE or ins.op == OP.DUPCLOSURE then
					applyDefs()
					resolveUses()
				else
					resolveUses()
					applyDefs()
				end
			end
		end

		-- * a register captured by reference is ONE variable from the capture until CLOSEUPVALS:
		-- * every write and read of it in that window belongs to the same variable
		local openIn = {}
		do
			local function transfer(state, ins, onTouch)
				if onTouch then
					for _, r in ins.uses do
						local open = state[r]
						if open then
							for cid in open do
								onTouch(ins.useDef[r], cid)
							end
						end
					end
					for r, id in ins.defIds do
						local open = state[r]
						if open then
							for cid in open do
								onTouch(id, cid)
							end
						end
					end
				end
				if ins.op == OP.NEWCLOSURE or ins.op == OP.DUPCLOSURE then
					for _, cap in ins.captures do
						if cap.a == 1 then
							local r = cap.b
							local set = {}
							if state[r] then
								for cid in state[r] do
									set[cid] = true
								end
							end
							set[ins.useDef[r]] = true
							state[r] = set
						end
					end
				elseif ins.op == OP.CLOSEUPVALS then
					for r in state do
						if r >= ins.a then
							state[r] = nil
						end
					end
				end
			end
			local outState = {}
			local work, queued = {}, {}
			for _, block in blocks do
				work[#work + 1] = block
				queued[block] = true
				outState[block] = {}
			end
			while #work > 0 do
				local block = remove(work, 1)
				queued[block] = nil
				local state = {}
				for _, pred in block.pred do
					for r, set in outState[pred] do
						local mine = state[r]
						if not mine then
							mine = {}
							state[r] = mine
						end
						for cid in set do
							mine[cid] = true
						end
					end
				end
				local snapshot = {}
				for r, set in state do
					local copy = {}
					for cid in set do
						copy[cid] = true
					end
					snapshot[r] = copy
				end
				openIn[block] = snapshot
				for _, ins in block.insns do
					transfer(state, ins)
				end
				local old = outState[block]
				local changed = false
				for r, set in state do
					for cid in set do
						if not (old[r] and old[r][cid]) then
							changed = true
						end
					end
				end
				if changed then
					outState[block] = state
					for _, succ in block.succ do
						if not queued[succ] then
							queued[succ] = true
							work[#work + 1] = succ
						end
					end
				end
			end
			for _, block in blocks do
				local state = {}
				for r, set in openIn[block] do
					local copy = {}
					for cid in set do
						copy[cid] = true
					end
					state[r] = copy
				end
				for _, ins in block.insns do
					transfer(state, ins, union)
				end
			end
		end

		-- * webs (= variables)
		local webs = {}
		local function web(id)
			local root = find(id)
			local w = webs[root]
			if not w then
				w = { id = root, defs = {}, uses = {}, captured = false, kinds = {} }
				webs[root] = w
			end
			return w
		end
		for id, info in defInfo do
			local w = web(id)
			w.defs[#w.defs + 1] = id
			w.kinds[info.kind] = true
		end
		for _, u in uses do
			local w = web(u.def)
			w.uses[#w.uses + 1] = u
			if (u.ins.op == OP.NEWCLOSURE or u.ins.op == OP.DUPCLOSURE) then
				w.captured = true
			end
		end
		local function webOf(id)
			return webs[find(id)]
		end

		-- * a temporary: written once, read once, in the same block, never captured
		for _, w in webs do
			local onlyDef = #w.defs == 1 and defInfo[w.defs[1]]
			local tempish = onlyDef and onlyDef.kind == "normal" and not w.captured and #w.uses >= 1
			if tempish then
				for _, u in w.uses do
					if u.ins.block ~= onlyDef.ins.block or u.ins.index <= onlyDef.ins.index then
						tempish = false
					end
					if u.ins.readsTwice and u.ins.readsTwice[u.reg] then
						tempish = false
					end
				end
			end
			w.tempish = tempish
			w.temp = tempish and #w.uses == 1
			w.useLeft = #w.uses
		end

		-- * liveness of variables at block entries (for hoisting declarations out of loops)
		local liveIn = {}
		do
			local useB, defB = {}, {}
			for _, block in blocks do
				local u, d = {}, {}
				for _, ins in block.insns do
					local function doUses()
						for _, r in ins.uses do
							local w = webOf(ins.useDef[r])
							if not d[w] then
								u[w] = true
							end
						end
					end
					local function doDefs()
						for _, id in ins.defIds do
							d[webOf(id)] = true
						end
					end
					if ins.op == OP.NEWCLOSURE or ins.op == OP.DUPCLOSURE then
						doDefs()
						doUses()
					else
						doUses()
						doDefs()
					end
				end
				useB[block], defB[block] = u, d
				liveIn[block] = {}
			end
			local changed = true
			while changed do
				changed = false
				for n = #blocks, 1, -1 do
					local block = blocks[n]
					local live = {}
					for _, succ in block.succ do
						for w in liveIn[succ] do
							live[w] = true
						end
					end
					for w in defB[block] do
						live[w] = nil
					end
					for w in useB[block] do
						live[w] = true
					end
					local old = liveIn[block]
					for w in live do
						if not old[w] then
							changed = true
							break
						end
					end
					liveIn[block] = live
				end
			end
		end

		local openWebsAt = {}
		for _, block in blocks do
			local set = {}
			for _, cids in openIn[block] do
				for cid in cids do
					set[webOf(cid)] = true
				end
			end
			openWebsAt[block.start] = set
		end

		local backSources = {}
		for _, ins in seq do
			ins.nextLive = nextLive(ins.next)
			if ins.target and ins.target <= ins.pc and (UNCONDITIONAL[ins.op] or CONDITIONAL[ins.op]) and not ins.boolmat then
				local list = backSources[ins.target]
				if not list then
					list = {}
					backSources[ins.target] = list
				end
				list[#list + 1] = ins
			end
		end

		return {
			p = p, K = K, seq = seq, byPc = byPc, prevOf = prevOf, incoming = incoming, blocks = blocks,
			blockAt = blockAt, webOf = webOf, webs = webs, defInfo = defInfo, liveIn = liveIn,
			openWebsAt = openWebsAt, backSources = backSources, paramDefs = paramDefs,
		}
	end

	--------------------------------------------------------------------------
	-- structuring
	--------------------------------------------------------------------------
	local function structure(A)
		local byPc, seq = A.byPc, A.seq
		local size = A.p.sizecode

		local function insAt(pc)
			return byPc[pc]
		end
		local function lastBefore(pc)
			return A.prevOf[pc]
		end

		-- * jumps into `pc` from anywhere except the listed instructions
		local function externalIncoming(pc, allowed)
			local list = A.incoming[pc]
			if not list then
				return false
			end
			for _, ins in list do
				if not allowed[ins] then
					return true
				end
			end
			return false
		end

		-- * an instruction whose only effect is a temporary that is read inside [from, to]
		local function isTempDef(ins, from, to)
			if NOOPS[ins.op] then
				return true -- * FASTCALL hints have no effect of their own
			end
			if (ins.op == OP.CALL and ins.c == 0) or (ins.op == OP.GETVARARGS and ins.b == 0) then
				-- * a multret value consumed in the same range
				return ins.multretTo ~= nil and ins.multretTo.pc >= from and ins.multretTo.pc <= to
			end
			if ins.boolmat or ins.target or #ins.defs == 0 then
				return false
			end
			if ins.op == OP.CALL and ins.c ~= 2 then
				return false
			end
			for r, id in ins.defIds do
				local w = A.webOf(id)
				if not w.temp then
					return false
				end
				local u = w.uses[1].ins
				if u.pc < from or u.pc > to then
					return false
				end
			end
			return true
		end

		local structRange

		-- * jumping to an unconditional jump is the same as jumping to where it goes (the compiler
		-- * threads jumps: a loop followed by `JUMP x` may exit straight to x)
		-- * a loop instruction jumps back to the first instruction of the body, or, when the body
		-- * is nothing but a jump to the loop instruction (`continue`), the compiler threads that
		-- * jump and the loop instruction jumps to itself
		local loopBacksTo
		local function canonical(pc)
			for _ = 1, 16 do
				local ins = insAt(pc)
				if ins and UNCONDITIONAL[ins.op] then
					pc = ins.target
				else
					break
				end
			end
			return pc
		end
		function loopBacksTo(loopIns, bodyStart)
			if loopIns.target == bodyStart then
				return true
			end
			return loopIns.target == loopIns.pc and canonical(bodyStart) == loopIns.pc
		end

		-- * a chain of conditional jumps forming one and/or condition
		local function buildChains(first, e, preFirst)
			local segs = { { pre = preFirst or {}, jump = first, start = (preFirst and preFirst[1] and preFirst[1].pc) or first.pc } }
			local candidates = {}
			local function consistent()
				local n = #segs
				local tthen, telse = segs[n].jump.next, segs[n].jump.target
				local starts = {}
				for k = 2, n do
					starts[segs[k].start] = k
				end
				for i = 1, n - 1 do
					local t = segs[i].jump.target
					local k = starts[t]
					if not (t == tthen or t == telse or (k and k > i)) then
						return false
					end
				end
				-- * nothing outside the chain may jump into its later segments
				local chainJumps = {}
				for k = 1, n do
					chainJumps[segs[k].jump] = true
				end
				for k = 2, n do
					if externalIncoming(segs[k].start, chainJumps) then
						return false
					end
					for _, ins in segs[k].pre do
						if ins.pc ~= segs[k].start and externalIncoming(ins.pc, {}) then
							return false
						end
					end
					if segs[k].jump.pc ~= segs[k].start and externalIncoming(segs[k].jump.pc, {}) then
						return false
					end
				end
				return true
			end
			if consistent() then
				candidates[#candidates + 1] = #segs
			end
			for _ = 1, 64 do
				local last = segs[#segs].jump
				local pc = last.next
				local startPc = pc
				local pre = {}
				local ins = insAt(pc)
				while ins and pc < e and not CONDITIONAL[ins.op] and isTempDef(ins, startPc, size) do
					pre[#pre + 1] = ins
					pc = ins.next
					ins = insAt(pc)
				end
				if not ins or pc >= e or not CONDITIONAL[ins.op] or ins.boolmat or A.backSources[startPc] then
					break
				end
				for _, p in pre do
					for _, id in p.defIds do
						local u = A.webOf(id).uses[1].ins
						if u.pc < startPc or u.pc > ins.pc then
							return candidates, segs
						end
					end
				end
				segs[#segs + 1] = { pre = pre, jump = ins, start = startPc }
				if consistent() then
					candidates[#candidates + 1] = #segs
				end
			end
			return candidates, segs
		end

		-- * condition tree for "execution reaches tthen" of segs[1..n]
		local function chainCondition(segs, n)
			local tthen, telse = segs[n].jump.next, segs[n].jump.target
			local f = {}
			f[n + 1] = TRUE
			local startIndex = {}
			for k = 2, n do
				startIndex[segs[k].start] = k
			end
			for i = n, 1, -1 do
				local leaf = E("cond", { seg = segs[i] })
				local t = segs[i].jump.target
				local nextF = f[i + 1]
				local function andF(x, y)
					if y == TRUE then
						return x
					end
					return E("and", { l = x, r = y })
				end
				if t == tthen and t == telse then
					f[i] = E("or", { l = leaf, r = nextF }) -- * degenerate, keeps the evaluation
				elseif t == tthen then
					f[i] = nextF == TRUE and E("or", { l = leaf, r = TRUE }) or E("or", { l = leaf, r = nextF })
				elseif t == telse then
					f[i] = andF(E("not", { e = leaf }), nextF)
				else
					local k = startIndex[t]
					local fk = f[k]
					local andHead = splitTail(nextF, "and", fk)
					local orHead = not andHead and splitTail(nextF, "or", fk)
					if andHead then
						f[i] = E("and", { l = E("or", { l = leaf, r = andHead }), r = fk })
					elseif orHead then
						f[i] = E("or", { l = E("and", { l = E("not", { e = leaf }), r = orHead }), r = fk })
					else
						return nil
					end
				end
			end
			return f[1]
		end

		local function loopTargets(ctx, target)
			-- * jumping to `return` (with no values) is the same as returning right there
			local final = insAt(canonical(target))
			if final and final.op == OP.RETURN and final.b == 1 then
				return "return"
			end
			local loop = ctx.loop
			if not loop then
				return nil
			end
			local t = canonical(target)
			if target == loop.exit or t == canonical(loop.exit) then
				return "break"
			end
			if loop.tailExit and (target == loop.tailExit or t == canonical(loop.tailExit)) then
				return "break"
			end
			for c in loop.conts do
				if target == c or t == canonical(c) then
					return "continue"
				end
			end
			return nil
		end

		-- * try one chain length; returns the node and the pc to continue at
		local function tryIf(segs, n, e, ctx)
			local cond = chainCondition(segs, n)
			if not cond then
				return nil
			end
			local last = segs[n].jump
			local tthen, telse = last.next, last.target
			-- * threaded jump past the end of the enclosing range: same as jumping to its end
			if telse > e and canonical(e) == canonical(telse) then
				telse = e
			end
			local chain = { segs = { table.unpack(segs, 1, n) }, cond = cond }
			if telse == tthen then
				-- * `if c then continue end` as the last statement of a loop body: the compiler jumps
				-- * straight to the next iteration, which is also the next instruction (an empty `if`
				-- * would test the opposite condition)
				if not A.conservative and n == 1 and loopTargets(ctx, telse) == "continue" then
					A.info.usedNew = true
					local taken = E("cond", { seg = segs[1] })
					return { kind = "condjump", chain = { segs = { segs[1] }, cond = E("not", { e = taken }) }, action = "continue" }, tthen
				end
				return { kind = "if", chain = chain, thenB = { items = {} }, degenerate = true }, tthen
			end
			if telse > tthen and telse <= e then
				local lastThen = lastBefore(telse)
				if lastThen and lastThen.pc >= tthen and UNCONDITIONAL[lastThen.op] and lastThen.op ~= OP.JUMPBACK then
					-- * `if c then ... continue end` compiles exactly like `if c then ... else <rest of the
					-- * loop body> end`; the line info tells them apart: a `continue` is a statement of its
					-- * own, on a later line than the code before it
					local lineOf = A.p.lineOf
					local before = lastBefore(lastThen.pc)
					if not A.conservative and lineOf and before and before.pc >= tthen and loopTargets(ctx, lastThen.target) == "continue"
						and (lineOf(lastThen.pc) or 0) > (lineOf(before.pc) or math.huge)
					then
						local ok1, thenB = pcall(structRange, tthen, lastThen.pc, ctx)
						if ok1 then
							A.info.usedNew = true
							local thenItems = table.move(thenB.items, 1, #thenB.items, 1, {})
							thenItems[#thenItems + 1] = { kind = "continue" }
							return { kind = "if", chain = chain, thenB = { items = thenItems } }, telse
						end
					end
					local E2 = lastThen.target
					if E2 > e and canonical(e) == canonical(E2) then
						E2 = e
					end
					if E2 > telse and E2 <= e then
						local ok1, thenB = pcall(structRange, tthen, lastThen.pc, ctx)
						local ok2, elseB
						if ok1 then
							ok2, elseB = pcall(structRange, telse, E2, ctx)
						end
						if ok1 and ok2 then
							return { kind = "if", chain = chain, thenB = thenB, elseB = elseB }, E2
						end
						-- * the jump may instead be a break / continue / return with no else
						if not loopTargets(ctx, E2) then
							return nil, ok1 and elseB or thenB
						end
					elseif not loopTargets(ctx, E2) then
						return nil, "jump out of an if"
					end
				end
				local ok, thenB = pcall(structRange, tthen, telse, ctx)
				if not ok then
					return nil, thenB
				end
				return { kind = "if", chain = chain, thenB = thenB }, telse
			end
			local action = loopTargets(ctx, telse)
			if action then
				return { kind = "condjump", chain = chain, action = action }, tthen
			end
			return nil, "conditional jump to " .. telse .. " cannot be structured"
		end

		-- * `x = a and b or c` and friends: conditional jumps plus value "leaves" that all write one
		-- * register R, ending at one join point. Rebuilt as an and/or expression (or `if c then a
		-- * else b` when allowCond), only when every test and leaf is used exactly once.
		local function tryValueExpr(first, e, items, allowCond)
			local elements = {}
			local R
			local pc = first.pc
			local Jn = first.target
			local positions = {}
			local regionJumps = {}
			local guard = 0
			while pc < Jn do
				guard += 1
				if guard > 256 then
					return nil
				end
				local ins = insAt(pc)
				if not ins or pc >= e then
					return nil
				end
				if CONDITIONAL[ins.op] and not ins.boolmat then
					if ins.target <= ins.pc or ins.target > e then
						return nil
					end
					positions[pc] = #elements + 1
					elements[#elements + 1] = { kind = "test", seg = { pre = {}, jump = ins }, startPc = pc }
					regionJumps[ins] = true
					if ins.target > Jn then
						Jn = ins.target
					end
					pc = ins.next
				else
					local startPc = pc
					local run = {}
					while ins and pc < e and pc < Jn and not (CONDITIONAL[ins.op] and not ins.boolmat) and (pc == startPc or not A.incoming[pc]) do
						local multretOk = ((ins.op == OP.CALL and ins.c == 0) or (ins.op == OP.GETVARARGS and ins.b == 0))
						if (ins.target and not ins.boolmat) or (#ins.defs == 0 and not NOOPS[ins.op] and not multretOk) then
							return nil
						end
						run[#run + 1] = ins
						pc = ins.next
						ins = insAt(pc)
					end
					if #run == 0 then
						return nil
					end
					-- * split off trailing setup for the next test (temporaries it reads)
					local preStart = #run + 1
					local nextIsTest = ins and CONDITIONAL[ins.op] and not ins.boolmat and pc < Jn and not A.incoming[pc]
					if nextIsTest then
						while preStart > 1 and isTempDef(run[preStart - 1], run[preStart - 1].pc, ins.pc) do
							preStart -= 1
						end
					end
					local isPre = nextIsTest and preStart == 1
					if nextIsTest and preStart > 1 and preStart <= #run then
						-- * value first, then the test's setup
						local valueRun = { table.unpack(run, 1, preStart - 1) }
						local preRun = { table.unpack(run, preStart) }
						local lastValue = valueRun[#valueRun]
						if #lastValue.defs ~= 1 then
							return nil
						end
						local reg = lastValue.defs[1]
						if R and R ~= reg then
							return nil
						end
						R = reg
						for n2 = 1, #valueRun - 1 do
							if not isTempDef(valueRun[n2], startPc, lastValue.pc) then
								return nil
							end
						end
						positions[startPc] = #elements + 1
						elements[#elements + 1] = { kind = "leaf", run = valueRun, startPc = startPc }
						if ins.target <= ins.pc or ins.target > e then
							return nil
						end
						local preStartPc = preRun[1].pc
						positions[preStartPc] = #elements + 1
						elements[#elements + 1] = { kind = "test", seg = { pre = preRun, jump = ins }, startPc = preStartPc }
						regionJumps[ins] = true
						if ins.target > Jn then
							Jn = ins.target
						end
						pc = ins.next
					elseif isPre then
						if ins.target <= ins.pc or ins.target > e then
							return nil
						end
						positions[startPc] = #elements + 1
						elements[#elements + 1] = { kind = "test", seg = { pre = run, jump = ins }, startPc = startPc }
						regionJumps[ins] = true
						if ins.target > Jn then
							Jn = ins.target
						end
						pc = ins.next
					else
						local lastRun = run[#run]
						if #lastRun.defs ~= 1 then
							return nil
						end
						local reg = lastRun.defs[1]
						if R and R ~= reg then
							return nil
						end
						R = reg
						for n = 1, #run - 1 do
							if not isTempDef(run[n], startPc, lastRun.pc) then
								return nil
							end
						end
						positions[startPc] = #elements + 1
						elements[#elements + 1] = { kind = "leaf", run = run, startPc = startPc }
					end
				end
			end
			if pc ~= Jn or #elements < 2 or not R or elements[#elements].kind ~= "leaf" then
				return nil
			end
			for _, el in elements do
				if el.kind == "test" then
					local j = el.seg.jump
					if (j.op == OP.JUMPIF or j.op == OP.JUMPIFNOT) and j.a == R then
						if #el.seg.pre > 0 then
							return nil
						end
						el.rtest = j.op == OP.JUMPIF and "truthy" or "falsy"
					end
					if j.target ~= Jn and not positions[j.target] then
						return nil
					end
				end
				if el.startPc ~= first.pc and externalIncoming(el.startPc, regionJumps) then
					return nil
				end
			end

			-- * the value tree, built backwards from the join point
			local CUR = { k = "cur" }
			local FIELDS = { "l", "r", "a", "b", "c" }
			local function countCur(t)
				if t == CUR then
					return 1
				end
				local n = 0
				for _, f in FIELDS do
					if t[f] then
						n += countCur(t[f])
					end
				end
				return n
			end
			local function subst(t, leaf)
				if t == CUR then
					return leaf
				end
				if countCur(t) == 0 then
					return t -- * keep shared subtrees shared
				end
				local copy = table.clone(t)
				for _, f in FIELDS do
					if t[f] then
						copy[f] = subst(t[f], leaf)
					end
				end
				return copy
			end
			local F = {}
			local m = #elements
			F[m + 1] = CUR
			local hasCond = false
			-- * `x = c and v` compiled as `x = false; if c then x = v end`. The constant may sit before
			-- * the first test's own setup code (it has no side effects, so that is fine).
			local falseIndex = #items
			while falseIndex >= 1 and items[falseIndex].kind == "ins" and isTempDef(items[falseIndex].ins, items[falseIndex].ins.pc, first.pc) do
				falseIndex -= 1
			end
			local prevItem = items[falseIndex]
			local startsFalse = prevItem and prevItem.kind == "ins" and prevItem.ins.op == OP.LOADB and prevItem.ins.b == 0
				and prevItem.ins.c == 0 and prevItem.ins.a == R
			local startsTrue = not A.conservative and prevItem and prevItem.kind == "ins" and prevItem.ins.op == OP.LOADB and prevItem.ins.b == 1
				and prevItem.ins.c == 0 and prevItem.ins.a == R
			local usedFalse = false
			-- * a comparison is `true` when its jump is taken; a truthiness test is not
			local function isCompareTest(el)
				local op = el.seg.jump.op
				return op ~= OP.JUMPIF and op ~= OP.JUMPIFNOT
			end
			for k = m, 1, -1 do
				local el = elements[k]
				if el.kind == "leaf" then
					if countCur(F[k + 1]) ~= 1 then
						return nil
					end
					F[k] = subst(F[k + 1], { k = "leaf", el = el })
				else
					local t = el.seg.jump.target
					local Ft = t == Jn and CUR or F[positions[t]]
					local Fn = F[k + 1]
					if el.rtest then
						if Ft == CUR then
							if countCur(Fn) ~= 0 then
								return nil
							end
							F[k] = { k = el.rtest == "truthy" and "or" or "and", l = CUR, r = Fn, el = el }
						elseif el.rtest == "truthy" and splitTail(Fn, "and", Ft) then
							F[k] = { k = "and", l = { k = "or", l = CUR, r = splitTail(Fn, "and", Ft), el = el }, r = Ft, el = Fn.el }
						elseif el.rtest == "falsy" and splitTail(Fn, "or", Ft) then
							F[k] = { k = "or", l = { k = "and", l = CUR, r = splitTail(Fn, "or", Ft), el = el }, r = Ft, el = Fn.el }
						else
							return nil
						end
					elseif Ft == CUR and startsFalse and countCur(Fn) == 0 then
						F[k] = { k = "and", l = { k = "fall", el = el }, r = Fn }
						usedFalse = true
					elseif Ft == CUR and startsTrue and countCur(Fn) == 0 and isCompareTest(el) then
						A.info.usedNew = true
						F[k] = { k = "or", l = { k = "taken", el = el }, r = Fn }
						usedFalse = true
					elseif Ft ~= CUR and splitTail(Fn, "or", Ft) then
						-- * c' ? (X or W) : W  ==  (c' and X) or W
						F[k] = { k = "or", l = { k = "and", l = { k = "fallc", el = el }, r = splitTail(Fn, "or", Ft) }, r = Ft, el = Fn.el }
					else
						F[k] = { k = "cond", c = { k = "taken", el = el }, a = Ft, b = Fn }
						hasCond = true
					end
				end
			end
			local tree = F[1]
			local seen, dup = {}, false
			local function walk(t)
				if t.el then
					if seen[t.el] then
						dup = true
					end
					seen[t.el] = true
				end
				for _, f in FIELDS do
					if t[f] then
						walk(t[f])
					end
				end
			end
			walk(tree)
			if dup then
				return nil
			end
			for _, el in elements do
				if not seen[el] then
					return nil
				end
			end
			-- * c ? false : x  is  (not c) and x  -- not a real if-expression
			local realCond = false
			local function isFalseLeaf(t)
				return t.k == "leaf" and #t.el.run == 1 and t.el.run[1].op == OP.LOADB and t.el.run[1].b == 0 and t.el.run[1].c == 0
			end
			local function isTrueLeaf(t)
				return t.k == "leaf" and #t.el.run == 1 and t.el.run[1].op == OP.LOADB and t.el.run[1].b == 1 and t.el.run[1].c == 0
			end
			local function scanCond(t)
				if not A.conservative and t.k == "cond" and isTrueLeaf(t.a) and t.c.k == "taken" and isCompareTest(t.c.el) then
					A.info.usedNew = true
				end
				if t.k == "cond" and not isFalseLeaf(t.a) and not (t.a == CUR and startsFalse)
					and not (not A.conservative and isTrueLeaf(t.a) and t.c.k == "taken" and isCompareTest(t.c.el))
				then
					realCond = true
				end
				for _, f in FIELDS do
					if t[f] and t[f] ~= CUR then
						scanCond(t[f])
					end
				end
			end
			scanCond(tree)
			if realCond and not allowCond then
				return nil
			end
			local leaf0, leaf0Index
			local cur = countCur(tree)
			if cur > 1 then
				return nil
			elseif cur == 1 then
				local prev = items[#items]
				leaf0Index = #items
				if not (prev and prev.kind == "ins" and #prev.ins.defs == 1 and prev.ins.defs[1] == R
					and not (prev.ins.target and not prev.ins.boolmat) and prev.ins.next == first.pc)
				then
					return nil
				end
				leaf0 = prev.ins
			end
			local dropLeaf0 = false
			if cur == 0 and usedFalse then
				leaf0, dropLeaf0, leaf0Index = prevItem.ins, true, falseIndex
			end
			local firstTest = elements[1].kind == "test" and (not leaf0 or dropLeaf0) and elements[1] or nil
			-- * everything the expression is built from, for "is the result only used once, right after?"
			local regionIns = {}
			for _, el in elements do
				for _, i2 in (el.run or el.seg.pre) do
					regionIns[i2] = true
				end
				if el.seg then
					regionIns[el.seg.jump] = true
				end
			end
			if leaf0 then
				regionIns[leaf0] = true
			end
			return { kind = "valexpr", reg = R, tree = tree, cur = CUR, leaf0 = leaf0, leaf0Index = leaf0Index, dropLeaf0 = dropLeaf0, firstTest = firstTest, regionIns = regionIns, join = Jn }, Jn
		end

		-- * Last resort for forward jumps to a common point J (inlined functions' early returns):
		-- * `repeat ... until true` runs once, and `break` jumps to J.
		local function tryBreakBlock(s0, e)
			local targets, list = {}, {}
			local pc = s0
			while pc < e do
				local i = insAt(pc)
				if not i then
					break
				end
				if i.target and not i.boolmat and i.target > s0 and i.target <= e and not targets[i.target] then
					targets[i.target] = true
					list[#list + 1] = i.target
				end
				pc = i.next
			end
			table.sort(list)
			for n, J in list do
				if n > 12 then
					break
				end
				local blockLoop = { header = s0, exit = J, conts = {}, isBlock = true }
				local ok, body = pcall(structRange, s0, J, { loop = blockLoop })
				if ok then
					return { kind = "breakblock", body = body, loop = blockLoop }, J
				end
			end
			return nil
		end

		local function handleIf(first, e, ctx)
			local candidates, segs = buildChains(first, e)
			local lastErr = "no usable condition"
			for c = #candidates, 1, -1 do
				local node, nextPc = tryIf(segs, candidates[c], e, ctx)
				if node then
					return node, nextPc
				end
				lastErr = nextPc or lastErr
			end
			if string.find(tostring(lastErr), FAIL, 1, true) then
				error(lastErr, 0)
			end
			fail(lastErr)
		end

		-- * memo + budget: the fallbacks (shorter chains, break blocks) retry sub-ranges, which
		-- * must not blow up on large functions
		-- * An inlined `for ... do if c then return false end end return true` (-O2): the inlined
		-- * `return false` sets the result and jumps past the `true` that follows the loop. Written
		-- * as `x = true` before the loop and `x = false; break` inside it, which is exact when:
		-- * - the code after the loop up to the jump target only loads constants (no side effects),
		-- * - every jump there writes all those registers first, in straight-line code,
		-- * - nothing else in the loop (or its setup) reads or writes them, and no closure sees them.
		-- * Returns the jump target, the constant loads and where to put them in `items`.
		local CONST_LOADS = { [OP.LOADNIL] = true, [OP.LOADB] = true, [OP.LOADN] = true, [OP.LOADK] = true, [OP.LOADKX] = true }
		local function hoistLoopTail(prep, loopIns, exit, e, items)
			local loads, regs = {}, {}
			local pc = exit
			while pc < e do
				local ins = insAt(pc)
				if not ins or not CONST_LOADS[ins.op] or ins.target or #ins.defs ~= 1 or (pc ~= exit and A.incoming[pc]) then
					break
				end
				loads[#loads + 1] = ins
				regs[ins.defs[1]] = true
				pc = ins.next
			end
			local J = pc
			if #loads == 0 or J > e or not insAt(J) then
				return nil
			end
			for r in regs do
				if r >= prep.a then
					return nil -- * a loop register: the loop itself overwrites it
				end
			end
			for _, ins in loads do
				for _, id in ins.defIds do
					if A.webOf(id).captured then
						return nil
					end
				end
			end
			-- * the jumps out of the loop to J, and what each writes just before jumping
			local jumpBlock = {}
			local found = false
			local cJ = canonical(J)
			local q = prep.next
			while q < loopIns.pc do
				local ins = insAt(q)
				if not ins then
					return nil
				end
				if ins.target and not ins.boolmat and (ins.target == J or (canonical(ins.target) == cJ and ins.target > loopIns.pc)) then
					if not UNCONDITIONAL[ins.op] then
						return nil
					end
					found = true
					local written = {}
					local cur = ins
					while not A.incoming[cur.pc] do
						local prev = lastBefore(cur.pc)
						if not prev or prev.pc < prep.next or prev.target or CONDITIONAL[prev.op] or UNCONDITIONAL[prev.op] or prev.op == OP.RETURN then
							break
						end
						jumpBlock[prev] = true
						for _, r in prev.defs do
							written[r] = true
						end
						cur = prev
					end
					for r in regs do
						if not written[r] then
							return nil
						end
					end
				end
				q = ins.next
			end
			if not found then
				return nil
			end
			-- * nothing else in the loop touches them
			q = prep.next
			while q <= loopIns.pc do
				local ins = insAt(q)
				for _, r in ins.uses do
					if regs[r] then
						return nil
					end
				end
				if not jumpBlock[ins] then
					for _, r in ins.defs do
						if regs[r] then
							return nil
						end
					end
				end
				q = ins.next
			end
			for _, r in prep.uses do
				if regs[r] then
					return nil
				end
			end
			-- * before the loop's setup (the instructions that only fill the loop registers)
			local at = #items + 1
			while at > 1 do
				local item = items[at - 1]
				local setupIns = item.kind == "ins" and item.ins
				if not setupIns or #setupIns.defs == 0 then
					break
				end
				local ok = true
				for _, r in setupIns.defs do
					if r < prep.a or regs[r] then
						ok = false
					end
				end
				for _, r in setupIns.uses do
					if regs[r] then
						ok = false
					end
				end
				if not ok then
					break
				end
				at -= 1
			end
			return J, loads, at
		end
		local function insertLoads(items, loads, at)
			for n, ins in loads do
				table.insert(items, at + n - 1, { kind = "ins", ins = ins })
			end
		end

		local memo = {}
		local budget = 4000
		local rawStructRange
		function structRange(s, e, ctx)
			local loop = ctx.loop
			local key = s .. ":" .. e
			if loop then
				local conts = {}
				for c in loop.conts do
					conts[#conts + 1] = c
				end
				table.sort(conts)
				key ..= ":" .. tostring(loop.exit) .. ":" .. tostring(loop.header) .. ":" .. concat(conts, ",") .. (loop.isBlock and ":b" or "") .. ":" .. tostring(loop.tailExit)
			end
			local hit = memo[key]
			if hit then
				if hit.err then
					error(hit.err, 0)
				end
				return hit.block
			end
			budget -= 1
			if budget < 0 then
				fail("function too complex to structure")
			end
			memo[key] = { err = FAIL .. "range is already being structured" } -- * no retrying itself
			local ok, result = pcall(rawStructRange, s, e, ctx)
			if ok then
				memo[key] = { block = result }
				return result
			end
			memo[key] = { err = result }
			error(result, 0)
		end

		function rawStructRange(s, e, ctx)
			local block = { items = {} }
			local items = block.items
			local pc = s
			while pc < e do
				local ins = insAt(pc)
				if not ins then
					fail("no instruction at " .. pc)
				end
				if ins.dead or (ins.unreachable and UNCONDITIONAL[ins.op]) then
					pc = ins.next
					continue
				end
				-- * while / repeat loop with header here
				local sources = A.backSources[pc]
				local B
				if sources then
					for _, src in sources do
						if src.pc < e and src.pc >= pc and (not B or src.pc > B.pc) then
							B = src
						end
					end
				end
				if B and not (ctx.loop and ctx.loop.conts[pc]) then
					if not UNCONDITIONAL[B.op] then
						fail("conditional backward jump")
					end
					local exit = B.next
					local loop = { header = pc, exit = exit, conts = { [pc] = true, [B.pc] = true }, backPc = B.pc }
					local loopCtx = { loop = loop }
					local node
					-- * `while cond do`: the loop starts with a condition that jumps to the exit
					local pre, scan = {}, pc
					local first = insAt(scan)
					while first and scan < B.pc and not CONDITIONAL[first.op] and isTempDef(first, pc, B.pc) do
						pre[#pre + 1] = first
						scan = first.next
						first = insAt(scan)
					end
					if first and CONDITIONAL[first.op] and not first.boolmat and scan < B.pc then
						local candidates, segs = buildChains(first, B.pc, pre)
						segs[1].start = pc
						for c = #candidates, 1, -1 do
							local n = candidates[c]
							local last = segs[n].jump
							if (last.target == exit or canonical(last.target) == canonical(exit)) and last.next <= B.pc then
								local cond = chainCondition(segs, n)
								if cond then
									local ok, body = pcall(structRange, last.next, B.pc, loopCtx)
									if ok then
										local header = pc
										node = {
											kind = "while", chain = { segs = { table.unpack(segs, 1, n) }, cond = cond }, body = body, loop = loop,
											fullBody = function()
												return structRange(header, B.pc, { loop = loop })
											end,
										}
										break
									end
								end
							end
						end
					end
					if not node then
						local body = structRange(pc, B.pc, { loop = loop, inLoopBody = true })
						node = { kind = "while", body = body, loop = loop }
					end
					items[#items + 1] = node
					pc = exit
				elseif ins.op == OP.FORNPREP then
					local exit = ins.target
					local loopIns = lastBefore(exit)
					if not (loopIns and loopIns.op == OP.FORNLOOP and loopIns.a == ins.a and loopBacksTo(loopIns, ins.next)) then
						-- * a loop followed by `JUMP x` (the end of an if branch): the compiler threads
						-- * the "loop runs zero times" jump straight to x
						loopIns = nil
						local p2 = ins.next
						while p2 < e do
							local i2 = insAt(p2)
							if not i2 then
								break
							end
							if i2.op == OP.FORNLOOP and i2.a == ins.a and loopBacksTo(i2, ins.next) then
								if canonical(i2.next) == canonical(exit) then
									loopIns, exit = i2, i2.next
								end
								break
							end
							p2 = i2.next
						end
					end
					if not loopIns or loopIns.op ~= OP.FORNLOOP or not loopBacksTo(loopIns, ins.next) or loopIns.a ~= ins.a or exit > e then
						fail("malformed numeric for")
					end
					local loop = { header = ins.next, exit = exit, conts = { [loopIns.pc] = true } }
					local ok, body = pcall(structRange, ins.next, loopIns.pc, { loop = loop })
					local J, loads, at
					if not ok then
						J, loads, at = hoistLoopTail(ins, loopIns, exit, e, items)
						if not J then
							error(body, 0)
						end
						loop.tailExit = J
						body = structRange(ins.next, loopIns.pc, { loop = loop })
						insertLoads(items, loads, at)
					end
					items[#items + 1] = { kind = "numfor", prep = ins, loopIns = loopIns, body = body, loop = loop }
					pc = J or exit
				elseif FORGPREPS[ins.op] then
					local loopIns = insAt(ins.target)
					if not loopIns or loopIns.op ~= OP.FORGLOOP or not loopBacksTo(loopIns, ins.next) or loopIns.a ~= ins.a or loopIns.next > e then
						fail("malformed generic for")
					end
					local loop = { header = ins.next, exit = loopIns.next, conts = { [loopIns.pc] = true } }
					local ok, body = pcall(structRange, ins.next, loopIns.pc, { loop = loop })
					local J, loads, at
					if not ok then
						J, loads, at = hoistLoopTail(ins, loopIns, loopIns.next, e, items)
						if not J then
							error(body, 0)
						end
						loop.tailExit = J
						body = structRange(ins.next, loopIns.pc, { loop = loop })
						insertLoads(items, loads, at)
					end
					items[#items + 1] = { kind = "genfor", prep = ins, loopIns = loopIns, body = body, loop = loop }
					pc = J or loopIns.next
				elseif CONDITIONAL[ins.op] and not ins.boolmat then
					-- * prefer `x = a and b or c`, then if statements, then `if c then a else b` values
					local node, nextPc = tryValueExpr(ins, e, items, false)
					if not node then
						local ok, n2, p2 = pcall(handleIf, ins, e, ctx)
						if ok then
							node, nextPc = n2, p2
						else
							node, nextPc = tryValueExpr(ins, e, items, true)
							if not node then
								node, nextPc = tryBreakBlock(ins.pc, e)
							end
							if not node then
								error(n2, 0)
							end
						end
					end
					if node.kind == "valexpr" and node.leaf0 then
						remove(items, node.leaf0Index) -- * its first value is part of the expression
					end
					items[#items + 1] = node
					pc = nextPc
				elseif UNCONDITIONAL[ins.op] and ins.target > ins.pc and (function()
					local q = ins.next
					while q < ins.target do
						local i2 = insAt(q)
						if not i2 or not i2.unreachable then
							return false
						end
						q = i2.next
					end
					return q == ins.target
				end)() then
					pc = ins.target -- * jumps over code that never runs: a no-op
				elseif UNCONDITIONAL[ins.op] then
					local action = loopTargets(ctx, ins.target)
					if not action then
						fail("unstructured jump from " .. ins.pc .. " to " .. ins.target)
					end
					items[#items + 1] = { kind = action }
					pc = ins.next
				elseif ins.op == OP.FORNLOOP or ins.op == OP.FORGLOOP or (ins.op == OP.LOADB and ins.c ~= 0) then
					fail("stray loop/jump instruction")
				else
					items[#items + 1] = { kind = "ins", ins = ins }
					pc = ins.next
				end
			end
			if pc ~= e then
				fail("range overrun")
			end
			return block
		end

		return structRange(0, size, {})
	end

	--------------------------------------------------------------------------
	-- intermediate representation with folded expressions
	--------------------------------------------------------------------------
	local function buildIR(A, ast, ctx)
		local K = A.K
		local webOf = A.webOf
		local materialized = {}

		local function newBlock(parent, loopStmt)
			return { stmts = {}, parent = parent, depth = parent and parent.depth + 1 or 0, loop = loopStmt }
		end

		local function constExpr(k)
			if k.t == "nil" then
				return E("const", { text = "nil" })
			end
			return E("const", { text = Lifter.constText(k), value = k })
		end
		local function K_(i)
			local k = K[i]
			if not k then
				fail("missing constant")
			end
			if k.t == "vector" then
				ctx.globals.Vector3 = true
			end
			return constExpr(k)
		end
		local function Ks(i)
			local k = K[i]
			if not k or k.t ~= "string" then
				fail("expected a string constant")
			end
			return k.v
		end

		local function varExpr(w)
			materialized[w] = true
			w.noFold = true
			return E("var", { w = w })
		end

		-- * Fold operands back into expressions. A temporary is folded only if it is the most recent
		-- * unfolded statement (skipping constants), taking candidates in reverse order of the
		-- * instruction that computed them. That keeps every side effect in its original order,
		-- * whatever order the compiler chose for this construct (built-in calls load the function
		-- * last, method calls compute the arguments before NAMECALL, ...).
		local mentions -- forward

		-- * `local flag = false` (a constant into a new local) can be evaluated earlier without changing
		-- * anything, so a value computed before it may still fold past it, unless it reads that local
		local function isConstLocalStore(st)
			return st.k == "assign" and st.pure and not st.tempWeb and #st.targets == 1 and st.targets[1].k == "var"
				and #st.values == 1 and st.values[1].k == "const"
		end

		-- * a statement folded into the one being built: that one starts on the earliest line
		local function absorbLine(block, st)
			if st and st.line and (not block.absorbedLine or st.line < block.absorbedLine) then
				block.absorbedLine = st.line
			end
		end

		local function takeOperands(block, ins, regs, multret, allowNamed)
			local stmts = block.stmts
			local exprs = {}
			local cands = {}
			local n = #regs + (multret and 1 or 0)
			for i, r in regs do
				local w
				if type(r) == "table" then
					w = webOf(r.ins.useDef[r.reg])
				else
					w = webOf(ins.useDef[r])
				end
				if w.tempish and w.useLeft == 1 and not w.noFold then
					cands[#cands + 1] = { slot = i, w = w, at = A.defInfo[w.defs[1]].ins.index }
				else
					exprs[i] = varExpr(w)
				end
				w.useLeft -= 1
			end
			if multret then
				cands[#cands + 1] = { slot = n, multret = multret, at = multret.index }
			end
			table.sort(cands, function(x, y)
				return x.at > y.at
			end)
			local j = #stmts
			local blocked = false
			for _, cand in cands do
				local found
				if not blocked then
					local k = j
					local skippedStores = nil
					while k >= 1 do
						local st = stmts[k]
						if (cand.multret and st.multretOf == cand.multret) or (cand.w and st.tempWeb == cand.w) then
							if cand.w and st.namedClosure and not allowNamed then
								break
							end
							local readsSkipped = false
							if skippedStores then
								for _, w2 in skippedStores do
									if mentions(st.value, w2) then
										readsSkipped = true
									end
								end
							end
							if not readsSkipped then
								found = k
							end
							break
						end
						if st.pure and st.tempWeb then
							k -= 1
						elseif isConstLocalStore(st) then
							skippedStores = skippedStores or {}
							skippedStores[#skippedStores + 1] = st.targets[1].w
							k -= 1
						else
							break
						end
					end
				end
				if found then
					exprs[cand.slot] = stmts[found].value
					absorbLine(block, stmts[found])
					remove(stmts, found)
					j = found - 1
				else
					blocked = true
					-- * constants can be moved freely
					local moved = false
					if cand.w then
						for k = #stmts, 1, -1 do
							local st = stmts[k]
							if st.tempWeb == cand.w and st.pure then
								exprs[cand.slot] = st.value
								absorbLine(block, st)
								remove(stmts, k)
								if k <= j then
									j -= 1
								end
								moved = true
								break
							end
						end
					end
					if not moved then
						if cand.multret then
							fail("multret value could not be placed")
						end
						exprs[cand.slot] = varExpr(cand.w)
					end
				end
			end
			return exprs
		end

		-- * does the expression read the variable `w` (e.g. `t.self = t`)?
		function mentions(e, w)
			local found = false
			local function visit(x)
				if found or not x then
					return
				end
				if x.k == "var" and x.w == w then
					found = true
					return
				end
				if x.k == "closure" then
					for _, cap in x.caps do
						if type(cap) == "table" and cap.w == w then
							found = true
						end
					end
				end
				for _, f in { "obj", "key", "fn", "l", "r", "e", "c", "a", "b" } do
					if type(x[f]) == "table" then
						visit(x[f])
					end
				end
				for _, list in { x.args, x.list } do
					if list then
						for _, y in list do
							visit(y)
						end
					end
				end
				if x.entries then
					for _, entry in x.entries do
						visit(entry.key)
						visit(entry.value)
					end
				end
			end
			visit(e)
			return found
		end

		local function pushDef(block, ins, reg, value, pure)
			local w = webOf(ins.defIds[reg])
			local st = { k = "assign", targets = { { k = "var", w = w } }, values = { value }, value = value, pure = pure }
			if w.tempish then
				st.tempWeb = w
			else
				materialized[w] = true
			end
			insert(block.stmts, st)
			return st
		end

		local function pushStmt(block, st)
			insert(block.stmts, st)
			return st
		end

		local function condLeaf(block, seg)
			local ins = seg.jump
			local op = ins.op
			local regs = { ins.a }
			if TWO_REG_COMPARE[op] then
				regs[2] = ins.aux
			end
			local ex = takeOperands(block, ins, regs)
			local taken
			if op == OP.JUMPIF then
				taken = ex[1]
			elseif op == OP.JUMPIFNOT then
				taken = E("not", { e = ex[1] })
			elseif TWO_REG_COMPARE[op] then
				local cmp = E("binop", { op = TWO_REG_COMPARE[op], l = ex[1], r = ex[2] })
				taken = NEGATED_COMPARE[op] and E("not", { e = cmp }) or cmp
			else
				local aux = ins.aux
				local value
				if op == OP.JUMPXEQKNIL then
					value = E("const", { text = "nil" })
				elseif op == OP.JUMPXEQKB then
					value = E("const", { text = band(aux, 1) ~= 0 and "true" or "false" })
				else
					value = K_(band(aux, 0xFFFFFF))
				end
				taken = E("binop", { op = band(aux, 0x80000000) ~= 0 and "~=" or "==", l = ex[1], r = value })
			end
			return taken
		end

		local emitIns
		local buildBlock

		-- * condition expression; later segments' setup code must fold away completely
		local function buildCondition(block, chain, loopFirst)
			local function walk(node)
				if node.k == "cond" then
					local seg = node.seg
					local target = block
					local scratch
					if seg ~= chain.segs[1] or loopFirst then
						scratch = newBlock(block)
						scratch.stmts = {}
						for _, ins in seg.pre do
							emitIns(scratch, ins)
						end
						target = scratch
					end
					local taken = condLeaf(target, seg)
					if scratch and #scratch.stmts > 0 then
						fail("condition with side statements")
					end
					return taken
				elseif node.k == "and" or node.k == "or" then
					local l = walk(node.l)
					local r = walk(node.r)
					return E(node.k, { l = l, r = r })
				elseif node.k == "not" then
					return boolNot(walk(node.e))
				elseif node == TRUE or node.k == "const" then
					return node
				end
				fail("bad condition node")
			end
			-- * the tree is built so that a left-to-right walk visits segments in code order
			local cond = walk(chain.cond)
			return cond
		end

		local function simplifyCond(e)
			if e.k == "not" then
				return boolNot(simplifyCond(e.e))
			elseif e.k == "and" or e.k == "or" then
				return E(e.k, { l = simplifyCond(e.l), r = simplifyCond(e.r) })
			end
			return e
		end

		function emitIns(block, ins)
			local op, a, b, c = ins.op, ins.a, ins.b, ins.c
			if NOOPS[op] or op == OP.CAPTURE or op == OP.CLOSEUPVALS then
				return
			end
			if ins.boolmat then
				local seg = { jump = ins }
				local taken = condLeaf(block, seg)
				local value
				local isBool = not (op == OP.JUMPIF or op == OP.JUMPIFNOT)
				if ins.boolmat.whenJump then
					value = isBool and taken or E("not", { e = E("not", { e = taken }) })
				else
					value = E("not", { e = taken })
				end
				pushDef(block, ins, ins.boolmat.reg, value, false)
				return
			end
			if op == OP.LOADNIL then
				pushDef(block, ins, a, E("const", { text = "nil" }), true)
			elseif op == OP.LOADB then
				pushDef(block, ins, a, E("const", { text = b ~= 0 and "true" or "false" }), true)
			elseif op == OP.LOADN then
				pushDef(block, ins, a, E("const", { text = numLit(ins.d) }), true)
			elseif op == OP.LOADK then
				pushDef(block, ins, a, K_(ins.d), true)
			elseif op == OP.LOADKX then
				pushDef(block, ins, a, K_(ins.aux), true)
			elseif op == OP.MOVE then
				local ex = takeOperands(block, ins, { b })
				pushDef(block, ins, a, ex[1], false)
			elseif op == OP.GETGLOBAL then
				local name = Ks(ins.aux)
				if not isIdent(name) then
					fail("global with an unusable name")
				end
				ctx.globals[name] = true
				pushDef(block, ins, a, E("global", { name = name }), false)
			elseif op == OP.SETGLOBAL then
				local name = Ks(ins.aux)
				if not isIdent(name) then
					fail("global with an unusable name")
				end
				ctx.globals[name] = true
				local ex = takeOperands(block, ins, { a }, nil, true)
				pushStmt(block, { k = "assign", targets = { E("global", { name = name }) }, values = ex })
			elseif op == OP.GETUPVAL then
				pushDef(block, ins, a, E("upval", { name = ctx.upnames[b + 1] or fail("unknown upvalue") }), false)
			elseif op == OP.SETUPVAL then
				local ex = takeOperands(block, ins, { a })
				pushStmt(block, { k = "assign", targets = { E("upval", { name = ctx.upnames[b + 1] or fail("unknown upvalue") }) }, values = ex })
			elseif op == OP.GETIMPORT then
				local aux = ins.aux
				local count = rshift(aux, 30)
				local ids = { band(rshift(aux, 20), 1023), band(rshift(aux, 10), 1023), band(aux, 1023) }
				local root = Ks(ids[1])
				if not isIdent(root) or count < 1 or count > 3 then
					fail("unusable import")
				end
				ctx.globals[root] = true
				local ex = E("global", { name = root })
				for n = 2, count do
					local base = ex
					ex = E("index", { obj = base, key = E("const", { text = strLit(Ks(ids[n])), str = Ks(ids[n]) }) })
				end
				pushDef(block, ins, a, ex, false)
			elseif op == OP.GETTABLE then
				local ex = takeOperands(block, ins, { b, c })
				pushDef(block, ins, a, E("index", { obj = ex[1], key = ex[2] }), false)
			elseif op == OP.GETTABLEKS then
				local ex = takeOperands(block, ins, { b })
				local key = Ks(ins.aux)
				pushDef(block, ins, a, E("index", { obj = ex[1], key = E("const", { text = strLit(key), str = key }) }), false)
			elseif op == OP.GETTABLEN then
				local ex = takeOperands(block, ins, { b })
				pushDef(block, ins, a, E("index", { obj = ex[1], key = E("const", { text = tostring(c + 1) }) }), false)
			elseif op == OP.SETTABLE or op == OP.SETTABLEKS or op == OP.SETTABLEN then
				-- * value (and key) first, then the table: it may be a table constructor still being filled
				local keyExpr, valueExpr
				if op == OP.SETTABLE then
					local ex = takeOperands(block, ins, { c, a }, nil, true)
					keyExpr, valueExpr = ex[1], ex[2]
				else
					local ex = takeOperands(block, ins, { a }, nil, true)
					valueExpr = ex[1]
					if op == OP.SETTABLEKS then
						local key = Ks(ins.aux)
						keyExpr = E("const", { text = strLit(key), str = key })
					else
						keyExpr = E("const", { text = tostring(c + 1) })
					end
				end
				local tw = webOf(ins.useDef[b])
				local tail = block.stmts[#block.stmts]
				if tail and tail.tableCtor and tail.ctorWeb == tw and not tail.closedCtor
					and not mentions(keyExpr, tw) and not mentions(valueExpr, tw)
				then
					local entries = tail.value.entries
					local rank = keyExpr.str and tail.value.keyRank and tail.value.keyRank[keyExpr.str]
					local at = #entries + 1
					if rank then
						-- * before constant fields that come later in the source (constants have no
						-- * side effects, so nothing is evaluated in another order)
						while at > 1 and entries[at - 1].isConst and entries[at - 1].rank and entries[at - 1].rank > rank do
							at -= 1
						end
					end
					insert(entries, at, { key = keyExpr, value = valueExpr, rank = rank, line = ctx.ownLine and ctx.ownLine(ins.pc) or nil })
					tail.pure = false
					tw.useLeft -= 1
				else
					local ex = takeOperands(block, ins, { b })
					pushStmt(block, { k = "assign", targets = { E("index", { obj = ex[1], key = keyExpr }) }, values = { valueExpr } })
				end
			elseif op == OP.NEWTABLE or op == OP.DUPTABLE then
				-- * v7+ templates may already hold constant values
				local entries = {}
				local keyRank
				local tk = op == OP.DUPTABLE and K[ins.d]
				if tk and tk.v then
					keyRank = {}
					for j, keyIdx in tk.v do
						local keyK = K[keyIdx]
						if keyK and keyK.t == "string" and keyRank[keyK.v] == nil then
							keyRank[keyK.v] = j
						end
					end
				end
				if tk and tk.vals then
					for j, keyIdx in tk.v do
						local valIdx = tk.vals[j]
						local valK = valIdx >= 0 and K[valIdx]
						if valK and valK.t ~= "nil" then
							local keyK = K[keyIdx]
							local key = keyK.t == "string" and E("const", { text = strLit(keyK.v), str = keyK.v }) or K_(keyIdx)
							entries[#entries + 1] = { key = key, value = K_(valIdx), rank = j, isConst = true }
						end
					end
				end
				local st = pushDef(block, ins, a, E("table", { entries = entries, nextIndex = 1, keyRank = keyRank }), #entries == 0)
				st.tableCtor = true
				-- * fills right after creation go into the constructor, even for a variable
				st.ctorWeb = webOf(ins.defIds[a])
			elseif op == OP.SETLIST then
				local regs = {}
				local last = c > 0 and b + c - 2 or ins.multretFrom.a - 1
				for r = b, last do
					regs[#regs + 1] = r
				end
				local values = takeOperands(block, ins, regs, c == 0 and ins.multretFrom or nil)
				local tw = webOf(ins.useDef[a])
				local tail = block.stmts[#block.stmts]
				local selfRef = false
				for _, v in values do
					if mentions(v, tw) then
						selfRef = true
					end
				end
				if tail and tail.tableCtor and tail.ctorWeb == tw and not tail.closedCtor and tail.value.nextIndex == ins.aux and not selfRef then
					for _, v in values do
						insert(tail.value.entries, { value = v })
					end
					tail.value.nextIndex += #values
					tail.pure = false
					if c == 0 then
						tail.closedCtor = true -- * a multret item must stay the last field
					end
					tw.useLeft -= 1
				else
					if c == 0 then
						fail("SETLIST with multret outside a table constructor")
					end
					local ex = takeOperands(block, ins, { a })
					for n, v in values do
						pushStmt(block, { k = "assign", targets = { E("index", { obj = ex[1], key = E("const", { text = tostring(ins.aux + n - 1) }) }) }, values = { v } })
					end
				end
			elseif op == OP.NEWCLOSURE or op == OP.DUPCLOSURE then
				local caps = {}
				for n, cap in ins.captures do
					if cap.a == 2 then
						caps[n] = ctx.upnames[cap.b + 1] or fail("unknown upvalue")
					else
						caps[n] = { w = webOf(ins.useDef[cap.b]) }
						materialized[caps[n].w] = true
						caps[n].w.useLeft -= 1
					end
				end
				local selfW = webOf(ins.defIds[a])
				local st = pushDef(block, ins, a, E("closure", { child = ins.child, caps = caps, selfW = selfW }), false)
				if ctx.chunk.protos[ins.child].debugname then
					st.namedClosure = true -- * only folded into `t.name = ...`, otherwise `local function`
				end
			elseif op == OP.NAMECALL then
				pushStmt(block, { k = "namecall", ins = ins })
			elseif op == OP.CALL then
				local tail = block.stmts[#block.stmts]
				local argRegs = {}
				local isMethod = tail and tail.k == "namecall" and tail.ins.a == a
				local first = isMethod and a + 2 or a + 1
				local last = b > 0 and a + b - 1 or ins.multretFrom.a - 1
				for r = first, last do
					argRegs[#argRegs + 1] = r
				end
				local expr
				if isMethod then
					local nc = tail.ins
					absorbLine(block, block.stmts[#block.stmts])
					remove(block.stmts)
					-- * emitted as: object, arguments, NAMECALL, CALL
					local regs = { { ins = nc, reg = nc.b } }
					for _, r in argRegs do
						regs[#regs + 1] = r
					end
					local ex = takeOperands(block, ins, regs, b == 0 and ins.multretFrom or nil)
					local obj = remove(ex, 1)
					expr = E("method", { obj = obj, name = Ks(nc.aux), args = ex })
				else
					local regs = { a }
					for _, r in argRegs do
						regs[#regs + 1] = r
					end
					local ex = takeOperands(block, ins, regs, b == 0 and ins.multretFrom or nil)
					local fn = remove(ex, 1)
					expr = E("call", { fn = fn, args = ex })
				end
				if c == 1 then
					pushStmt(block, { k = "call", expr = expr })
				elseif c == 2 then
					pushDef(block, ins, a, expr, false)
				elseif c == 0 then
					expr.multret = true
					pushStmt(block, { k = "assign", tempWeb = true, multretOf = ins, value = expr, pure = false })
				else
					local targets = {}
					for r = a, a + c - 2 do
						targets[#targets + 1] = varExpr(webOf(ins.defIds[r]))
					end
					expr.multret = true
					pushStmt(block, { k = "assign", targets = targets, values = { expr } })
				end
			elseif op == OP.RETURN then
				local regs = {}
				local last = b > 0 and a + b - 2 or ins.multretFrom.a - 1
				for r = a, last do
					regs[#regs + 1] = r
				end
				local ex = takeOperands(block, ins, regs, b == 0 and ins.multretFrom or nil)
				pushStmt(block, { k = "return", values = ex })
			elseif ARITH[op] then
				local ex = takeOperands(block, ins, { b, c })
				pushDef(block, ins, a, E("binop", { op = ARITH[op], l = ex[1], r = ex[2] }), false)
			elseif ARITHK[op] then
				local ex = takeOperands(block, ins, { b })
				pushDef(block, ins, a, E("binop", { op = ARITHK[op], l = ex[1], r = K_(c) }), false)
			elseif op == OP.SUBRK or op == OP.DIVRK then
				local ex = takeOperands(block, ins, { c })
				pushDef(block, ins, a, E("binop", { op = op == OP.SUBRK and "-" or "/", l = K_(b), r = ex[1] }), false)
			elseif op == OP.AND or op == OP.OR then
				-- * the instruction evaluates both sides; `a or f()` would only call f sometimes, so a
				-- * right side with side effects stays in its own local (`local x = f()` ... `a or x`)
				local right = webOf(ins.useDef[c])
				if right.tempish then
					for k = #block.stmts, 1, -1 do
						local st = block.stmts[k]
						if st.tempWeb == right then
							if not isSideEffectFree(st.value) then
								right.noFold = true
							end
							break
						end
					end
				end
				local ex = takeOperands(block, ins, { b, c })
				if not isSideEffectFree(ex[2]) then
					-- * the instruction evaluates both sides; `a and f()` would not
					local w = webOf(ins.useDef[c])
					fail("and/or with a side effect on the right (" .. tostring(w.id) .. ")")
				end
				pushDef(block, ins, a, E(op == OP.AND and "and" or "or", { l = ex[1], r = ex[2] }), false)
			elseif op == OP.ANDK or op == OP.ORK then
				local ex = takeOperands(block, ins, { b })
				pushDef(block, ins, a, E(op == OP.ANDK and "and" or "or", { l = ex[1], r = K_(c) }), false)
			elseif op == OP.CONCAT then
				local regs = {}
				for r = b, c do
					regs[#regs + 1] = r
				end
				local ex = takeOperands(block, ins, regs)
				pushDef(block, ins, a, E("concat", { list = ex }), false)
			elseif op == OP.NOT then
				local ex = takeOperands(block, ins, { b })
				pushDef(block, ins, a, E("not", { e = ex[1] }), false)
			elseif op == OP.MINUS then
				local ex = takeOperands(block, ins, { b })
				pushDef(block, ins, a, E("unop", { op = "-", e = ex[1] }), false)
			elseif op == OP.LENGTH then
				local ex = takeOperands(block, ins, { b })
				pushDef(block, ins, a, E("unop", { op = "#", e = ex[1] }), false)
			elseif op == OP.GETVARARGS then
				if b == 0 then
					pushStmt(block, { k = "assign", tempWeb = true, multretOf = ins, value = E("vararg", { multret = true }), pure = false })
				elseif b == 2 then
					pushDef(block, ins, a, E("vararg"), false)
				elseif b > 2 then
					local targets = {}
					for r = a, a + b - 2 do
						targets[#targets + 1] = varExpr(webOf(ins.defIds[r]))
					end
					pushStmt(block, { k = "assign", targets = targets, values = { E("vararg", { multret = true }) } })
				end
			else
				fail("cannot express " .. tostring(Lifter.OP_NAMES[op]))
			end
		end

		-- * the source line a structured item starts on (bytecode line info), or nil
		local lineOf = ctx.ownLine
		local function itemLine(item)
			if not lineOf then
				return nil
			end
			local kind = item.kind
			local ins
			if kind == "ins" then
				ins = item.ins
			elseif kind == "if" or kind == "condjump" then
				ins = item.chain.segs[1].jump
			elseif kind == "numfor" or kind == "genfor" then
				ins = item.prep
			elseif kind == "while" then
				ins = A.byPc[item.loop.header]
			elseif kind == "valexpr" then
				local best
				for i2 in item.regionIns do
					local l = lineOf(i2.pc)
					if l and (not best or l < best) then
						best = l
					end
				end
				return best
			end
			return ins and lineOf(ins.pc) or nil
		end

		function buildBlock(astBlock, parent, loopStmt)
			local block = newBlock(parent, loopStmt)
			for _, item in astBlock.items do
				local line = itemLine(item)
				buildItem(block, item)
				if block.absorbedLine and (not line or block.absorbedLine < line) then
					line = block.absorbedLine
				end
				block.absorbedLine = nil
				-- * the statements this item added (earlier ones are already done)
				for n = #block.stmts, 1, -1 do
					local st = block.stmts[n]
					if st.lineDone then
						break
					end
					st.lineDone = true
					if st.line == nil then
						st.line = line
					end
				end
			end
			return block
		end

		function buildItem(block, item)
			do
				local kind = item.kind
				if kind == "ins" then
					emitIns(block, item.ins)
				elseif kind == "if" or kind == "condjump" then
					local cond = buildCondition(block, item.chain, false)
					if kind == "condjump" then
						local inner = cond
						cond = E("not", { e = inner })
					end
					cond = simplifyCond(cond)
					local st = { k = "if", cond = cond, refBlock = block, degenerate = item.degenerate }
					if kind == "condjump" then
						st.thenB = newBlock(block)
						st.thenB.stmts = { item.action == "return" and { k = "return", values = {} } or { k = item.action } }
					else
						st.thenB = buildBlock(item.thenB, block)
						if item.elseB then
							st.elseB = buildBlock(item.elseB, block)
						end
					end
					pushStmt(block, st)
				elseif kind == "while" then
					local st = { k = "while", loop = item.loop, refBlock = block }
					local bodyAst = item.body
					if item.chain then
						local scratch = newBlock(block)
						local ok, cond = pcall(buildCondition, scratch, item.chain, true)
						if ok and #scratch.stmts == 0 then
							st.cond = simplifyCond(cond)
						elseif not ok and not string.find(tostring(cond), FAIL, 1, true) then
							error(cond, 0)
						else
							bodyAst = item.fullBody()
						end
					end
					st.body = buildBlock(bodyAst, block, st)
					pushStmt(block, st)
				elseif kind == "numfor" then
					local prep = item.prep
					local ex = takeOperands(block, prep, { prep.a + 2, prep.a, prep.a + 1 })
					local st = { k = "numfor", init = ex[1], limit = ex[2], step = ex[3], loop = item.loop, refBlock = block }
					st.var = webOf(prep.lvDef)
					materialized[st.var] = true
					st.body = buildBlock(item.body, block, st)
					pushStmt(block, st)
				elseif kind == "genfor" then
					local prep, loopIns = item.prep, item.loopIns
					local st = { k = "genfor", loop = item.loop, refBlock = block }
					-- * `for k, v in pairs(t)`: one call producing the three iterator values
					local tail = block.stmts[#block.stmts]
					local regs = { prep.a, prep.a + 1, prep.a + 2 }
					local usedCall = false
					if tail and tail.k == "assign" and #tail.targets == 3 and #tail.values == 1 and tail.values[1].k == "call" then
						local ok = true
						for n = 1, 3 do
							local t = tail.targets[n]
							if not (t.k == "var" and t.w == webOf(prep.useDef[regs[n]]) and #t.w.uses == 1 and #t.w.defs == 1) then
								ok = false
							end
						end
						if ok then
							absorbLine(block, tail)
							remove(block.stmts)
							for n = 1, 3 do
								materialized[tail.targets[n].w] = nil
							end
							st.exprs = { tail.values[1] }
							usedCall = true
						end
					end
					if not usedCall then
						local ex = takeOperands(block, prep, regs)
						while #ex > 1 and ex[#ex].k == "const" and ex[#ex].text == "nil" do
							remove(ex)
						end
						st.exprs = ex
					end
					st.vars = {}
					for n, id in loopIns.lvDefs do
						st.vars[n] = webOf(id)
						materialized[st.vars[n]] = true
					end
					st.body = buildBlock(item.body, block, st)
					pushStmt(block, st)
				elseif kind == "valexpr" then
					local function leafValue(target, insList)
						local before = #target.stmts
						for _, i2 in insList do
							emitIns(target, i2)
						end
						-- * folding may remove earlier statements of `target`, never add more than the value
						if #target.stmts > before + 1 or #target.stmts == 0 then
							fail("value with side statements")
						end
						local st = remove(target.stmts)
						if st.k ~= "assign" or #st.targets ~= 1 or st.targets[1].k ~= "var" or #st.values ~= 1 then
							fail("unexpected value statement")
						end
						return st.values[1], st.targets[1].w
					end
					local curValue, Rw
					if item.leaf0 and not item.dropLeaf0 then
						curValue, Rw = leafValue(block, { item.leaf0 })
					end
					-- * `not` in a value context: only flips what is already a boolean
					local function valueNot(x)
						if x.k == "not" and x.e.k == "binop" and (x.e.op == "==" or x.e.op == "~=" or x.e.op == "<" or x.e.op == "<=") then
							return x.e
						elseif x.k == "binop" and x.op == "==" then
							return E("binop", { op = "~=", l = x.l, r = x.r })
						elseif x.k == "binop" and x.op == "~=" then
							return E("binop", { op = "==", l = x.l, r = x.r })
						end
						return E("not", { e = x })
					end
					local function isBoolean(x)
						return x.k == "not" or (x.k == "binop" and (x.op == "==" or x.op == "~=" or x.op == "<" or x.op == "<="))
							or (x.k == "const" and (x.text == "true" or x.text == "false"))
					end
					local function build(t)
						local k = t.k
						if k == "cur" then
							if not curValue then
								fail("value expression without its first value")
							end
							return curValue
						elseif k == "leaf" then
							local scratch = newBlock(block)
							local v, w = leafValue(scratch, t.el.run)
							if Rw and Rw ~= w then
								fail("value expression writes two variables")
							end
							Rw = w
							return v
						elseif k == "taken" or k == "fall" or k == "fallc" then
							-- * the first test of the expression may fold what was computed just before it
							local scratch = t.el == item.firstTest and block or newBlock(block)
							local before = #scratch.stmts
							for _, i2 in t.el.seg.pre do
								emitIns(scratch, i2)
							end
							local taken = condLeaf(scratch, t.el.seg)
							if scratch ~= block and #scratch.stmts > 0 then
								fail("condition with side statements")
							end
							if k == "taken" then
								return taken
							elseif k == "fallc" then
								return boolNot(taken)
							end
							return valueNot(taken)
						elseif k == "and" or k == "or" then
							local l = build(t.l)
							local r = build(t.r)
							return E(k, { l = l, r = r })
						elseif k == "cond" then
							local c = build(t.c)
							local a = build(t.a)
							local b = build(t.b)
							if a.k == "const" and a.text == "false" then
								return E("and", { l = valueNot(c), r = b })
							elseif a.k == "const" and a.text == "true" and isBoolean(c) then
								return E("or", { l = c, r = b })
							end
							return E("ifexpr", { c = c, a = a, b = b })
						end
						fail("bad value tree")
					end
					local value = build(item.tree)
					if not Rw then
						fail("value expression without a target")
					end
					local st = pushStmt(block, { k = "assign", targets = { E("var", { w = Rw }) }, values = { value }, value = value })
					-- * used exactly once, right after, and only written here: fold it like a temporary
					local outside = {}
					for _, u in Rw.uses do
						if not item.regionIns[u.ins] then
							outside[#outside + 1] = u
						end
					end
					local ownDefs = true
					for _, id in Rw.defs do
						local info = A.defInfo[id]
						if not (info.ins and item.regionIns[info.ins]) then
							ownDefs = false
						end
					end
					if ownDefs and not Rw.captured and #outside == 1 and outside[1].ins.block == A.blockAt[item.join] and not Rw.noFold then
						Rw.tempish = true
						Rw.useLeft = 1
						st.tempWeb = Rw
					else
						materialized[Rw] = true
					end

				elseif kind == "break" or kind == "continue" then
					pushStmt(block, { k = kind })
				elseif kind == "return" then
					pushStmt(block, { k = "return", values = {} })
				elseif kind == "breakblock" then
					local st = { k = "repeat", loop = item.loop, untilCond = E("const", { text = "true" }), isBlock = true }
					st.body = buildBlock(item.body, block, st)
					pushStmt(block, st)
				else
					fail("unknown node " .. tostring(kind))
				end
			end
		end

		local root = buildBlock(ast, nil, nil)
		local function markTargets(block)
			for _, st in block.stmts do
				if st.k == "assign" then
					for _, t in st.targets do
						if t.k == "var" then
							materialized[t.w] = true
						end
					end
				end
				for _, child in { st.thenB or false, st.elseB or false, st.body or false } do
					if child then
						markTargets(child)
					end
				end
			end
		end
		markTargets(root)
		-- * `return` with no values at the very end of a function is implicit
		local last = root.stmts[#root.stmts]
		if last and last.k == "return" and #last.values == 0 then
			remove(root.stmts)
		end
		return root, materialized
	end

	--------------------------------------------------------------------------
	-- variables: names and declarations
	--------------------------------------------------------------------------
	local function forEachExpr(e, fn)
		if not e then
			return
		end
		fn(e)
		local k = e.k
		if k == "index" then
			forEachExpr(e.obj, fn)
			forEachExpr(e.key, fn)
		elseif k == "call" then
			forEachExpr(e.fn, fn)
			for _, a in e.args do
				forEachExpr(a, fn)
			end
		elseif k == "method" then
			forEachExpr(e.obj, fn)
			for _, a in e.args do
				forEachExpr(a, fn)
			end
		elseif k == "binop" or k == "and" or k == "or" then
			forEachExpr(e.l, fn)
			forEachExpr(e.r, fn)
		elseif k == "unop" or k == "not" then
			forEachExpr(e.e, fn)
		elseif k == "ifexpr" then
			forEachExpr(e.c, fn)
			forEachExpr(e.a, fn)
			forEachExpr(e.b, fn)
		elseif k == "concat" then
			for _, a in e.list do
				forEachExpr(a, fn)
			end
		elseif k == "table" then
			for _, entry in e.entries do
				forEachExpr(entry.key, fn)
				forEachExpr(entry.value, fn)
			end
		end
	end

	-- * webs referenced by a statement (not inside nested blocks), and nested blocks
	local function stmtRefs(st, fn)
		local function ex(e)
			forEachExpr(e, function(x)
				if x.k == "var" then
					fn(x.w)
				elseif x.k == "closure" then
					for _, cap in x.caps do
						if type(cap) == "table" then
							fn(cap.w)
						end
					end
				end
			end)
		end
		local k = st.k
		if k == "assign" then
			for _, t in st.targets do
				ex(t)
			end
			for _, v in st.values do
				ex(v)
			end
		elseif k == "call" then
			ex(st.expr)
		elseif k == "return" then
			for _, v in st.values do
				ex(v)
			end
		elseif k == "if" then
			ex(st.cond)
		elseif k == "numfor" then
			ex(st.init)
			ex(st.limit)
			ex(st.step)
		elseif k == "genfor" then
			for _, v in st.exprs do
				ex(v)
			end
		end
	end
	local function childBlocks(st)
		local k = st.k
		if k == "if" then
			return st.thenB, st.elseB
		elseif k == "while" or k == "numfor" or k == "genfor" or k == "repeat" then
			return st.body
		end
	end

	-- * `while true do ... if c then break end end` without continue -> `repeat ... until c`
	local function makeRepeats(block)
		for _, st in block.stmts do
			local a, b = childBlocks(st)
			if a then
				makeRepeats(a)
			end
			if b then
				makeRepeats(b)
			end
			if st.k == "while" and not st.cond then
				local body = st.body.stmts
				local last = body[#body]
				if last and last.k == "if" and not last.elseB and #last.thenB.stmts == 1 and last.thenB.stmts[1].k == "break" then
					local hasContinue = false
					local function scan(b2)
						for _, s in b2.stmts do
							if s.k == "continue" then
								hasContinue = true
							end
							if s.k ~= "while" and s.k ~= "numfor" and s.k ~= "genfor" and s.k ~= "repeat" then
								local x, y = childBlocks(s)
								if x then
									scan(x)
								end
								if y then
									scan(y)
								end
							end
						end
					end
					scan(st.body)
					if not hasContinue then
						remove(body)
						st.k = "repeat"
						st.untilCond = last.cond
					end
				end
			end
		end
	end

	local function makeIfExpressions(block)
		for i, st in block.stmts do
			local a, b = childBlocks(st)
			if a then
				makeIfExpressions(a)
			end
			if b then
				makeIfExpressions(b)
			end
			if st.k == "if" and st.elseB and #st.thenB.stmts == 1 and #st.elseB.stmts == 1 then
				local x, y = st.thenB.stmts[1], st.elseB.stmts[1]
				if x.k == "assign" and y.k == "assign" and #x.targets == 1 and #y.targets == 1 and #x.values == 1 and #y.values == 1
					and x.targets[1].k == "var" and y.targets[1].k == "var" and x.targets[1].w == y.targets[1].w
					and x.values[1].k ~= "closure" and y.values[1].k ~= "closure"
				then
					block.stmts[i] = { k = "assign", targets = { x.targets[1] }, values = { E("ifexpr", { c = st.cond, a = x.values[1], b = y.values[1] }) }, line = st.line }
				end
			end
		end
	end

	-- * Luau allows 200 locals in scope at once. Generated code (one `local name = "X"` per
	-- * entry, hundreds of times, each scoped in the original) needs `do ... end` blocks.
	local function exprRefs(e, fn)
		forEachExpr(e, function(x)
			if x.k == "var" then
				fn(x.w)
			elseif x.k == "closure" then
				for _, cap in x.caps do
					if type(cap) == "table" then
						fn(cap.w)
					end
				end
			end
		end)
	end
	local function deepRefs(st, fn)
		stmtRefs(st, fn)
		if st.k == "local" then
			fn(st.w)
		elseif st.k == "numfor" and st.var then
			fn(st.var)
		elseif st.k == "genfor" and st.vars then
			for _, w in st.vars do
				fn(w)
			end
		elseif st.k == "while" and st.cond then
			exprRefs(st.cond, fn)
		elseif st.k == "repeat" and st.untilCond then
			exprRefs(st.untilCond, fn)
		end
		local a, b = childBlocks(st)
		for _, child in { a, b } do
			for _, s2 in child.stmts do
				deepRefs(s2, fn)
			end
		end
	end
	local function declaredIn(st)
		if st.k == "local" then
			return { st.w }
		elseif st.k == "assign" and (st.isLocal or st.isLocalFunction) then
			local list = {}
			for _, t in st.targets do
				if t.k == "var" then
					list[#list + 1] = t.w
				end
			end
			return list
		end
		return nil
	end
	local function maxActive(block)
		local declared, deepest = 0, 0
		for _, st in block.stmts do
			local d = declaredIn(st)
			if d then
				declared += #d
			end
			local a, b = childBlocks(st)
			local loopVars = (st.k == "numfor" and 4) or (st.k == "genfor" and #st.vars + 3) or 0
			if a then
				deepest = math.max(deepest, maxActive(a) + loopVars)
			end
			if b then
				deepest = math.max(deepest, maxActive(b))
			end
		end
		return declared + deepest
	end
	-- * a `break` / `continue` of an enclosing loop
	local function hasLoopExit(block)
		for _, st in block.stmts do
			if st.k == "break" or st.k == "continue" then
				return true
			end
			if st.k ~= "while" and st.k ~= "numfor" and st.k ~= "genfor" and not (st.k == "repeat" and not st.isDo) then
				local a, b = childBlocks(st)
				if (a and hasLoopExit(a)) or (b and hasLoopExit(b)) then
					return true
				end
			end
		end
		return false
	end
	local function scopeShortLocals(block, parentStmt)
		for _, st in block.stmts do
			local a, b = childBlocks(st)
			if a then
				scopeShortLocals(a, st)
			end
			if b then
				scopeShortLocals(b, st)
			end
		end
		local stmts = block.stmts
		local lastUse = {}
		for n, st in stmts do
			deepRefs(st, function(w)
				lastUse[w] = n
			end)
		end
		-- * `repeat local x ... until x`: the condition sees the body's locals
		if parentStmt and parentStmt.k == "repeat" and parentStmt.untilCond and block == parentStmt.body then
			exprRefs(parentStmt.untilCond, function(w)
				lastUse[w] = math.huge
			end)
		end
		local MAX_SPAN = 64
		local i = 1
		while i <= #stmts do
			local decl = declaredIn(stmts[i])
			if decl then
				local j = i
				for _, w in decl do
					j = math.max(j, lastUse[w] or i)
				end
				-- * whatever is declared inside must also end inside
				local n = i + 1
				while n <= j and j - i < MAX_SPAN do
					local d2 = declaredIn(stmts[n])
					if d2 then
						for _, w in d2 do
							j = math.max(j, lastUse[w] or n)
						end
					end
					n += 1
				end
				if j - i < MAX_SPAN and j <= #stmts and not (i == 1 and j == #stmts) then
					local body = { stmts = table.move(stmts, i, j, 1, {}), parent = block, depth = (block.depth or 0) + 1 }
					if not hasLoopExit(body) then
						for _ = i, j do
							remove(stmts, i)
						end
						insert(stmts, i, { k = "repeat", isBlock = true, isDo = true, untilCond = E("const", { text = "true" }), body = body })
						local shift = j - i
						for w, at in lastUse do
							if at > j and at ~= math.huge then
								lastUse[w] = at - shift
							elseif at >= i and at <= j then
								lastUse[w] = i
							end
						end
					end
				end
			end
			i += 1
		end
	end

	local function placeDeclarations(A, root, materialized, ctx)
		-- * parents of blocks / loop info
		local refsByWeb = {} -- w -> list of { block, index }
		local function visit(block)
			for i, st in block.stmts do
				local function note(w)
					local list = refsByWeb[w]
					if not list then
						list = {}
						refsByWeb[w] = list
					end
					list[#list + 1] = { block = block, index = i }
				end
				stmtRefs(st, note)
				if st.k == "repeat" and st.untilCond then
					forEachExpr(st.untilCond, function(x)
						if x.k == "var" then
							local list = refsByWeb[x.w]
							if not list then
								list = {}
								refsByWeb[x.w] = list
							end
							list[#list + 1] = { block = st.body, index = #st.body.stmts + 1 }
						end
					end)
				end
				if st.k == "while" and st.cond then
					forEachExpr(st.cond, function(x)
						if x.k == "var" then
							local list = refsByWeb[x.w]
							if not list then
								list = {}
								refsByWeb[x.w] = list
							end
							list[#list + 1] = { block = st.body, index = 0 }
						end
					end)
				end
				local a, b = childBlocks(st)
				if a then
					a.parent, a.parentStmt, a.parentIndex = block, st, i
					a.depth = block.depth + 1
					visit(a)
				end
				if b then
					b.parent, b.parentStmt, b.parentIndex = block, st, i
					b.depth = block.depth + 1
					visit(b)
				end
			end
		end
		root.depth = 0
		visit(root)

		local function lca(x, y)
			while x.depth > y.depth do
				x = x.parent
			end
			while y.depth > x.depth do
				y = y.parent
			end
			while x ~= y do
				x, y = x.parent, y.parent
			end
			return x
		end
		-- * index of the statement in `ancestor` that contains `block`
		local function indexIn(ancestor, block, index)
			while block ~= ancestor do
				index = block.parentIndex
				block = block.parent
			end
			return index
		end
		local function loopEntryBlock(st)
			local loop = st.loop
			return loop and A.blockAt[loop.header]
		end

		local decls = {} -- block -> list of { index, w }
		for w in materialized do
			local kinds = w.kinds
			if kinds.hidden or kinds.undefined then
				fail("reads a register that has no value")
			end
			local refs = refsByWeb[w]
			if kinds.param or kinds.loopvar then
				-- * a generic for's variables may be reassigned in the body (the iteration state is a
				-- * separate copy); a numeric for's may not
				if kinds.loopvar and (kinds.normal or kinds.param) then
					for _, id in w.defs do
						local info = A.defInfo[id]
						if info.kind == "loopvar" and info.ins.op ~= OP.FORGLOOP then
							fail("numeric loop variable is assigned")
						end
						if info.kind == "param" then
							fail("loop variable merged with a parameter")
						end
					end
				end
			elseif refs then
				local target = refs[1].block
				for n = 2, #refs do
					target = lca(target, refs[n].block)
				end
				-- * hoist out of every loop it must survive across
				local b = target
				while b do
					if b.parentStmt and (b.parentStmt.k == "while" or b.parentStmt.k == "repeat" or b.parentStmt.k == "numfor" or b.parentStmt.k == "genfor") and b == b.parentStmt.body then
						local entry = loopEntryBlock(b.parentStmt)
						local live = entry and (A.liveIn[entry][w] or (A.openWebsAt[entry.start] and A.openWebsAt[entry.start][w]))
						if live then
							target = b.parent
						end
					end
					b = b.parent
				end
				local first = math.huge
				for _, ref in refs do
					local blk, idx = ref.block, ref.index
					local depthOk = true
					local cur = blk
					while cur and cur ~= target do
						cur = cur.parent
					end
					if not cur then
						depthOk = false
					end
					if depthOk then
						local i = indexIn(target, blk, idx)
						if i < first then
							first = i
						end
					end
				end
				if first == math.huge then
					first = 1
				end
				first = math.max(first, 1)
				local list = decls[target]
				if not list then
					list = {}
					decls[target] = list
				end
				list[#list + 1] = { index = first, w = w }
			end
		end
		-- * make the declarations: `local x = value` when possible
		local count = 0
		for block, list in decls do
			table.sort(list, function(x, y)
				if x.index ~= y.index then
					return x.index > y.index
				end
				return x.w.id < y.w.id
			end)
			for _, d in list do
				count += 1
				local st = block.stmts[d.index]
				local merged = false
				if st and st.k == "assign" and #st.targets == 1 and st.targets[1].k == "var" and st.targets[1].w == d.w and not st.isLocal then
					local selfRef = false
					forEachExpr(st.values[1], function(x)
						if x.k == "var" and x.w == d.w then
							selfRef = true
						end
					end)
					local v = st.values[1]
					if v.k == "closure" then
						for _, cap in v.caps do
							if type(cap) == "table" and cap.w == d.w then
								selfRef = "function"
							end
						end
					end
					if selfRef == "function" then
						st.isLocalFunction = true
						merged = true
					elseif not selfRef then
						st.isLocal = true
						merged = true
					end
				elseif st and st.k == "assign" and #st.targets > 1 and not st.isLocal then
					-- * `local a, b = f()` when every target is declared here
					local all = true
					for _, t in st.targets do
						if t.k ~= "var" then
							all = false
						end
					end
					if all then
						st.pendingLocal = st.pendingLocal or {}
						st.pendingLocal[d.w] = true
						local n = 0
						for _ in st.pendingLocal do
							n += 1
						end
						if n == #st.targets then
							st.isLocal = true
						end
						merged = true
					end
				end
				if not merged then
					insert(block.stmts, d.index, { k = "local", w = d.w })
				end
			end
		end
		-- * multi-target assignments that only got some of their targets declared there
		local function fixPartial(block)
			local n = 1
			while n <= #block.stmts do
				local st = block.stmts[n]
				if st.k == "assign" and st.pendingLocal and not st.isLocal then
					for w in st.pendingLocal do
						insert(block.stmts, n, { k = "local", w = w })
						n += 1
					end
					st.pendingLocal = nil
				end
				local a, b = childBlocks(st)
				if a then
					fixPartial(a)
				end
				if b then
					fixPartial(b)
				end
				n += 1
			end
		end
		fixPartial(root)
		-- * at most 200 locals in scope at once (with some room for the compiler)
		local LIMIT = 190
		if maxActive(root) + A.p.numparams > LIMIT then
			scopeShortLocals(root)
			if maxActive(root) + A.p.numparams > LIMIT then
				fail("too many locals")
			end
		end
	end

	--------------------------------------------------------------------------
	-- naming: Roblox style names from what a variable holds and how it is used
	--------------------------------------------------------------------------
	local NAME_KEYWORDS = {}
	for word in string.gmatch(
		"and break do else elseif end false for function if in local nil not or repeat return then true until while continue export type typeof",
		"%S+"
	) do
		NAME_KEYWORDS[word] = true
	end

	local BUILTIN_NAMES = {}
	for word in string.gmatch([[
		assert error getfenv getmetatable ipairs load loadstring newproxy next pairs pcall print rawequal rawget rawlen
		rawset require select setfenv setmetatable tonumber tostring type typeof unpack xpcall ypcall gcinfo
		collectgarbage _G _VERSION string table math os coroutine bit32 utf8 buffer debug task vector game workspace
		script shared plugin settings UserSettings wait delay spawn tick time elapsedTime warn version stats Enum
		Instance Vector3 Vector2 CFrame Color3 BrickColor UDim UDim2 Ray Region3 TweenInfo NumberRange NumberSequence
		ColorSequence Random Rect DateTime Font Faces Axes PhysicalProperties RaycastParams OverlapParams SharedTable
		Content Vector3int16 Vector2int16 NumberSequenceKeypoint ColorSequenceKeypoint PathWaypoint Region3int16 self]], "%S+") do
		BUILTIN_NAMES[word] = true
	end

	local CAMEL_SPECIAL = {
		CFrame = "cframe", UDim2 = "udim2", UDim = "udim", GUI = "gui", UI = "ui", ID = "id", NPC = "npc",
		HRP = "hrp", FOV = "fov", URL = "url", JSON = "json", HTTP = "http", FFlag = "fflag",
	}

	-- * "Hello World" / "hello-world" / "__index" -> "HelloWorld" / "helloWorld" / "index"
	local function cleanWord(s)
		if type(s) ~= "string" then
			return nil
		end
		s = string.gsub(s, "[^%w_]+(%w)", string.upper)
		s = string.gsub(s, "[^%w_]", "")
		s = string.gsub(s, "^_+", "")
		s = string.gsub(s, "_+$", "")
		if s == "" or #s > 40 or string.find(s, "^%d") then
			return nil
		end
		return s
	end

	-- * "LocalPlayer" -> "localPlayer", "CFrame" -> "cframe", "HTTPService" -> "httpService"
	local function camel(s)
		s = cleanWord(s)
		if not s then
			return nil
		end
		if CAMEL_SPECIAL[s] then
			return CAMEL_SPECIAL[s]
		end
		for prefix, low in CAMEL_SPECIAL do
			if #s > #prefix and string.sub(s, 1, #prefix) == prefix and string.find(s, "^%u", #prefix + 1) then
				return low .. string.sub(s, #prefix + 1)
			end
		end
		if not string.find(s, "%l") then
			return string.lower(s)
		end
		local run = string.match(s, "^%u+")
		if not run then
			return s
		end
		if #run == 1 then
			return string.lower(run) .. string.sub(s, 2)
		end
		return string.lower(string.sub(run, 1, -2)) .. string.sub(s, #run)
	end

	local function constStr(e)
		if e and e.k == "const" then
			if e.str then
				return e.str
			end
			if e.value and e.value.t == "string" then
				return e.value.v
			end
		end
		return nil
	end

	local function upperFirst(s)
		return (string.gsub(s, "^%l", string.upper))
	end

	local IRREGULAR_PLURALS = {
		children = "child", people = "person", data = "entry", indices = "index", vertices = "vertex",
		matrices = "matrix", mice = "mouse", leaves = "leaf", knives = "knife", lives = "life",
	}
	local function singular(s)
		if not s then
			return nil
		end
		if IRREGULAR_PLURALS[s] then
			return IRREGULAR_PLURALS[s]
		end
		if #s < 4 then
			return nil
		end
		if string.find(s, "ies$") then
			return string.sub(s, 1, -4) .. "y"
		elseif string.find(s, "sses$") or string.find(s, "[xz]es$") or string.find(s, "[cs]hes$") then
			return string.sub(s, 1, -3)
		elseif string.find(s, "[^su]s$") then
			return string.sub(s, 1, -2)
		end
		return nil
	end

	-- * the name of one element of a collection: "players" -> "player", "fooToModuleMap" -> "module"
	local function elementName(s)
		if not s then
			return nil
		end
		local single = singular(s)
		if single then
			return single
		end
		local target = string.match(s, "^%l[%w]-To(%u%w-)Map$")
		if target then
			return camel(target)
		end
		for _, suffix in { "Map", "Lookup", "Table", "Dict", "Dictionary", "Cache", "List", "Array", "Registry" } do
			local base = string.match(s, "^(.-)" .. suffix .. "$")
			if base and #base >= 2 then
				return singular(base) or base
			end
		end
		return nil
	end

	-- * parameters of the functions Roblox events pass to a connected function
	local EVENT_PARAMS = {
		CharacterAdded = { "character" }, CharacterRemoving = { "character" }, CharacterAppearanceLoaded = { "character" },
		ChildAdded = { "child" }, ChildRemoved = { "child" }, DescendantAdded = { "descendant" },
		DescendantRemoving = { "descendant" }, AncestryChanged = { "child", "parent" },
		PlayerAdded = { "player" }, PlayerRemoving = { "player" }, Touched = { "hit" },
		Changed = { "property" }, AttributeChanged = { "attribute" },
		InputBegan = { "input", "gameProcessedEvent" }, InputChanged = { "input", "gameProcessedEvent" },
		InputEnded = { "input", "gameProcessedEvent" }, TouchStarted = { "touch", "gameProcessedEvent" },
		TouchMoved = { "touch", "gameProcessedEvent" }, TouchTap = { "touchPositions", "gameProcessedEvent" },
		LastInputTypeChanged = { "lastInputType" }, GamepadConnected = { "gamepadNum" }, GamepadDisconnected = { "gamepadNum" },
		Heartbeat = { "deltaTime" }, RenderStepped = { "deltaTime" }, PreRender = { "deltaTime" },
		PreSimulation = { "deltaTime" }, PostSimulation = { "deltaTime" }, PreAnimation = { "deltaTime" },
		Stepped = { "time", "deltaTime" }, HealthChanged = { "health" }, Running = { "speed" },
		Jumping = { "active" }, FreeFalling = { "active" }, Climbing = { "speed" }, Swimming = { "speed" },
		Seated = { "active", "currentSeatPart" }, StateChanged = { "oldState", "newState" },
		MoveToFinished = { "reached" }, Chatted = { "message" }, Idled = { "time" },
		Activated = { "inputObject", "clickCount" }, MouseEnter = { "x", "y" }, MouseLeave = { "x", "y" },
		MouseMoved = { "x", "y" }, MouseButton1Down = { "x", "y" }, MouseButton1Up = { "x", "y" },
		MouseButton2Down = { "x", "y" }, MouseButton2Up = { "x", "y" }, MouseWheelForward = { "x", "y" },
		MouseWheelBackward = { "x", "y" }, FocusLost = { "enterPressed", "inputThatCausedFocusLoss" },
		OnServerEvent = { "player" }, Completed = { "playbackState" }, Equipped = { "mouse" },
		Triggered = { "player" }, TriggerEnded = { "player" }, MouseClick = { "player" },
		PromptTriggered = { "prompt", "player" }, KeyframeReached = { "keyframeName" },
		AnimationPlayed = { "animationTrack" }, PromptProductPurchaseFinished = { "userId", "productId", "isPurchased" },
		PromptGamePassPurchaseFinished = { "player", "gamePassId", "wasPurchased" },
		PromptPurchaseFinished = { "player", "assetId", "isPurchased" }, TextChanged = {},
	}

	-- * results of methods with fixed meanings
	local METHOD_RESULTS = {
		GetChildren = "children", GetDescendants = "descendants", GetPlayers = "players", GetTags = "tags",
		GetMouse = "mouse", GetPlayerFromCharacter = "player", GetPlayerByUserId = "player", GetState = "state",
		Clone = "clone", Raycast = "raycastResult", GetTouchingParts = "touchingParts", GetPartsInPart = "parts",
		GetPartBoundsInBox = "parts", GetPartBoundsInRadius = "parts", JSONDecode = "data", JSONEncode = "json",
		GenerateGUID = "guid", GetAsync = "data", HttpGet = "response", HttpGetAsync = "response",
		PostAsync = "response", RequestAsync = "response", InvokeServer = "result", InvokeClient = "result",
		Invoke = "result", GetFocusedTextBox = "textBox", GetServerTimeNow = "now", LoadAnimation = "track",
		PointToWorldSpace = "worldPoint", VectorToWorldSpace = "worldVector", PointToObjectSpace = "localPoint",
		VectorToObjectSpace = "localVector", ToWorldSpace = "worldCFrame", ToObjectSpace = "relativeCFrame",
		GetPivot = "pivot", GetExtentsSize = "size", GetMass = "mass", GetDataStore = "dataStore",
		GetOrderedDataStore = "dataStore", GetGlobalDataStore = "dataStore", UserOwnsGamePassAsync = "ownsGamePass",
		PlayerOwnsAsset = "ownsAsset", Connect = "connection", Once = "connection", ConnectParallel = "connection",
		ScreenPointToRay = "ray", ViewportPointToRay = "ray", Cross = "cross", Dot = "dot", Lerp = "lerped",
		Create = "tween", GetUserId = "userId", GetFullName = "fullName",
		format = "text", sub = "substring", rep = "repeated", len = "length", split = "parts", byte = "byte",
		find = { "startIndex", "endIndex" }, match = "match",
		FindPartOnRay = { "hit", "position", "normal", "material" },
		FindPartOnRayWithIgnoreList = { "hit", "position", "normal", "material" },
		FindPartOnRayWithWhitelist = { "hit", "position", "normal", "material" },
		WorldToScreenPoint = { "screenPoint", "onScreen" }, WorldToViewportPoint = { "viewportPoint", "onScreen" },
		ToEulerAnglesYXZ = { "rx", "ry", "rz" }, ToEulerAnglesXYZ = { "rx", "ry", "rz" },
		ToOrientation = { "rx", "ry", "rz" }, ToAxisAngle = { "axis", "angle" },
		GetBoundingBox = { "boundingCFrame", "boundingSize" },
		GetComponents = { "x", "y", "z", "r00", "r01", "r02", "r10", "r11", "r12", "r20", "r21", "r22" },
		components = { "x", "y", "z", "r00", "r01", "r02", "r10", "r11", "r12", "r20", "r21", "r22" },
	}
	-- * `obj:Method("Name")`: the string names the result
	local CHILD_BY_NAME = { WaitForChild = true, FindFirstChild = true, FindFirstAncestor = true, FindFirstDescendant = true }
	local CHILD_BY_CLASS = {
		FindFirstChildOfClass = true, FindFirstChildWhichIsA = true, FindFirstAncestorOfClass = true,
		FindFirstAncestorWhichIsA = true,
	}
	local FLAG_METHODS = {
		IsUserFeatureEnabled = "FFlag", GetFFlag = "FFlag", GetFastFlag = "FFlag", DefineFastFlag = "FFlag",
		GetEngineFeature = "FFlag", GetFastInt = "FInt", DefineFastInt = "FInt", GetFastString = "FString",
		DefineFastString = "FString",
	}
	-- * results of global functions
	local CALL_RESULTS = {
		tostring = "text", tonumber = "number", typeof = "valueType", type = "valueType", getmetatable = "metatable",
		next = { "key", "value" }, ["os.clock"] = "now", ["os.time"] = "now", tick = "now", time = "now",
		elapsedTime = "now", ["os.date"] = "date", ["math.random"] = "randomNumber", ["math.atan2"] = "angle",
		["math.atan"] = "angle", ["math.rad"] = "radians", ["math.deg"] = "degrees", ["math.sqrt"] = "root",
		["math.sign"] = "sign", ["math.noise"] = "noise", ["math.min"] = "minimum", ["math.max"] = "maximum",
		["math.clamp"] = "clamped", ["math.floor"] = "rounded", ["math.ceil"] = "rounded", ["math.round"] = "rounded",
		["math.abs"] = "absolute", ["math.lerp"] = "lerped", ["string.format"] = "text", ["string.split"] = "parts",
		["string.sub"] = "substring", ["string.len"] = "length", ["string.rep"] = "repeated", ["string.lower"] = "lower",
		["string.upper"] = "upper", ["string.find"] = { "startIndex", "endIndex" }, ["string.match"] = "match",
		["string.gsub"] = { "result", "count" }, ["string.byte"] = "byte", ["string.char"] = "character",
		["table.concat"] = "text", ["table.find"] = "index", ["table.remove"] = "removed", ["table.create"] = "list",
		["table.pack"] = "packed", ["table.clone"] = "copy", ["coroutine.create"] = "thread",
		["coroutine.wrap"] = "thread", ["coroutine.running"] = "thread", ["coroutine.resume"] = { "success", "result" },
		["coroutine.status"] = "status", ["task.spawn"] = "thread", ["task.defer"] = "thread", ["task.delay"] = "thread",
		spawn = "thread", delay = "thread", ["task.wait"] = "elapsed", wait = "elapsed",
		pcall = { "success", "result" }, xpcall = { "success", "result" }, ypcall = { "success", "result" },
		["Vector3.new"] = "vector", ["Vector2.new"] = "vector", ["Vector3int16.new"] = "vector",
		["Vector2int16.new"] = "vector", ["vector.create"] = "vector", ["CFrame.new"] = "cframe",
		["CFrame.lookAt"] = "cframe", ["CFrame.fromMatrix"] = "cframe", ["CFrame.Angles"] = "rotation",
		["CFrame.fromEulerAnglesXYZ"] = "rotation", ["CFrame.fromEulerAnglesYXZ"] = "rotation",
		["CFrame.fromOrientation"] = "rotation", ["CFrame.fromAxisAngle"] = "rotation", ["Color3.new"] = "color",
		["Color3.fromRGB"] = "color", ["Color3.fromHSV"] = "color", ["Color3.fromHex"] = "color",
		["BrickColor.new"] = "brickColor", ["BrickColor.random"] = "brickColor", ["UDim2.new"] = "udim2",
		["UDim2.fromScale"] = "udim2", ["UDim2.fromOffset"] = "udim2", ["UDim.new"] = "udim",
		["TweenInfo.new"] = "tweenInfo", ["RaycastParams.new"] = "raycastParams", ["OverlapParams.new"] = "overlapParams",
		["Random.new"] = "random", ["Ray.new"] = "ray", ["Region3.new"] = "region", ["NumberRange.new"] = "range",
		["NumberSequence.new"] = "sequence", ["ColorSequence.new"] = "sequence",
		["NumberSequenceKeypoint.new"] = "keypoint", ["ColorSequenceKeypoint.new"] = "keypoint",
		["PhysicalProperties.new"] = "physicalProperties", ["DateTime.now"] = "now", ["Font.new"] = "font",
		["Rect.new"] = "rect", ["buffer.create"] = "buf", ["buffer.fromstring"] = "buf", ["utf8.char"] = "character",
		["utf8.len"] = "length",
	}
	-- * `obj.Field`: fields whose own name is too vague without the object's name
	local PREFIXED_FIELDS = {
		CFrame = true, Position = true, Size = true, Value = true, Magnitude = true, Unit = true, LookVector = true,
		RightVector = true, UpVector = true, Name = true, Text = true, Velocity = true, Orientation = true, Rotation = true,
	}
	local FIELD_RESULTS = {
		LocalPlayer = "player", CurrentCamera = "camera", Character = "character", Humanoid = "humanoid",
		HumanoidRootPart = "rootPart", Parent = "parent",
	}
	-- * what reading a field says about the object
	local FIELD_KINDS = {
		Character = "player", UserId = "player", DisplayName = "player", Team = "player", TeamColor = "player",
		Backpack = "player", PlayerGui = "player", leaderstats = "player", AccountAge = "player", CharacterAdded = "player",
		Humanoid = "character", HumanoidRootPart = "character", Head = "character", Torso = "character",
		UpperTorso = "character", KeyCode = "input", UserInputType = "input", UserInputState = "input",
		Health = "humanoid", MaxHealth = "humanoid", WalkSpeed = "humanoid", JumpPower = "humanoid",
		JumpHeight = "humanoid", MoveDirection = "humanoid", RootPart = "humanoid", FloorMaterial = "humanoid",
		HipHeight = "humanoid", Anchored = "part", CanCollide = "part", CanTouch = "part", Material = "part",
		BrickColor = "part", AssemblyLinearVelocity = "part", Touched = "part", Text = "label", TextColor3 = "label",
		TextSize = "label", MouseButton1Click = "button", Activated = "button", Volume = "sound", SoundId = "sound",
		IsPlaying = "track", AnimationId = "animation", LookVector = "cframe", RightVector = "cframe",
		UpVector = "cframe",
	}
	local FIELD_KIND_SCORE = {
		player = 1, character = 1, input = 1, humanoid = 1, part = 0.8, label = 0.6, button = 0.8, sound = 0.8,
		track = 0.8, animation = 0.8, cframe = 0.6,
	}

	-- * `pcall(function() return settings:IsUserFeatureEnabled("Name") end)`: the flag it reads
	local function flagNameOfProto(chunk, protoId, ctx)
		ctx.flagNames = ctx.flagNames or {}
		local cached = ctx.flagNames[protoId]
		if cached ~= nil then
			return cached or nil
		end
		local result = false
		local p = chunk.protos[protoId]
		local ok, insns = pcall(Lifter.decodeProto, chunk, p)
		if ok then
			local lastString
			for _, ins in insns do
				if ins.op == OP.LOADK then
					local k = p.k[ins.d]
					lastString = k and k.t == "string" and k.v or lastString
				elseif ins.op == OP.NAMECALL then
					local k = p.k[ins.aux]
					local prefix = k and k.t == "string" and FLAG_METHODS[k.v]
					local word = prefix and cleanWord(lastString)
					if word then
						result = prefix .. upperFirst(word)
						break
					end
				end
			end
		end
		ctx.flagNames[protoId] = result
		return result or nil
	end

	local LOOKUP_FUNCTIONS = {
		get = true, load = true, require = true, import = true, fetch = true, find = true, wait = true,
		getmodule = true, loadmodule = true, legacyload = true, getservice = true, use = true, module = true,
	}
	local STRING_TRANSFORMS = { lower = true, upper = true, gsub = true, reverse = true, trim = true }

	local function isLookupName(fname)
		if type(fname) ~= "string" then
			return false
		end
		local lowered = string.lower((string.gsub(fname, "^_+", "")))
		return LOOKUP_FUNCTIONS[lowered] or string.find(lowered, "^get") ~= nil or string.find(lowered, "^find") ~= nil
			or string.find(lowered, "^load") ~= nil or string.find(lowered, "^fetch") ~= nil or string.find(lowered, "require") ~= nil
	end

	-- * the last part of a path-like string, if it can be a name: "StreamingAPI/StreamingIdRemoved" -> "StreamingIdRemoved"
	local function lookupName(str)
		if type(str) ~= "string" or #str > 60 then
			return nil
		end
		local last = string.match(str, "([^/\\%.:]+)$")
		if not last or not string.find(last, "^[%a_][%w_]*$") then
			return nil
		end
		return last
	end

	-- * the last constant string argument that can be a name
	local function lookupNameInArgs(args)
		for n = #args, 1, -1 do
			local x = args[n]
			if x.k == "const" then
				local str = x.str or (x.value and x.value.t == "string" and x.value.v)
				local name = str and lookupName(str)
				if name then
					return name
				end
			end
		end
		return nil
	end

	-- * names that say nothing about what a variable holds
	local GENERIC_NAMES = {
		value = true, arg = true, data = true, text = true, tbl = true, list = true, object = true, flag = true,
		result = true, callback = true, condition = true, key = true, count = true, message = true, lookup = true,
		module = true, instance = true, vector = true, i = true, j = true, k = true, _ = true,
	}
	local function isGenericName(name)
		local base = string.match(name, "^(.-)_?%d*$")
		return GENERIC_NAMES[base] or GENERIC_NAMES[name] or string.find(name, "^arg%d+$") ~= nil
	end
	local function plural(word)
		if string.find(word, "[^aeiou]y$") then
			return string.sub(word, 1, -2) .. "ies"
		elseif string.find(word, "[sxz]$") or string.find(word, "[cs]h$") then
			return word .. "es"
		end
		return word .. "s"
	end
	-- * "deep_copy" -> "copy", "GetMoveVector" -> "vector"
	local function lastWord(name)
		local snake = string.match(name, "_([%a][%w]*)$")
		if snake then
			return snake
		end
		local camelWord = string.match(name, "%l(%u[%l%d]+)$")
		if camelWord then
			return string.lower(string.sub(camelWord, 1, 1)) .. string.sub(camelWord, 2)
		end
		return name
	end

	local RETURN_VERBS = { "Get", "Select", "Find", "Choose", "Pick", "Calculate", "Compute", "Create", "Make", "Build", "Load", "Fetch" }

	-- * Chooses every variable name of one function. Returns names (web -> name), the
	-- * parameter names in order, and whether the function is printed as `function T:m()`.
	local function chooseNames(A, p, root, materialized, upnames, hints, ctx, chunk, protoId)
		hints = hints or {}
		local isMethod = false
		local recs, order = {}, {}
		local function rec(w)
			local r = recs[w]
			if not r then
				r = { w = w, defs = {}, fields = {}, methods = {}, stores = {}, reads = 0 }
				recs[w] = r
				order[#order + 1] = r
			end
			return r
		end

		local function pathOf(e)
			if e.k == "global" then
				return e.name
			elseif e.k == "index" and e.key.str then
				local base = pathOf(e.obj)
				return base and base .. "." .. e.key.str
			end
			return nil
		end

		-- * facts about how each variable is used
		local function scan(e)
			forEachExpr(e, function(x)
				local k = x.k
				if k == "var" then
					rec(x.w).reads += 1
				elseif k == "index" then
					if x.obj.k == "var" then
						local r = rec(x.obj.w)
						if x.key.str then
							r.fields[x.key.str] = true
						else
							r.indexed = true
						end
					end
					if not x.key.str and x.key.k == "var" then
						rec(x.key.w).usedAsKey = true
					end
				elseif k == "method" then
					if x.obj.k == "var" then
						local r = rec(x.obj.w)
						r.methods[x.name] = true
						local a1 = x.args[1]
						if x.name == "IsA" and constStr(a1) then
							r.isA = r.isA or constStr(a1)
						elseif (CHILD_BY_NAME[x.name] or CHILD_BY_CLASS[x.name])
							and (constStr(a1) == "Humanoid" or constStr(a1) == "HumanoidRootPart")
						then
							r.hasHumanoid = true
						end
					end
					-- * functions handed to Roblox get the parameter names Roblox uses
					local fnArg
					if (x.name == "Connect" or x.name == "Once" or x.name == "ConnectParallel") and x.args[1] then
						fnArg = x.args[1]
						if fnArg.k == "closure" then
							local event = x.obj.k == "index" and x.obj.key.str
							fnArg.hints = { params = event and EVENT_PARAMS[event], eventName = event or nil }
						end
					elseif (x.name == "catch" or x.name == "Catch") and x.args[1] and x.args[1].k == "closure" then
						x.args[1].hints = { params = { "err" } }
					elseif x.name == "BindToRenderStep" and x.args[3] and x.args[3].k == "closure" then
						x.args[3].hints = { params = { "deltaTime" } }
					elseif (x.name == "BindAction" or x.name == "BindActionAtPriority") and x.args[2] and x.args[2].k == "closure" then
						x.args[2].hints = { params = { "actionName", "inputState", "inputObject" } }
					end
				elseif k == "call" then
					if x.fn.k == "var" then
						rec(x.fn.w).called = true
					end
					local path = pathOf(x.fn)
					local a1 = x.args[1]
					if a1 and a1.k == "var" then
						local r = rec(a1.w)
						if path == "ipairs" or path == "table.insert" or path == "table.remove" or path == "table.sort"
							or path == "table.concat" or path == "table.find" or path == "table.clear" or path == "unpack"
							or path == "table.unpack"
						then
							r.list = true
						elseif path == "pairs" or path == "next" then
							r.map = true
						elseif path == "require" then
							r.module = true
						end
					end
					if path == "table.insert" and a1 and a1.k == "var" then
						local item = x.args[#x.args]
						if #x.args >= 2 and item.k == "var" then
							local holder = rec(a1.w)
							holder.storedVars = holder.storedVars or {}
							holder.storedVars[#holder.storedVars + 1] = item.w
						end
					end
					if path == "table.sort" and x.args[2] and x.args[2].k == "closure" then
						x.args[2].hints = { params = { "a", "b" } }
					elseif path == "xpcall" and x.args[2] and x.args[2].k == "closure" then
						x.args[2].hints = { params = { "err" } }
					end
				elseif k == "binop" then
					for _, side in { x.l, x.r } do
						if side.k == "var" then
							if x.op == "+" or x.op == "-" or x.op == "*" or x.op == "/" or x.op == "%" or x.op == "^" or x.op == "//" then
								rec(side.w).numeric = true
							end
						end
					end
				elseif k == "unop" and x.op == "#" and x.e.k == "var" then
					rec(x.e.w).list = true
				elseif k == "concat" then
					for _, part in x.list do
						if part.k == "var" then
							rec(part.w).text = true
						end
					end
				elseif k == "closure" then
					for _, cap in x.caps do
						if type(cap) == "table" then
							rec(cap.w).reads += 1
						end
					end
				end
			end)
		end

		-- * parameters first, in order
		local paramRecs = {}
		for r = 0, p.numparams - 1 do
			local w = A.webOf(A.paramDefs[r])
			paramRecs[r + 1] = rec(w)
			paramRecs[r + 1].param = r + 1
			paramRecs[r + 1].block = root
			paramRecs[r + 1].index = 0
		end

		local returnedFromMain = {}
		local function walk(block)
			for i, st in block.stmts do
				local k = st.k
				-- * blocks inside this statement: where they sit, for scope checks
				local a, b = childBlocks(st)
				for _, child in { a or false, b or false } do
					if child then
						child.nameParent, child.nameIndex = block, i
					end
				end
				if k == "local" then
					local r = rec(st.w)
					if not r.block then
						r.block, r.index = block, i
					end
				elseif k == "assign" then
					local n = #st.targets
					local nv = #st.values
					for t, target in st.targets do
						if target.k == "var" then
							local r = rec(target.w)
							if not r.block then
								r.block, r.index = block, i
							end
							local def
							if nv >= n then
								def = { e = st.values[t], pos = 1, count = 1 }
							elseif t >= nv then
								def = { e = st.values[nv], pos = t - nv + 1, count = n - nv + 1 }
							else
								def = { e = st.values[t], pos = 1, count = 1 }
							end
							def.multi = n > 1
							r.defs[#r.defs + 1] = def
							local e = def.e
							if def.pos == 2 and e.k == "call" and pathOf(e.fn) == "pcall" and e.args[1] and e.args[1].k == "closure" then
								r.flag = flagNameOfProto(chunk, e.args[1].child, ctx)
							end
						else
							scan(target)
							if target.k == "index" and target.obj.k == "var" then
								local owner = rec(target.obj.w)
								local value = st.values[t]
								if value and target.key.str then
									if target.key.str == "__index" and value.k == "var" and value.w == target.obj.w then
										owner.isClass = true
									elseif value.k == "closure" then
										owner.hasFunctions = true
									end
								end
							end
							local value = st.values[t]
							if value and value.k == "var" and target.k == "index" and not target.key.str and target.obj.k == "var" then
								local holder = rec(target.obj.w)
								holder.storedVars = holder.storedVars or {}
								holder.storedVars[#holder.storedVars + 1] = value.w
							end
							if value and value.k == "var" and target.k == "index" and target.key.str then
								local r = rec(value.w)
								r.stores[#r.stores + 1] = target.key.str
							end
							if value and value.k == "closure" and target.k == "index" and target.key.str then
								local key = target.key.str
								if key == "OnServerInvoke" then
									value.hints = { params = { "player" } }
								elseif key == "ProcessReceipt" then
									value.hints = { params = { "receiptInfo" } }
								end
							end
						end
					end
					for _, v in st.values do
						scan(v)
					end
				elseif k == "call" then
					scan(st.expr)
				elseif k == "return" then
					for _, v in st.values do
						scan(v)
						if v.k == "var" then
							rec(v.w).returned = true
							if block == root then
								returnedFromMain[v.w] = true
							end
						end
					end
				elseif k == "if" then
					scan(st.cond)
					walk(st.thenB)
					if st.elseB then
						walk(st.elseB)
					end
				elseif k == "while" then
					if st.cond then
						scan(st.cond)
					end
					walk(st.body)
				elseif k == "repeat" then
					walk(st.body)
					if st.untilCond then
						scan(st.untilCond)
					end
				elseif k == "numfor" then
					scan(st.init)
					scan(st.limit)
					scan(st.step)
					local r = rec(st.var)
					r.block, r.index = st.body, 0
					r.numfor = true
					walk(st.body)
				elseif k == "genfor" then
					for _, v in st.exprs do
						scan(v)
					end
					for n, w in st.vars do
						local r = rec(w)
						r.block, r.index = st.body, 0
						r.genfor = st
						r.genforIndex = n
					end
					walk(st.body)
				end
			end
		end
		walk(root)

		local names = {}
		local baseOfName = {} -- * "angle3" -> "angle" for names that got a number to be unique
		local function nameOf(w)
			local n = names[w]
			return n and (baseOfName[n] or n)
		end
		local reserved = {}
		for name in NAME_KEYWORDS do
			reserved[name] = true
		end
		for name in ctx.allGlobals do
			reserved[name] = true
		end
		for name in BUILTIN_NAMES do
			if name ~= "self" then
				reserved[name] = true
			end
		end
		for _, name in upnames do
			if type(name) == "string" then
				reserved[name] = true
			end
		end
		-- * names of enclosing functions: not reused (no shadowing), except for a real name from
		-- * debug info, which is what the original wrote
		local outerReserved = {}
		for _, outer in ctx.outerNames do
			for name in outer do
				-- * `_` only ever names variables nothing reads, so reusing it hides nothing
				if name ~= "_" then
					outerReserved[name] = true
				end
			end
		end

		-- * a noun for an expression, for building names from it
		local valueName
		local function nounOf(e)
			if not e then
				return nil
			end
			local k = e.k
			if k == "var" then
				return nameOf(e.w)
			elseif k == "upval" or k == "global" then
				return isIdent(e.name) and e.name or nil
			elseif k == "index" then
				return e.key.str and cleanWord(e.key.str)
			elseif k == "call" or k == "method" then
				return (valueName(e, 1, 1))
			end
			return nil
		end

		local function nameFromFunctionName(fname, fallbackScore)
			if not fname then
				return nil
			end
			fname = string.gsub(fname, "^_+", "")
			if fname == "" then
				return nil
			end
			-- * what it is, not where it comes from: drop `_from_config`, `ForPlayer`, `_by_id`
			local function trimmed(name)
				local short = string.match(name, "^(.-)_from_[%w_]+$")
					or string.match(name, "^(.-)_by_[%w_]+$")
					or string.match(name, "^(.-)_for_[%w_]+$")
				if short and #short >= 2 then
					return short
				end
				short = string.match(name, "^(.-)From%u%w*$") or string.match(name, "^(.-)For%u%w*$") or string.match(name, "^(.-)By%u%w*$")
				if short and #short >= 2 then
					return short
				end
				return name
			end
			local snakeRest = string.match(fname, "^[Gg]et_([%a][%w_]*)$")
			if snakeRest then
				return trimmed(snakeRest), 2
			end
			if string.find(fname, "^is_%a") or string.find(fname, "^has_%a") or string.find(fname, "^can_%a") or string.find(fname, "^should_%a") then
				return fname, 2
			end
			for _, verb in { "find", "load", "create", "make", "build", "calculate", "compute", "fetch", "read", "generate", "new", "wait", "select", "await", "promise" } do
				snakeRest = string.match(fname, "^" .. verb .. "_([%a][%w_]*)$")
				if snakeRest then
					return trimmed(snakeRest), 1.5
				end
			end
			local rest = string.match(fname, "^[Gg]et(%u%w*)$")
			if rest then
				return camel(trimmed(rest)), 2
			end
			if string.find(fname, "^[IiHhCcSs][a-z]+%u") and (string.find(fname, "^[Ii]s%u") or string.find(fname, "^[Hh]as%u")
				or string.find(fname, "^[Cc]an%u") or string.find(fname, "^[Ss]hould%u"))
			then
				return camel(fname), 2
			end
			for _, verb in { "Find", "Load", "Create", "Make", "Build", "Calculate", "Compute", "Fetch", "Read", "Generate", "New", "Wait", "Select", "Choose", "Pick" } do
				rest = string.match(fname, "^" .. verb .. "(%u%w*)$") or string.match(fname, "^" .. string.lower(verb) .. "(%u%w*)$")
				if rest then
					return camel(rest), 1.5
				end
			end
			-- * `name_from_source` returns a name
			local short = trimmed(fname)
			if short ~= fname and camel(short) and not NAME_KEYWORDS[camel(short)] and not BUILTIN_NAMES[camel(short)] then
				return camel(short), 1
			end
			local base = camel(fname)
			if not base then
				return nil
			end
			local word = lastWord(base)
			if NAME_KEYWORDS[word] or BUILTIN_NAMES[word] or #word < 2 then
				word = base
			end
			if NAME_KEYWORDS[word] or BUILTIN_NAMES[word] then
				return "result", fallbackScore or 0.3
			end
			return word, fallbackScore or 0.3
		end

		local function fromList(v, pos)
			if type(v) == "table" then
				return v[pos]
			end
			return pos == 1 and v or nil
		end

		function valueName(e, pos, count)
			local k = e.k
			if k == "closure" then
				local child = chunk.protos[e.child]
				if child.debugname and isIdent(child.debugname) then
					return child.debugname, 5
				end
				if e.hints and e.hints.eventName then
					return "on" .. upperFirst(e.hints.eventName), 2
				end
				return "callback", 0.5
			elseif k == "method" then
				local m = e.name
				local a1 = e.args[1]
				local str = constStr(a1)
				if (m == "GetService" or m == "FindService") and str then
					return cleanWord(str), 4
				elseif CHILD_BY_NAME[m] and str then
					return camel(str), 3
				elseif CHILD_BY_CLASS[m] and str then
					return camel(str), 3
				elseif FLAG_METHODS[m] and str and cleanWord(str) then
					return FLAG_METHODS[m] .. upperFirst(cleanWord(str)), 4
				elseif m == "GetAttribute" and str then
					return camel(str), 3
				elseif (m == "GetPropertyChangedSignal" or m == "GetAttributeChangedSignal") and str and camel(str) then
					return camel(str) .. "Changed", 2
				elseif m == "GetUserCFrame" and a1 and a1.k == "index" and a1.key.str then
					return camel(a1.key.str) .. "CFrame", 2.5
				elseif (m == "Wait" or m == "wait") and e.obj.k == "index" and e.obj.key.str then
					local params = EVENT_PARAMS[e.obj.key.str]
					local name = params and params[pos]
					if name then
						return name, 3
					end
					return nil
				elseif (m == "Connect" or m == "Once") and e.obj.k == "index" and e.obj.key.str and camel(e.obj.key.str) then
					return camel(e.obj.key.str) .. "Connection", 2
				elseif m == "Clone" then
					local noun = nounOf(e.obj)
					return noun and camel(noun) or "clone", 1.5
				elseif m == "IsA" and str and cleanWord(str) then
					return "is" .. upperFirst(cleanWord(str)), 2
				elseif STRING_TRANSFORMS[m] and pos == 1 and nounOf(e.obj) and camel(nounOf(e.obj)) then
					return camel(nounOf(e.obj)), 1.5
				elseif pos == 1 and isLookupName(m) and not METHOD_RESULTS[m] and lookupNameInArgs(e.args) then
					return lookupNameInArgs(e.args), 2.5
				elseif m == "format" then
					return "text", 0.5
				elseif METHOD_RESULTS[m] then
					local name = fromList(METHOD_RESULTS[m], pos)
					if name then
						return name, 2
					end
					return nil
				end
				local name, score = nameFromFunctionName(m)
				if pos > 1 and name then
					return name .. pos, score * 0.5
				end
				return name, score
			elseif k == "call" then
				local path = pathOf(e.fn)
				local a1 = e.args[1]
				if path == "require" and a1 then
					local name
					if a1.k == "method" and CHILD_BY_NAME[a1.name] and constStr(a1.args[1]) then
						name = cleanWord(constStr(a1.args[1]))
					elseif a1.k == "index" and a1.key.str then
						name = cleanWord(a1.key.str)
					elseif a1.k == "var" then
						name = names[a1.w]
					elseif a1.k == "upval" then
						name = isIdent(a1.name) and a1.name or nil
					elseif constStr(a1) then
						local last = string.match(constStr(a1), "([^/\\]+)$")
						last = last and string.match(last, "^[^%.]+")
						name = last and cleanWord(last)
						name = name and upperFirst(name)
					end
					return name or "module", name and 4 or 1
				elseif path == "setmetatable" then
					return "object", 1
				elseif path == "Instance.new" and constStr(a1) then
					return camel(constStr(a1)), 3
				elseif path and CALL_RESULTS[path] then
					local name = fromList(CALL_RESULTS[path], pos)
					if name then
						return name, path == "pcall" and 3 or 1
					end
					return nil
				end
				local calleeName = (e.fn.k == "var" and nameOf(e.fn.w)) or ((e.fn.k == "upval" or e.fn.k == "global") and e.fn.name)
					or (e.fn.k == "index" and e.fn.key.str)
				local looked = pos == 1 and lookupName(constStr(a1))
				if pos == 1 and isLookupName(calleeName) and lookupNameInArgs(e.args) and not CALL_RESULTS[pathOf(e.fn) or ""] then
					return lookupNameInArgs(e.args), 2.5
				end
				if looked and type(calleeName) == "string" then
					local lowered = string.lower(calleeName)
					if LOOKUP_FUNCTIONS[lowered] or string.find(lowered, "load") or string.find(lowered, "require") then
						return looked, 2.5
					end
					if (e.fn.k == "var" or e.fn.k == "upval") and string.find(looked, "^%u") then
						return looked, 2.2
					end
				end
				if e.fn.k == "var" or e.fn.k == "upval" then
					local fname = e.fn.k == "var" and names[e.fn.w] or e.fn.name
					if fname and isIdent(fname) then
						local name, score = nameFromFunctionName(fname)
						if pos > 1 and name then
							return name .. pos, score * 0.5
						end
						return name, score
					end
				elseif e.fn.k == "index" and e.fn.key.str then
					local key = e.fn.key.str
					if key == "new" or key == "New" or key == "create" or key == "Create" then
						local noun = nounOf(e.fn.obj)
						if noun and camel(noun) then
							return camel(noun), 2
						end
					end
					return nameFromFunctionName(key)
				end
				return nil
			elseif k == "index" then
				local key = e.key.str
				if key then
					local path = pathOf(e.obj)
					if path and string.sub(path, 1, 5) == "Enum." then
						return camel(string.match(path, "^Enum%.([%w_]+)")), 1
					end
					if FIELD_RESULTS[key] then
						return FIELD_RESULTS[key], 2.5
					end
					if PREFIXED_FIELDS[key] then
						local noun = e.obj.k == "var" and names[e.obj.w]
						if noun and #noun + #key <= 28 then
							return noun .. key, 2
						end
					end
					local obj = e.obj
					local fromModule = obj.k == "call" and pathOf(obj.fn) == "require"
					if not fromModule then
						local objName = (obj.k == "var" and names[obj.w]) or ((obj.k == "upval" or obj.k == "global") and obj.name)
						fromModule = type(objName) == "string" and string.find(objName, "^%u%l") ~= nil
					end
					if fromModule and string.find(key, "^%u") and cleanWord(key) then
						return cleanWord(key), 2
					end
					local name = camel(key)
					if name and (BUILTIN_NAMES[name] or NAME_KEYWORDS[name]) then
						local noun = camel(nounOf(obj))
						name = noun and #noun + #name <= 28 and noun .. upperFirst(name) or nil
					end
					return name, 2
				end
				local noun = nounOf(e.obj)
				local element = elementName(noun)
				if element then
					return element, 2
				end
				return nil
			elseif k == "table" then
				if #e.entries == 0 then
					return "tbl", 0.1
				end
				local keyed, stringKeyed = false, true
				for _, entry in e.entries do
					if entry.key then
						keyed = true
						if not entry.key.str then
							stringKeyed = false
						end
					end
				end
				if not keyed then
					return "list", 0.5
				end
				return stringKeyed and "data" or "lookup", 0.5
			elseif k == "const" then
				if e.text == "true" or e.text == "false" then
					return "flag", 0.1
				elseif constStr(e) then
					return "text", 0.1
				elseif e.text ~= "nil" then
					return "value", 0.1
				end
				return nil
			elseif k == "binop" then
				if e.op == "==" or e.op == "~=" or e.op == "<" or e.op == "<=" then
					return "condition", 0.2
				end
				local function isPosition(x)
					return x.k == "index" and (x.key.str == "Position" or x.key.str == "p")
				end
				if e.op == "-" and isPosition(e.l) and isPosition(e.r) then
					return "offset", 0.6
				end
				-- * named after its leftmost operand that has a name
				for _, side in { e.l, e.r } do
					if side.k ~= "const" then
						local noun = valueName(side, 1, 1)
						if noun then
							return noun, 0.3
						end
					end
				end
				return nil
			elseif k == "and" or k == "or" then
				if e.r.k == "var" and recs[e.r.w] and recs[e.r.w].flag then
					return recs[e.r.w].flag, 3.5
				end
				local noun = (e.r.k == "var" and nameOf(e.r.w)) or nounOf(e.r) or nounOf(e.l)
				return camel(noun), 0.3
			elseif k == "not" then
				return "condition", 0.2
			elseif k == "unop" then
				if e.op == "#" then
					return "count", 1
				end
				return (valueName(e.e, 1, 1)), 0.3
			elseif k == "concat" then
				return "text", 0.5
			elseif k == "var" then
				return nameOf(e.w), 0.2
			elseif k == "upval" or k == "global" then
				return camel(e.name), 0.2
			elseif k == "vararg" then
				return count > 1 and ("arg" .. pos) or "args", 0.5
			elseif k == "ifexpr" then
				local a, sa = valueName(e.a, pos, count)
				local b, sb = valueName(e.b, pos, count)
				if a and (not b or sa >= sb) then
					return a, sa
				end
				return b, sb
			end
			return nil
		end

		local function usageName(r)
			local best, bestScore
			local function offer(name, score)
				if name and (not bestScore or score > bestScore) then
					best, bestScore = name, score
				end
			end
			if r.storedVars then
				for _, item in r.storedVars do
					local itemName = nameOf(item)
					if itemName and not isGenericName(itemName) and #itemName <= 24 then
						offer(plural(itemName), 1)
						break
					end
				end
			end
			if r.usedAsKey then
				offer("key", 0.6)
			end
			for _, key in r.stores do
				if not string.find(key, "^__") then
					offer(camel(key), 1.5)
					break
				end
			end
			if r.isA then
				offer(camel(r.isA), 1.2)
			end
			if r.hasHumanoid then
				offer("character", 1.2)
			end
			for field in r.fields do
				local kind = FIELD_KINDS[field]
				if kind then
					offer(kind, FIELD_KIND_SCORE[kind])
				end
			end
			if r.methods.Disconnect then
				offer("connection", 1)
			end
			if r.methods.Connect or r.methods.Wait then
				offer("signal", 1)
			end
			if r.methods.FireServer or r.methods.FireAllClients or r.methods.FireClient then
				offer("remote", 1)
			end
			if r.methods.InvokeServer or r.methods.InvokeClient then
				offer("remote", 1)
			end
			if r.methods.LoadAnimation then
				offer("humanoid", 0.8)
			end
			if r.called then
				offer("callback", 0.6)
			end
			if r.list then
				offer("list", 0.8)
			end
			if r.map then
				offer("tbl", 0.4)
			end
			if r.module then
				offer("module", 0.8)
			end
			if r.text then
				offer("text", 0.5)
			end
			if r.methods.Destroy or r.methods.FindFirstChild or r.methods.WaitForChild or r.methods.GetChildren
				or r.fields.Parent or r.fields.Name or r.fields.ClassName
			then
				offer("instance", 0.4)
			end
			if r.fields.Magnitude or r.fields.Unit or r.fields.magnitude or r.fields.unit then
				offer("vector", 0.5)
			end
			if r.fields.X or r.fields.Y or r.fields.Z then
				offer("vector", 0.3)
			end
			if r.numeric then
				offer("value", 0.2)
			end
			return best, bestScore
		end

		-- * the function's own name says what its parameters are: `OnCharacterAdded(character)`,
		-- * `SetEnabled(enabled)`
		local fname = p.debugname
		local fnameParams
		if fname then
			local event = string.match(fname, "^On(%u%w*)$")
			if event then
				fnameParams = EVENT_PARAMS[event] or EVENT_PARAMS[string.match(event, "^%u%l+(%u%w*)$") or ""]
			end
			local set = string.match(fname, "^Set(%u%w*)$")
			if set and camel(set) then
				fnameParams = { camel(set) }
			end
		end

		-- * `NormalizeAngle` -> its parameter is an angle
		local fnameNoun = fname and string.match(fname, "^%a%l+(%u%l+)$")
		fnameNoun = fnameNoun and camel(fnameNoun)
		if not fnameNoun and fname then
			fnameNoun = string.match(fname, "_by_(%a[%w]*)$") or string.match(fname, "^[%l]+_for_(%a[%w]*)$")
		end
		if fnameNoun and (NAME_KEYWORDS[fnameNoun] or BUILTIN_NAMES[fnameNoun]) then
			fnameNoun = nil -- * `guardReturn` says nothing about its parameter
		end

		-- * the module's class / table, named after the script
		local className
		if protoId == chunk.main and ctx.options.scriptName then
			className = cleanWord(ctx.options.scriptName)
			if className then
				className = upperFirst(className)
			end
		end
		local classTaken = false
		local classOwner
		if className then
			for w in returnedFromMain do
				local r = recs[w]
				if r then
					for _, def in r.defs do
						if def.e.k == "table" then
							classOwner = w
						end
					end
				end
			end
		end

		local function candidate(r)
			local best, bestScore
			local function offer(name, score)
				if name and score and (not bestScore or score > bestScore) then
					best, bestScore = name, score
				end
			end
			-- * real names, when the script was compiled with them (-g2)
			if p.locvars then
				for _, id in r.w.defs do
					local info = A.defInfo[id]
					local at = info.ins and (info.ins.pc + (info.ins.size or 1)) or 0
					if info.ins and info.ins.captures then
						at += #info.ins.captures -- * a closure's local starts after its CAPTUREs
					end
					for _, lv in p.locvars do
						local covers = lv.startpc <= at and at <= lv.endpc
						if info.kind == "loopvar" and info.ins and info.ins.target then
							-- * a loop variable's range is the loop body
							covers = lv.startpc <= at and lv.endpc >= info.ins.target
						end
						if lv.reg == info.reg and covers and lv.name and isIdent(lv.name) then
							offer(lv.name, 10)
						end
					end
				end
			end
			if r.param then
				local index = r.param - (hints.methodSelf and 1 or 0)
				local hinted = hints.params and hints.params[index]
				if hinted then
					offer(hinted, 4)
				end
				local fromName = fnameParams and fnameParams[index]
				if fromName then
					offer(fromName, 3)
				end
				local count = p.numparams - (hints.methodSelf and 1 or 0)
				if fnameNoun and count == 1 then
					offer(fnameNoun, 1)
				elseif fnameNoun and count == 2 and index >= 1 then
					offer(fnameNoun .. (index == 1 and "A" or "B"), 1)
				end
			end
			if r.numfor then
				offer("i", 1)
			end
			if r.genfor then
				local st, n = r.genfor, r.genforIndex
				local iter = st.exprs[1]
				local container, kind = iter, nil
				if iter and iter.k == "call" then
					local path = pathOf(iter.fn)
					if path == "pairs" or path == "ipairs" or path == "next" then
						container, kind = iter.args[1], path
					end
				elseif iter and iter.k == "global" and iter.name == "next" then
					container, kind = st.exprs[2], "pairs"
				end
				if n == 1 then
					if kind == "ipairs" then
						offer("i", 1)
					else
						local noun = container and nounOf(container)
						if container and container.k == "method" and (container.name == "GetChildren" or container.name == "GetDescendants" or container.name == "GetPlayers") then
							offer("i", 1)
						elseif noun and elementName(noun) and string.find(noun, "s$") then
							offer("i", 0.8)
						else
							offer("key", 1)
						end
					end
				elseif n == 2 then
					local element = container and elementName(nounOf(container))
					offer(element, 2)
					offer("value", 0.5)
				else
					offer("value" .. n, 0.5)
				end
			end
			for _, def in r.defs do
				local name, score = valueName(def.e, def.pos, def.count)
				local isCopy = def.e.k == "var" or def.e.k == "upval" or def.e.k == "global"
				if not (isCopy and #r.defs > 1) then
					offer(name, score)
				end
				-- * `local self = setmetatable({}, Class) ... return self` in a constructor
				if def.e.k == "call" and pathOf(def.e.fn) == "setmetatable" and r.returned and not isMethod then
					offer("self", 3)
				end
			end
			offer(usageName(r))
			if r.isClass then
				offer("Class", 1)
			end
			if className and not classTaken and (r.isClass or r.hasFunctions or returnedFromMain[r.w]) and (classOwner == nil or classOwner == r.w) then
				for _, def in r.defs do
					if def.e.k == "table" then
						offer(className, 6)
						break
					end
				end
			end
			if r.returned and fname then
				for _, verb in RETURN_VERBS do
					local rest = string.match(fname, "^" .. verb .. "(%u%w*)$") or string.match(fname, "^" .. string.lower(verb) .. "(%u%w*)$")
					if rest then
						offer(camel(rest), 1.2)
						break
					end
				end
			end
			if not best then
				if r.param and next(r.methods) then
					best = "object"
				elseif r.param then
					-- * nothing says what it is: named by position (`arg1`)
					best = "arg" .. (r.param - (hints.methodSelf and 1 or 0))
				else
					local fromCall = false
					for _, def in r.defs do
						if def.e.k == "call" or def.e.k == "method" then
							fromCall = true
						end
					end
					best = fromCall and "result" or "value"
				end
			end
			if best == className then
				classTaken = true
			end
			return best, bestScore or 0
		end

		-- * unique within every scope that can see it
		local taken = {}
		-- * index, in `outer`, of the statement that contains `block` (nil if it is not inside)
		local function positionIn(outer, block)
			local index
			while block and block ~= outer do
				index = block.nameIndex
				block = block.nameParent
			end
			if block == outer then
				return index or 0
			end
			return nil
		end
		-- * does a variable declared at (block1, index1) see one declared at (block2, index2), or the reverse?
		local function overlaps(block1, index1, block2, index2)
			if block1 == block2 then
				return true
			end
			local at = positionIn(block1, block2)
			if at then
				return at >= index1
			end
			at = positionIn(block2, block1)
			if at then
				return at >= index2
			end
			return false
		end
		local allowShadowing = false
		local function isFree(name, block, index)
			if reserved[name] or not isIdent(name) or (outerReserved[name] and not allowShadowing) then
				return false
			end
			local list = taken[name]
			if list then
				for _, other in list do
					if overlaps(other.block, other.index, block, index or 0) then
						return false
					end
				end
			end
			return true
		end
		local LETTERS = { i = { "j", "k", "l", "m", "n" } }
		local function claim(base, block, index)
			local name = base
			if not isFree(name, block, index) then
				name = nil
				for _, alt in LETTERS[base] or {} do
					if isFree(alt, block, index) then
						name = alt
						break
					end
				end
				if not name then
					local n = 2
					while not isFree((string.find(base, "%d$") and base .. "_" or base) .. n, block, index) do
						n += 1
					end
					name = (string.find(base, "%d$") and base .. "_" or base) .. n
					baseOfName[name] = base
				end
			end
			local list = taken[name]
			if not list then
				list = {}
				taken[name] = list
			end
			list[#list + 1] = { block = block, index = index or 0 }
			return name
		end

		-- * `self`: the first parameter of a method
		if hints.method and paramRecs[1] and not reserved.self then
			local first = paramRecs[1]
			local usedAsObject = next(first.fields) ~= nil or next(first.methods) ~= nil or first.indexed
			if hints.method == "namecall" or usedAsObject or first.reads == 0 then
				isMethod = true
				names[first.w] = "self"
				taken.self = { { block = root, index = 0 } }
				hints.methodSelf = true
			end
		end

		local deferred = {}
		for _, r in order do
			if not r.param and (materialized[r.w]) and not names[r.w] then
				local _, score = candidate(r)
				if score < 1 then
					deferred[r] = true
				end
			end
		end
		local passes = { {}, {} }
		for _, r in order do
			local list = deferred[r] and passes[2] or passes[1]
			list[#list + 1] = r
		end
		classTaken = false
		for _, r in table.move(passes[2], 1, #passes[2], #passes[1] + 1, passes[1]) do
			local w = r.w
			if not names[w] and (materialized[w] or r.param) then
				local multiTarget = false
				for _, def in r.defs do
					if def.multi then
						multiTarget = true
					end
				end
				if r.reads == 0 and not w.captured and not r.param and (r.genfor or multiTarget) and not reserved._ then
					names[w] = "_"
				else
					local block = r.block or root
					local index = r.block and r.index or 0
					local base, score = candidate(r)
					allowShadowing = score >= 10
					-- * a weak guess borrowed from a numbered name (`r01`, `result2`) that is already
					-- * taken would only read as a typo (`r01_2`)
					local argIndex = r.param and tonumber(string.match(base, "^arg(%d+)$"))
					if argIndex then
						-- * `arg2` taken by an enclosing function: the next free number, never `arg2_2`
						while not isFree("arg" .. argIndex, block, index) do
							argIndex += 1
						end
						base = "arg" .. argIndex
					elseif score < 1 and string.find(base, "%d$") and not isFree(base, block, index) then
						base = "value"
					end
					names[w] = claim(base, block, index)
					allowShadowing = false
				end
			end
		end

		local classWebs = {}
		for _, r in order do
			if r.isClass then
				classWebs[r.w] = true
			end
		end

		local params = {}
		for n, r in paramRecs do
			if not (isMethod and n == 1) then
				params[#params + 1] = names[r.w]
			end
		end
		if p.isvararg then
			params[#params + 1] = "..."
		end
		return names, params, isMethod, classWebs
	end

	local function onlyReadsLocals(e)
		local k = e.k
		if k == "const" or k == "var" or k == "upval" then
			return true
		elseif k == "and" or k == "or" then
			return onlyReadsLocals(e.l) and onlyReadsLocals(e.r)
		elseif k == "not" then
			return onlyReadsLocals(e.e)
		end
		return false
	end
	local function dropEmptyIfs(block)
		local stmts = block.stmts
		for i = #stmts, 1, -1 do
			local st = stmts[i]
			local a, b = childBlocks(st)
			if a then
				dropEmptyIfs(a)
			end
			if b then
				dropEmptyIfs(b)
			end
			if st.k == "if" and #st.thenB.stmts == 0 and (not st.elseB or #st.elseB.stmts == 0) and onlyReadsLocals(st.cond) then
				remove(stmts, i)
			end
		end
	end

	local LOOP_KINDS = { ["while"] = true, ["repeat"] = true, numfor = true, genfor = true }

	-- * a `break` / `continue` that belongs to this block (not to a loop nested inside it)
	local function exitsBlock(block)
		for _, st in block.stmts do
			if st.k == "break" or st.k == "continue" then
				return true
			end
			if not LOOP_KINDS[st.k] then
				local a, b = childBlocks(st)
				if (a and exitsBlock(a)) or (b and exitsBlock(b)) then
					return true
				end
			end
		end
		return false
	end

	-- * `A or B or true` -> `A or B` when the value is not used (an empty `if`): the same things are
	-- * evaluated in the same order. nil means the whole condition is a constant.
	local function withoutConstantTail(e)
		if e.k == "const" and (e.text == "true" or e.text == "false") then
			return nil
		end
		if e.k == "or" or e.k == "and" then
			local r = withoutConstantTail(e.r)
			if r == nil then
				return withoutConstantTail(e.l)
			end
			return E(e.k, { l = e.l, r = r })
		end
		return e
	end

	-- * readable control flow, same behaviour:
	-- * `repeat ... until true` with nothing that leaves it early is just its body,
	-- * `if c then else x end` is `if not c then x end`,
	-- * `if c or true then end` is `if c then end`
	local function tidyBlocks(block)
		local stmts = block.stmts
		local i = 1
		while i <= #stmts do
			local st = stmts[i]
			local a, b = childBlocks(st)
			if a then
				tidyBlocks(a)
			end
			if b then
				tidyBlocks(b)
			end
			if st.k == "repeat" and st.isBlock and not exitsBlock(st.body) then
				remove(stmts, i)
				for n, inner in st.body.stmts do
					insert(stmts, i + n - 1, inner)
				end
				continue
			end
			if st.k == "if" and #st.thenB.stmts == 0 and st.elseB and #st.elseB.stmts > 0 then
				st.cond = boolNot(st.cond)
				st.thenB, st.elseB = st.elseB, nil
			end
			if st.k == "if" and #st.thenB.stmts == 0 and (not st.elseB or #st.elseB.stmts == 0) then
				local cond = withoutConstantTail(st.cond)
				if cond == nil then
					remove(stmts, i)
					continue
				end
				-- * the jumps of `if c then end` test `not c` (they skip the empty body): print `c`
				st.cond = st.degenerate and boolNot(cond) or cond
			end
			i += 1
		end
	end

	-- * `local x = nil` for a variable nothing ever reads (the declaration of a local that is
	-- * assigned on every path before use) says nothing; leaving it out changes nothing
	local function dropDeadNils(block)
		local stmts = block.stmts
		for i = #stmts, 1, -1 do
			local st = stmts[i]
			if st.k == "assign" and #st.targets == 1 and #st.values == 1 and st.targets[1].k == "var"
				and st.values[1].k == "const" and st.values[1].text == "nil" and #st.targets[1].w.uses == 0
				and not st.targets[1].w.captured and not st.targets[1].w.kinds.param
			then
				remove(stmts, i)
			end
			local a, b = childBlocks(st)
			if a then
				dropDeadNils(a)
			end
			if b then
				dropDeadNils(b)
			end
		end
	end

	-- * names the whole script uses as globals, and method names it calls with `:`
	local function scanChunk(chunk)
		local globals, namecalls, dotReads = {}, {}, {}
		for _, p in chunk.protos do
			local ok, insns = pcall(Lifter.decodeProto, chunk, p)
			if ok then
				local K = p.k
				for _, ins in insns do
					local op = ins.op
					local k
					if op == OP.GETGLOBAL or op == OP.SETGLOBAL then
						k = K[ins.aux]
						if k and k.t == "string" then
							globals[k.v] = true
						end
					elseif op == OP.GETIMPORT then
						k = K[band(rshift(ins.aux, 20), 1023)]
						if k and k.t == "string" then
							globals[k.v] = true
						end
					elseif op == OP.NAMECALL then
						k = K[ins.aux]
						if k and k.t == "string" then
							namecalls[k.v] = true
						end
					elseif op == OP.GETTABLEKS then
						k = K[ins.aux]
						if k and k.t == "string" then
							dotReads[k.v] = true
						end
					end
				end
			end
		end
		return globals, namecalls, dotReads
	end

	--------------------------------------------------------------------------
	-- printing
	--------------------------------------------------------------------------
	local PREC = {
		["or"] = 1, ["and"] = 2,
		["<"] = 3, [">"] = 3, ["<="] = 3, [">="] = 3, ["~="] = 3, ["=="] = 3,
		[".."] = 4, ["+"] = 5, ["-"] = 5, ["*"] = 6, ["/"] = 6, ["//"] = 6, ["%"] = 6,
	}
	local RIGHT = { [".."] = true, ["^"] = true }
	local UNARY_PREC = 7
	PREC["^"] = 8

	local Printer = {}
	Printer.__index = Printer

	local function exprPrec(e)
		local k = e.k
		if k == "binop" then
			return PREC[e.op]
		elseif k == "and" or k == "or" then
			return PREC[k]
		elseif k == "concat" then
			return PREC[".."]
		elseif k == "unop" or k == "not" then
			return UNARY_PREC
		elseif k == "ifexpr" then
			return 0
		elseif k == "const" and e.text:sub(1, 1) == "(" then
			return 10
		elseif k == "closure" or k == "table" or k == "const" or k == "vararg" then
			return 9
		end
		return 10
	end

	local decompileFunction -- forward

	local function reasonText(err)
		local text = string.gsub(tostring(err), "^" .. FAIL, "")
		text = string.gsub(text, "[%c]+", " ")
		if #text > 140 then
			text = string.sub(text, 1, 140) .. "..."
		end
		return text
	end

	function Printer:name(w)
		local n = self.names[w]
		if not n then
			fail("variable without a name")
		end
		return n
	end

	function Printer:expr(e, indent)
		local k = e.k
		if k == "const" then
			return e.text
		elseif k == "var" then
			return self:name(e.w)
		elseif k == "upval" or k == "global" then
			return e.name
		elseif k == "vararg" then
			return "..."
		elseif k == "index" then
			local obj = self:prefix(e.obj, indent)
			if e.key.str and isIdent(e.key.str) then
				return obj .. "." .. e.key.str
			end
			return obj .. "[" .. self:expr(e.key, indent) .. "]"
		elseif k == "call" then
			return self:prefix(e.fn, indent) .. "(" .. self:list(e.args, indent) .. ")"
		elseif k == "method" then
			return self:prefix(e.obj, indent) .. ":" .. e.name .. "(" .. self:list(e.args, indent) .. ")"
		elseif k == "binop" or k == "and" or k == "or" then
			local op = k == "binop" and e.op or k
			local p = PREC[op]
			local l = self:expr(e.l, indent)
			local r = self:expr(e.r, indent)
			local lp, rp = exprPrec(e.l), exprPrec(e.r)
			if lp < p or (lp == p and RIGHT[op]) then
				l = "(" .. l .. ")"
			end
			local sameAssociative = (op == "and" or op == "or") and e.r.k == op
			if rp < p or (rp == p and not RIGHT[op] and not sameAssociative) then
				r = "(" .. r .. ")"
			end
			return l .. " " .. op .. " " .. r
		elseif k == "concat" then
			local parts = {}
			for n, x in e.list do
				local s = self:expr(x, indent)
				local xp = exprPrec(x)
				if xp < PREC[".."] or (xp == PREC[".."] and n < #e.list) then
					s = "(" .. s .. ")"
				end
				parts[n] = s
			end
			return concat(parts, " .. ")
		elseif k == "unop" or k == "not" then
			local op = k == "not" and "not " or e.op
			local inner = self:expr(e.e, indent)
			local ip = exprPrec(e.e)
			if ip < UNARY_PREC or (op == "-" and (inner:sub(1, 1) == "-")) then
				inner = "(" .. inner .. ")"
			end
			return op .. inner
		elseif k == "table" then
			if #e.entries == 0 then
				return "{}"
			end
			local function render(entryIndent)
				local parts = {}
				for n, entry in e.entries do
					local value = entry.value
					-- * `name = function()` needs no `-- name` comment
					if value.k == "closure" and entry.key and entry.key.str and self.chunk.protos[value.child].debugname == entry.key.str then
						value.namedByKey = true
					end
					local v = self:expr(value, entryIndent)
					if entry.key then
						if entry.key.str and isIdent(entry.key.str) then
							parts[n] = entry.key.str .. " = " .. v
						else
							parts[n] = "[" .. self:expr(entry.key, entryIndent) .. "] = " .. v
						end
					else
						if n == #e.entries and (value.k == "call" or value.k == "method" or value.k == "vararg") and not value.multret then
							v = "(" .. v .. ")"
						end
						parts[n] = v
					end
				end
				return parts
			end
			-- * functions and long tables go one entry per line, like hand written code. Functions
			-- * are only printed once (printing one decompiles it).
			local hasFunction = false
			forEachExpr(e, function(x)
				if x.k == "closure" then
					hasFunction = true
				end
			end)
			local fieldLines = {}
			for _, entry in e.entries do
				if entry.line then
					fieldLines[entry.line] = true
				end
			end
			local multiLine = next(fieldLines) ~= nil and next(fieldLines, next(fieldLines)) ~= nil
			if not hasFunction and not multiLine then
				local line = "{ " .. concat(render(indent), ", ") .. " }"
				if #line <= 100 and not string.find(line, "\n", 1, true) then
					return line
				end
			end
			local inner = rep("\t", indent + 1)
			-- * each field on its source line (when it is not earlier than the code around it)
			local marks = {}
			local floor = self.ctx.lineFloor
			for n, entry in e.entries do
				if entry.line and (not floor or entry.line >= floor) then
					marks[n] = "\1" .. entry.line .. "\2"
					floor = entry.line
				end
			end
			local parts = render(indent + 1)
			local lines = {}
			for n, part in parts do
				lines[n] = (marks[n] or "") .. inner .. part .. ","
			end
			if floor then
				self.ctx.lineFloor = floor
			end
			return "{\n" .. concat(lines, "\n") .. "\n" .. rep("\t", indent) .. "}"
		elseif k == "ifexpr" then
			return "if " .. self:expr(e.c, indent) .. " then " .. self:expr(e.a, indent) .. " else " .. self:expr(e.b, indent)
		elseif k == "closure" then
			local upnames = {}
			for n, cap in e.caps do
				upnames[n] = type(cap) == "string" and cap or self:name(cap.w)
			end
			return "function" .. (decompileFunction(self.chunk, e.child, upnames, indent, self.ctx, e.namedByKey, e.hints))
		end
		fail("cannot print " .. tostring(k))
	end

	function Printer:prefix(e, indent)
		local k = e.k
		local s = self:expr(e, indent)
		if k == "var" or k == "upval" or k == "global" or k == "index" or k == "call" or k == "method" then
			return s
		end
		return "(" .. s .. ")"
	end

	-- * a list where only the last element may expand to several values
	function Printer:list(exprs, indent, noExpand)
		local parts = {}
		for n, x in exprs do
			local s = self:expr(x, indent)
			if not noExpand and n == #exprs and (x.k == "call" or x.k == "method" or x.k == "vararg") and not x.multret then
				s = "(" .. s .. ")"
			end
			parts[n] = s
		end
		return concat(parts, ", ")
	end

	function Printer:block(block, indent, out)
		local tab = rep("\t", indent)
		local n = #block.stmts
		local floor = self.ctx.lineFloor
		local function lineMark(line)
			if line and (not floor or line >= floor) then
				floor = line
				return line
			end
			return nil
		end
		for i, st in block.stmts do
			local startIdx = #out + 1
			local markLine = lineMark(st.line)
			self.ctx.lineFloor = floor
			local k = st.k
			local isLast = i == n
			if k == "local" then
				out[#out + 1] = tab .. "local " .. self:name(st.w)
			elseif k == "assign" then
				local targets = {}
				for t, x in st.targets do
					targets[t] = self:expr(x, indent)
				end
				local function values()
					return #st.values >= #st.targets and self:list(st.values, indent, true) or self:list(st.values, indent)
				end
				local v1 = st.values[1]
				local t1 = st.targets[1]
				local sugarName
				local function path(x)
					if x.k == "global" or x.k == "upval" then
						return isIdent(x.name) and x.name or nil
					elseif x.k == "var" then
						return self:name(x.w)
					elseif x.k == "index" and x.key.str and isIdent(x.key.str) then
						local base = path(x.obj)
						return base and base .. "." .. x.key.str
					end
					return nil
				end
				if #st.targets == 1 and #st.values == 1 and v1.k == "closure" and not st.isLocal and not st.isLocalFunction then
					local debugname = self.chunk.protos[v1.child].debugname
					local last = (t1.k == "index" and t1.key.str) or ((t1.k == "global" or t1.k == "upval") and t1.name)
					if debugname and last == debugname then
						sugarName = path(t1)
					end
				end
				if sugarName then
					local upnames = {}
					for m, cap in v1.caps do
						upnames[m] = type(cap) == "string" and cap or self:name(cap.w)
					end
					-- * a method: called with `:` somewhere in the script, or stored in a class table
					local methodHint
					local key = t1.k == "index" and t1.key.str
					if key and key ~= "new" and key ~= "New" and key ~= "create" and key ~= "Create" then
						if self.ctx.namecalls[key] then
							methodHint = "namecall"
						elseif t1.obj.k == "var" and self.classWebs[t1.obj.w] and not self.ctx.dotReads[key] then
							methodHint = "class"
						end
					end
					local childHints = { method = methodHint, params = v1.hints and v1.hints.params }
					local body, isMethod = decompileFunction(self.chunk, v1.child, upnames, indent, self.ctx, true, childHints)
					if isMethod then
						sugarName = path(t1.obj) .. ":" .. key
					end
					out[#out + 1] = tab .. "function " .. sugarName .. body
				elseif st.isLocalFunction then
					local v = st.values[1]
					local upnames = {}
					for m, cap in v.caps do
						upnames[m] = type(cap) == "string" and cap or self:name(cap.w)
					end
					out[#out + 1] = tab .. "local function " .. targets[1] .. (decompileFunction(self.chunk, v.child, upnames, indent, self.ctx, true, v.hints))
				elseif st.isLocal and #st.targets == 1 and v1.k == "closure" and self.chunk.protos[v1.child].debugname then
					local upnames = {}
					for m, cap in v1.caps do
						upnames[m] = type(cap) == "string" and cap or self:name(cap.w)
					end
					out[#out + 1] = tab .. "local function " .. targets[1] .. (decompileFunction(self.chunk, v1.child, upnames, indent, self.ctx, true, v1.hints))
				elseif st.isLocal and #st.targets == 1 and #st.values == 1 and v1.k == "const" and v1.text == "nil" then
					out[#out + 1] = tab .. "local " .. targets[1]
				elseif st.isLocal then
					out[#out + 1] = tab .. "local " .. concat(targets, ", ") .. " = " .. values()
				else
					-- * x = x + y  ->  x += y
					local v = st.values[1]
					local t1 = st.targets[1]
					local sameTarget = v and v.k == "binop" and #st.targets == 1
						and ((t1.k == "var" and v.l.k == "var" and v.l.w == t1.w) or (t1.k == "upval" and v.l.k == "upval" and v.l.name == t1.name))
					if sameTarget
						and (v.op == "+" or v.op == "-" or v.op == "*" or v.op == "/" or v.op == "//" or v.op == "%" or v.op == "^")
					then
						local r = self:expr(v.r, indent)
						out[#out + 1] = tab .. targets[1] .. " " .. v.op .. "= " .. r
					elseif #st.targets == 1 and st.targets[1].k == "var" and v and v.k == "concat" and v.list[1].k == "var" and v.list[1].w == st.targets[1].w then
						local rest = { k = "concat", list = { table.unpack(v.list, 2) } }
						if #rest.list == 1 then
							rest = rest.list[1]
						end
						out[#out + 1] = tab .. targets[1] .. " ..= " .. self:expr(rest, indent)
					else
						out[#out + 1] = tab .. concat(targets, ", ") .. " = " .. values()
					end
				end
			elseif k == "call" then
				out[#out + 1] = tab .. self:expr(st.expr, indent)
			elseif k == "return" or k == "break" or k == "continue" then
				local text = k
				if k == "return" and #st.values > 0 then
					text = "return " .. self:list(st.values, indent)
				end
				if isLast then
					out[#out + 1] = tab .. text
				else
					out[#out + 1] = tab .. "do " .. text .. " end"
				end
			elseif k == "if" then
				local cur = st
				local first = true
				while true do
					local elseifLine = not first and lineMark(cur.line)
					local mark = elseifLine and ("\1" .. elseifLine .. "\2") or ""
					out[#out + 1] = mark .. tab .. (first and "if " or "elseif ") .. self:expr(cur.cond, indent) .. " then"
					if first and #cur.thenB.stmts == 0 and (not cur.elseB or #cur.elseB.stmts == 0) then
						-- * nothing was lost: every outcome of the condition continues after the `if`
						out[#out + 1] = tab .. "	-- (empty in the bytecode itself: the original body compiled to nothing, e.g. an inlined early `return`; nothing was left out)"
					end
					self:block(cur.thenB, indent + 1, out)
					first = false
					local elseB = cur.elseB
					if elseB and #elseB.stmts == 1 and elseB.stmts[1].k == "if" then
						cur = elseB.stmts[1]
					else
						if elseB and #elseB.stmts > 0 then
							out[#out + 1] = tab .. "else"
							self:block(elseB, indent + 1, out)
						end
						break
					end
				end
				out[#out + 1] = tab .. "end"
			elseif k == "while" then
				out[#out + 1] = tab .. "while " .. (st.cond and self:expr(st.cond, indent) or "true") .. " do"
				self:block(st.body, indent + 1, out)
				out[#out + 1] = tab .. "end"
			elseif k == "repeat" and st.isDo then
				out[#out + 1] = tab .. "do"
				self:block(st.body, indent + 1, out)
				out[#out + 1] = tab .. "end"
			elseif k == "repeat" then
				out[#out + 1] = tab .. "repeat"
				self:block(st.body, indent + 1, out)
				out[#out + 1] = tab .. "until " .. self:expr(st.untilCond, indent)
			elseif k == "numfor" then
				local head = self:name(st.var) .. " = " .. self:expr(st.init, indent) .. ", " .. self:expr(st.limit, indent)
				if not (st.step.k == "const" and st.step.text == "1") then
					head ..= ", " .. self:expr(st.step, indent)
				end
				out[#out + 1] = tab .. "for " .. head .. " do"
				self:block(st.body, indent + 1, out)
				out[#out + 1] = tab .. "end"
			elseif k == "genfor" then
				local names = {}
				for m, w in st.vars do
					names[m] = self:name(w)
				end
				out[#out + 1] = tab .. "for " .. concat(names, ", ") .. " in " .. self:list(st.exprs, indent) .. " do"
				self:block(st.body, indent + 1, out)
				out[#out + 1] = tab .. "end"
			else
				fail("cannot print statement " .. tostring(k))
			end
			if i > 1 and out[startIdx] and startIdx > 1 and string.find(out[startIdx], "^%s*%(") then
				local prev = out[startIdx - 1]
				local lastLine = string.match(prev, "([^\n]*)$")
				if string.find(lastLine, "--", 1, true) then
					out[startIdx - 1] = prev .. "\n" .. tab .. ";"
				else
					out[startIdx - 1] = prev .. ";"
				end
			end
			if markLine and out[startIdx] then
				out[startIdx] = "\1" .. markLine .. "\2" .. out[startIdx]
			end
		end
		self.ctx.lineFloor = floor
	end

	--------------------------------------------------------------------------
	-- one function
	--------------------------------------------------------------------------
	local structuredOnce
	local function structured(chunk, protoId, upnames, indent, ctx, hints)
		local saved = { ctx.structured, ctx.lifted, #ctx.reasons, #ctx.internalErrors }
		local info = {}
		local result = table.pack(pcall(structuredOnce, chunk, protoId, upnames, indent, ctx, hints, false, info))
		if result[1] then
			return table.unpack(result, 2, result.n)
		elseif not info.usedNew then
			error(result[2], 0)
		end
		ctx.structured, ctx.lifted = saved[1], saved[2]
		for n = #ctx.reasons, saved[3] + 1, -1 do
			ctx.reasons[n] = nil
		end
		for n = #ctx.internalErrors, saved[4] + 1, -1 do
			ctx.internalErrors[n] = nil
		end
		return structuredOnce(chunk, protoId, upnames, indent, ctx, hints, true)
	end
	function structuredOnce(chunk, protoId, upnames, indent, ctx, hints, noSplit, info)
		local p = chunk.protos[protoId]
		local A = analyze(chunk, p)
		A.conservative = noSplit
		A.info = info or {}
		local ast = structure(A)
		local irCtx = { upnames = upnames, globals = ctx.globals, chunk = chunk }
		-- * this function and the ones it is written in
		local enclosing = {}
		local q = protoId
		while q ~= nil and not enclosing[q] do
			enclosing[q] = true
			q = ctx.protoParent and ctx.protoParent[q]
		end
		irCtx.ownLine = function(pc)
			local l = p.lineOf and p.lineOf(pc)
			if not l then
				return nil
			end
			local o = ctx.lineOwner and ctx.lineOwner[l]
			if o ~= nil and not enclosing[o] then
				return nil -- * inlined from another function
			end
			return l
		end
		-- * A value used once is folded into its use, unless it was a local of its own in the source:
		-- * written on an earlier line than its use, and still holding its register while the
		-- * statement that uses it works above it (a temporary of the same expression is consumed
		-- * into its own register or below: `p:andThen(f)` <newline> `:catch(g)` reuses it).
		-- * the highest line of the code before each instruction (loop ends jump back to the
		-- * loop's own line, they do not count): a statement of its own never starts above it
		local maxBefore = {}
		do
			local high = 0
			for _, ins in A.seq do
				maxBefore[ins] = high
				local l = irCtx.ownLine(ins.pc)
				if l and l > high and ins.op ~= OP.FORNLOOP and ins.op ~= OP.FORGLOOP and ins.op ~= OP.JUMPBACK then
					high = l
				end
			end
		end
		for _, w in (noSplit and {} or A.webs) do
			if w.tempish and #w.defs == 1 and #w.uses == 1 then
				local def = A.defInfo[w.defs[1]].ins
				local use = w.uses[1].ins
				local dl, ul = def and irCtx.ownLine(def.pc), irCtx.ownLine(use.pc)
				if dl and ul and dl < ul and dl >= (maxBefore[def] or 0) and #def.defs == 1 and not def.boolmat and not def.target
					and not (def.op == OP.CALL and def.c == 0) and not use.boolmat
					and def.op ~= OP.NEWTABLE and def.op ~= OP.DUPTABLE
				then
					local r = def.defs[1]
					local lowest = math.huge
					for _, d in use.defs do
						lowest = math.min(lowest, d)
					end
					local above = lowest > r
					if above then
						A.info.usedNew = true
						w.tempish, w.temp = false, false
					end
				end
			end
		end
		local root, materialized = buildIR(A, ast, irCtx)
		makeRepeats(root)
		makeIfExpressions(root)
		tidyBlocks(root)
		dropDeadNils(root)
		dropEmptyIfs(root)
		placeDeclarations(A, root, materialized, ctx)
		local names, params, isMethod, classWebs = chooseNames(A, p, root, materialized, upnames, hints, ctx, chunk, protoId)
		local printer = setmetatable({ names = names, chunk = chunk, ctx = ctx, classWebs = classWebs }, Printer)
		local out = {}
		-- * functions written inside this one see these names
		local visible = {}
		for _, name in names do
			visible[name] = true
		end
		insert(ctx.outerNames, visible)
		local ok, err = pcall(printer.block, printer, root, indent + 1, out)
		remove(ctx.outerNames)
		if not ok then
			error(err, 0)
		end
		local last = A.seq[#A.seq]
		local endLine = last and last.op == OP.RETURN and last.b == 1 and p.lineOf and p.lineOf(last.pc) or nil
		return params, out, isMethod, endLine
	end

	function decompileFunction(chunk, protoId, upnames, indent, ctx, named, hints)
		if BetterDecompiler.onFunction then
			BetterDecompiler.onFunction() -- * lets the caller yield on very large scripts
		end
		local p = chunk.protos[protoId]
		local ok, params, out, isMethod, endLine = pcall(structured, chunk, protoId, upnames, indent, ctx, hints)
		local header = (p.debugname and not named) and (" -- " .. p.debugname) or ""
		if ok then
			ctx.structured += 1
			local endMark = endLine and ("\1" .. endLine .. "\2") or ""
			return "(" .. concat(params, ", ") .. ")" .. header .. "\3\n" .. concat(out, "\n") .. (#out > 0 and "\n" or "") .. endMark .. rep("\t", indent) .. "end", isMethod
		end
		if not string.find(tostring(params), FAIL, 1, true) then
			ctx.internalErrors[#ctx.internalErrors + 1] = tostring(params)
		end
		ctx.lifted += 1
		ctx.reasons[#ctx.reasons + 1] = ("%s (function %s, line %d, proto %d)"):format(tostring(params), tostring(p.debugname or "anonymous"), p.linedefined, protoId)
		local text, globals = Lifter.liftFunction(chunk, protoId, upnames, indent, function(childId, childUpnames, childIndent)
			return (decompileFunction(chunk, childId, childUpnames, childIndent, ctx))
		end)
		local reason = reasonText(params)
		text = string.gsub(text, "^(%b())\n", function(params)
			return params .. header .. "\n" .. rep("\t", indent + 1)
				.. "-- [low-level] the structure of this function could not be rebuilt (" .. reason .. "); this is its exact behaviour (registers are __R[n], jumps set __pc)\n"
		end, 1)
		for g in globals do
			ctx.globals[g] = true
		end
		text = string.gsub(text, "\n", "\n\4")
		return text, false
	end

	-- * Puts every statement on the line it has in the original script (from the bytecode's line
	-- * info), so error messages, tracebacks and debug.info give the original line numbers.
	-- * Printer markers: "\1<line>\2" starts a statement's first line, "\3" ends a function header,
	-- * "\4" starts a line that stays on a line of its own (low-level code). When the output is
	-- * behind, blank lines are added; when it is ahead, lines are joined onto the previous one,
	-- * which never changes what the code means: a `--` comment before the join becomes a
	-- * `--[[ ]]` comment, and a line starting with `(` gets a `;` (no `f` `(x)` call ambiguity).
	-- * Returns the text without markers.
	local OPENER_WORDS = { ["then"] = true, ["do"] = true, ["else"] = true, ["repeat"] = true }
	local function commentStart(line)
		local i, n = 1, #line
		while i <= n do
			local c = string.sub(line, i, i)
			if c == '"' or c == "'" then
				i += 1
				while i <= n do
					local d = string.sub(line, i, i)
					if d == "\\" then
						i += 2
					elseif d == c then
						break
					else
						i += 1
					end
				end
				i += 1
			elseif c == "-" and string.sub(line, i + 1, i + 1) == "-" then
				local level = string.match(line, "^%[(=*)%[", i + 2)
				local close = level and string.find(line, "]" .. level .. "]", i + 4 + #level, true)
				if not close then
					return i
				end
				i = close + #level + 2
			else
				i += 1
			end
		end
		return nil
	end
	local MAX_JOINED = 240
	local function layoutLines(text, enabled)
		if not enabled then
			return (string.gsub(string.gsub(text, "\1%d+\2", ""), "[\3\4]", ""))
		end
		local lines = {}
		for raw in string.gmatch(text .. "\n", "([^\n]*)\n") do
			local entry = { free = false, opener = false }
			while true do
				local target, rest = string.match(raw, "^\1(%d+)\2(.*)$")
				if target then
					entry.target = entry.target or tonumber(target)
					raw = rest
				elseif string.sub(raw, 1, 1) == "\4" then
					entry.free = true
					raw = string.sub(raw, 2)
				else
					break
				end
			end
			if string.sub(raw, -1) == "\3" then
				entry.opener = true
				raw = string.sub(raw, 1, -2)
			end
			entry.text = string.gsub(raw, "[\1\2\3\4]", "")
			lines[#lines + 1] = entry
		end
		local nextTarget = {}
		local nt
		for n = #lines, 1, -1 do
			nextTarget[n] = nt
			nt = lines[n].target or nt
		end
		-- * each output line: its pieces, and what joining after it needs to know
		local out = {}
		local function describe(line, text)
			local cut = commentStart(text)
			local code = cut and string.sub(text, 1, cut - 1) or text
			code = string.match(code, "^(.-)%s*$")
			line.comment = cut and string.sub(text, cut + 2) or nil
			if code ~= "" and string.find(code, "%S") then
				line.lastChar = string.sub(code, -1)
				line.lastWord = string.match(code, "([%w_]+)$")
			end
			line.len += #text
		end
		local function push(entry)
			local line = { pieces = { entry.text }, len = 0, opener = entry.opener }
			describe(line, entry.text)
			out[#out + 1] = line
		end
		local function canJoin(entry)
			local prev = out[#out]
			return prev ~= nil and not entry.free and string.find(entry.text, "%S") ~= nil
				and prev.len + #entry.text < MAX_JOINED
		end
		local function join(entry)
			local line = out[#out]
			local add = string.match(entry.text, "^%s*(.-)$")
			local last = line.pieces[#line.pieces]
			if line.comment then
				-- * `-- c` -> `--[[ c ]]`, so the code after it is not commented out
				local cut = commentStart(last)
				local level = ""
				while string.find(line.comment, "]" .. level .. "]", 1, true) do
					level ..= "="
				end
				local code = string.match(string.sub(last, 1, cut - 1), "^(.-)%s*$")
				line.pieces[#line.pieces] = code .. (code ~= "" and " " or "") .. "--[" .. level .. "[" .. line.comment .. " ]" .. level .. "]"
				line.comment = nil
			end
			-- * `f()` then `(x)()` on one line would be one call: separate them with `;`
			local sep = " "
			if string.sub(add, 1, 1) == "(" and not line.opener and not (line.lastWord and OPENER_WORDS[line.lastWord])
				and line.lastChar and string.find(line.lastChar, "[%w_%)%]}\"]")
			then
				sep = "; "
			end
			line.pieces[#line.pieces + 1] = sep .. add
			line.opener = entry.opener
			describe(line, add)
		end
		for n, entry in lines do
			local t = entry.target
			local blank = string.find(entry.text, "%S") == nil
			if t and t > #out then
				while #out < t - 1 do
					push({ text = "", opener = false })
				end
				push(entry)
			elseif t then
				if canJoin(entry) then
					join(entry)
				else
					push(entry)
				end
			else
				local nextT = nextTarget[n]
				local room = nextT == nil or #out + 1 < nextT
				if room or entry.free then
					push(entry)
				elseif canJoin(entry) then
					join(entry)
				elseif not blank then
					push(entry)
				end
			end
		end
		local result = table.create(#out)
		for n, line in out do
			result[n] = concat(line.pieces)
		end
		return concat(result, "\n")
	end

	-- * For every source line, the innermost function whose body strictly contains it. An
	-- * instruction of function F on a line owned by another function (not F, not one F is
	-- * written in) is inlined code: -O2 copies a local function's body, with its lines, into
	-- * the caller.
	local function lineOwners(chunk)
		local parent, spans = {}, {}
		for id, p in chunk.protos do
			if p.p then
				for _, child in p.p do
					parent[child] = id
				end
			end
		end
		for id, p in chunk.protos do
			if p.lineOf and p.sizecode then
				local last = p.linedefined or 0
				for pc = 0, p.sizecode - 1 do
					local l = p.lineOf(pc)
					if l and l > last then
						last = l
					end
				end
				spans[#spans + 1] = { id = id, first = p.linedefined or 0, last = last }
			end
		end
		table.sort(spans, function(x, y)
			return (x.last - x.first) > (y.last - y.first)
		end)
		local owner = {}
		for _, span in spans do
			for line = span.first + 1, span.last - 1 do
				owner[line] = span.id
			end
		end
		return owner, parent
	end

	-- * decompiles a whole script; returns source text and stats.
	-- * options.scriptName (optional) names the module's main table after the script.
	-- * options.matchLines (default true) puts statements on their original line numbers.
	function BetterDecompiler.decompile(chunk, options)
		local allGlobals, namecalls, dotReads = scanChunk(chunk)
		local lineOwner, protoParent = lineOwners(chunk)
		local ctx = {
			globals = {}, structured = 0, lifted = 0, reasons = {}, internalErrors = {},
			allGlobals = allGlobals, namecalls = namecalls, dotReads = dotReads, options = options or {}, outerNames = {},
			lineOwner = lineOwner, protoParent = protoParent,
		}
		local ok, params, out = pcall(structured, chunk, chunk.main, {}, -1, ctx)
		local body
		if ok then
			ctx.structured += 1
			body = layoutLines(concat(out, "\n"), ctx.options.matchLines ~= false)
		else
			ctx.lifted += 1
			ctx.reasons[#ctx.reasons + 1] = "main: " .. tostring(params)
			if not string.find(tostring(params), FAIL, 1, true) then
				ctx.internalErrors[#ctx.internalErrors + 1] = tostring(params)
			end
			body = "-- [low-level] the structure of the main body could not be rebuilt (" .. reasonText(params) .. "); it is exact but low level\n"
				.. layoutLines(Lifter.liftScript(chunk, function(childId, childUpnames, childIndent)
					return (decompileFunction(chunk, childId, childUpnames, childIndent, ctx))
				end), false)
		end
		return body, ctx
	end
end

-- * Renames generic decompiler output names (v14, p1, s1, arg3, ...) into names
-- * inferred from what they get assigned from / how they are used.
-- * Pure text in, text out. Comments, whitespace and everything else is preserved.

local RenameDecompiledVariables, FixGotoStatements, FixFunctionTypeAnnotations, RebuildBrokenFunctions, FindSuspiciousLines, FreeNames
do
	local sub, find, gsub, rep, upper, lower, match =
		string.sub, string.find, string.gsub, string.rep, string.upper, string.lower, string.match
	local concat = table.concat
	local floor = math.floor
	local clock = os.clock
	local step = (task and task.wait) or wait

	local KEYWORDS = {}
	for word in string.gmatch(
		"and break do else elseif end false for function if in local nil not or repeat return then true until while",
		"%S+"
	) do
		KEYWORDS[word] = true
	end

	-- * Names we must never generate, so that we can never shadow something the script needs
	local RESERVED = {}
	for word in pairs(KEYWORDS) do
		RESERVED[word] = true
	end
	for word in string.gmatch(
		[[continue export type typeof self _G _ENV game workspace Workspace script shared plugin string table math os io
		coroutine bit32 buffer utf8 debug task print warn error assert pairs ipairs next select tostring tonumber pcall
		xpcall ypcall rawget rawset rawequal rawlen setmetatable getmetatable unpack require wait spawn delay tick time
		newproxy loadstring load getfenv setfenv collectgarbage gcinfo elapsedTime version settings UserSettings stats
		PluginManager Instance Vector3 Vector2 Vector3int16 Vector2int16 CFrame UDim UDim2 Color3 BrickColor ColorSequence
		ColorSequenceKeypoint NumberRange NumberSequence NumberSequenceKeypoint Enum Ray Region3 Region3int16 TweenInfo
		Random Faces Axes Rect PhysicalProperties DateTime Font OverlapParams RaycastParams RaycastResult Content
		SharedTable vector]],
		"%S+"
	) do
		RESERVED[word] = true
	end

	local OPS = {
		"...", "..=", "//=", "<<=", ">>=",
		"..", "==", "~=", "!=", "<=", ">=", "+=", "-=", "*=", "/=", "%=", "^=", "//", "::", "->", "<<", ">>",
	}

	local OPEN = { ["("] = true, ["["] = true, ["{"] = true }
	local CLOSE = { [")"] = true, ["]"] = true, ["}"] = true }
	local STOPPERS = { ["end"] = true, ["until"] = true, ["local"] = true, ["return"] = true, ["break"] = true, ["continue"] = true }
	local LOGIC = { ["and"] = true, ["or"] = true }
	local COMPARE = { ["=="] = true, ["~="] = true, ["!="] = true, ["<"] = true, [">"] = true, ["<="] = true, [">="] = true }
	local ARITH = { ["+"] = true, ["-"] = true, ["*"] = true, ["/"] = true, ["%"] = true, ["^"] = true, ["//"] = true }

	-- * hoisted so the hot path does not allocate a table per lookup
	local SET_CONCAT = { [".."] = true }
	local SET_ASSIGN = { ["="] = true }
	local SET_THEN = { ["then"] = true }

	local ORDINALS = { "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth" }

	-- * marker: "name this after the first argument of the call"
	local A1 = "\1arg1"

	local METHODS = {
		GetChildren = "children",
		GetDescendants = "descendants",
		GetAncestors = "ancestors",
		GetPlayers = "players",
		GetTags = "tags",
		GetAttributes = "attributes",
		GetAttribute = A1,
		GetJoints = "joints",
		GetConnectedParts = "connected_parts",
		GetTouchingParts = "touching_parts",
		GetFullName = "full_name",
		GetDebugId = "debug_id",
		GetPropertyChangedSignal = "signal",
		GetAttributeChangedSignal = "signal",
		GetBoundingBox = "bounding_box",
		GetExtentsSize = "extents_size",
		GetPivot = "pivot",
		GetScale = "scale",
		GetMouse = "mouse",
		GetService = A1,
		FindService = A1,
		FindFirstChild = A1,
		WaitForChild = A1,
		FindFirstChildOfClass = A1,
		FindFirstChildWhichIsA = A1,
		FindFirstAncestor = A1,
		FindFirstAncestorOfClass = A1,
		FindFirstAncestorWhichIsA = A1,
		FindFirstDescendant = A1,
		Clone = "clone",
		IsA = "matches_class",
		IsDescendantOf = "is_descendant",
		IsAncestorOf = "is_ancestor",
		tostring = "text",
		tonumber = "number",
		typeof = "type_name",
		type = "type_name",
		unpack = "unpacked",
		Wait = "elapsed",
		Invoke = "invoke_result",
		InvokeServer = "invoke_result",
		Connect = "connection",
		Once = "connection",
		ConnectParallel = "connection",
		LoadAnimation = "track",
		["table.clone"] = "clone",
		["table.concat"] = "text",
		["table.find"] = "index",
		["table.remove"] = "removed",
		["table.pack"] = "packed",
		["table.unpack"] = "unpacked",
		["table.getn"] = "count",
		["table.maxn"] = "count",
		["table.freeze"] = "frozen",
		["table.isfrozen"] = "is_frozen",
		["string.format"] = "formatted",
		-- * the same functions reached as `s:gsub(...)` arrive here by bare name
		format = "formatted",
		gsub = "replaced",
		sub = "part",
		find = "position",
		match = "found",
		gmatch = "matches",
		split = "parts",
		rep = "repeated",
		reverse = "reversed",
		lower = "lowered",
		upper = "uppered",
		byte = "byte",
		char = "character",
		len = "length",
		trim = "trimmed",
		["string.split"] = "parts",
		["string.sub"] = "part",
		["string.gsub"] = "replaced",
		["string.match"] = "found",
		["string.gmatch"] = "matches",
		["string.find"] = "position",
		["string.rep"] = "repeated",
		["string.len"] = "length",
		["string.byte"] = "byte",
		["string.char"] = "character",
		["string.reverse"] = "reversed",
		["string.lower"] = "lowered",
		["string.upper"] = "uppered",
		["os.time"] = "timestamp",
		["os.clock"] = "clock",
		["os.date"] = "date",
		tick = "timestamp",
		["math.random"] = "random",
		["coroutine.create"] = "thread",
		["coroutine.wrap"] = "thread",
		["task.spawn"] = "thread",
		["task.defer"] = "thread",
		["task.delay"] = "thread",
		["buffer.create"] = "buff",
		["buffer.fromstring"] = "buff",
	}

	local VERB_PATTERNS = {
		"^[Gg]et_?(%w.*)$",
		"^[Ff]etch_?(%w.*)$",
		"^[Ll]oad_?(%w.*)$",
		"^[Rr]ead_?(%w.*)$",
		"^[Mm]ake_?(%w.*)$",
		"^[Cc]reate_?(%w.*)$",
		"^[Bb]uild_?(%w.*)$",
		"^[Cc]ompute_?(%w.*)$",
		"^[Cc]alculate_?(%w.*)$",
		"^[Rr]esolve_?(%w.*)$",
		"^[Pp]arse_?(%w.*)$",
		"^[Gg]enerate_?(%w.*)$",
		"^[Cc]onstruct_?(%w.*)$",
		"^[Rr]etrieve_?(%w.*)$",
		"^[Qq]uery_?(%w.*)$",
		"^[Dd]ownload_?(%w.*)$",
		"^[Rr]equest_?(%w.*)$",
	}

	local BOOL_PATTERNS = { "^[Ii]s[_%u]", "^[Hh]as[_%u]", "^[Cc]an[_%u]", "^[Ss]hould[_%u]", "^[Ww]as[_%u]" }

	-- * `i` reads well, `i_7` does not, so short names grow a real word when they collide
	local ALIAS = {
		i = "index", j = "index", k = "key", v = "value", n = "count", t = "tbl", s = "text",
		b = "flag", f = "callback", c = "character", d = "data", e = "entry", m = "match",
		o = "object", p = "part", r = "result", u = "value", w = "value", x = "value", y = "value", z = "value",
	}

	local PLAYER_FIELDS = {
		Character = true, UserId = true, DisplayName = true, PlayerGui = true, Backpack = true,
		Team = true, TeamColor = true, AccountAge = true, CharacterAdded = true, FollowUserId = true,
	}

	--------------------------------------------------------------------------
	-- helpers
	--------------------------------------------------------------------------

	local function isGenericName(name)
		if RESERVED[name] then
			return false
		end
		if find(name, "^[A-Za-z]%d+$") then -- v14, p1, s1, u3, A2
			return true
		end
		if find(name, "^[A-Za-z]_%d+$") then -- v_14, l_3
			return true
		end
		if find(name, "^arg%d*$") or find(name, "^args%d+$") or find(name, "^var%d*$") or find(name, "^param%d*$") then
			return true
		end
		if find(name, "^upval%w*%d+$") or find(name, "^loc%d+$") or find(name, "^tmp%d*$") or find(name, "^temp%d*$") then
			return true
		end
		if find(name, "^unknown%d*$") or find(name, "^slot%d+$") or find(name, "^reg%d+$") then
			return true
		end
		return false
	end

	-- * `v`, `k`, `t`, ... carry no meaning, so we look through them to what they hold
	local function isWeakName(name)
		return #name <= 2 and not find(name, "^%u") and name ~= "_"
	end

	local function upperFirst(s)
		return (gsub(s, "^%l", upper))
	end

	local function lowerFirst(s)
		return (gsub(s, "^%u", lower))
	end

	local IRREGULAR = {
		children = "child", people = "person", men = "man", women = "woman", feet = "foot",
		teeth = "tooth", mice = "mouse", geese = "goose", indices = "index", vertices = "vertex",
		matrices = "matrix", criteria = "criterion", data = "entry", descendants = "descendant",
	}

	local function singularize(s)
		local irregular = IRREGULAR[lower(s)]
		if irregular then
			return find(s, "^%u") and upper(sub(irregular, 1, 1)) .. sub(irregular, 2) or irregular
		end
		if #s < 4 then
			return s
		end
		local body
		if find(s, "ies$") then
			body = sub(s, 1, #s - 3) .. "y"
		elseif find(s, "[sxz]es$") or find(s, "[cs]hes$") then
			body = sub(s, 1, #s - 2)
		elseif find(s, "[^suiSUI]s$") and not find(s, "ss$") then
			body = sub(s, 1, #s - 1)
		end
		if body and #body >= 2 then
			return body
		end
		return s
	end

	-- * `s:gsub("%W", "")` must not produce a variable called `W`
	local function looksLikePattern(text)
		if find(text, "%%%a") or find(text, "%%%%") then
			return true
		end
		if find(text, "^%^") or find(text, "%$$") then
			return true
		end
		if find(text, "%.[%*%-%+]") or find(text, "%[%^") then
			return true
		end
		return false
	end

	local function sanitize(name)
		if type(name) ~= "string" or name == "" then
			return nil
		end
		name = gsub(name, "[^%w_]+", "_")
		name = gsub(name, "__+", "_")
		name = gsub(name, "^_+", "")
		name = gsub(name, "_+$", "")
		if name == "" then
			return nil
		end
		if find(name, "^%d") then
			name = "n" .. name
		end
		if #name > 42 then
			name = gsub(sub(name, 1, 42), "_+$", "")
		end
		if KEYWORDS[name] then
			name = name .. "_value"
		end
		if isGenericName(name) then
			return nil
		end
		return name
	end

	local function stringContents(text)
		local q = sub(text, 1, 1)
		if q == '"' or q == "'" then
			return sub(text, 2, #text - 1)
		end
		local s, e = find(text, "^%[=*%[")
		if s then
			return sub(text, e + 1, #text - (e - s))
		end
		return nil
	end

	--------------------------------------------------------------------------
	-- lexer: `pieces` holds every byte of the source in order, `toks` holds
	-- the meaningful tokens, each pointing at the piece it occupies
	--------------------------------------------------------------------------

	local function lex(src)
		local pieces, toks, comments = {}, {}, {}
		local np, nt, nc = 0, 0, 0
		local total = #src
		local pendingNL = true

		local function pushRaw(s)
			np = np + 1
			pieces[np] = s
		end
		local function pushComment(s)
			np = np + 1
			pieces[np] = s
			nc = nc + 1
			comments[nc] = np
		end
		local function pushTok(s, kind)
			np = np + 1
			pieces[np] = s
			nt = nt + 1
			toks[nt] = { i = np, k = kind, v = s, nl = pendingNL }
			pendingNL = false
		end

		local lexChunk
		lexChunk = function(from, to)
			local i = from
			while i <= to do
				local c = sub(src, i, i)
				if c == " " or c == "\t" or c == "\r" or c == "\n" then
					local s, e = find(src, "^[ \t\r\n]+", i)
					local w = sub(src, s, e)
					if find(w, "\n", 1, true) then
						pendingNL = true
					end
					pushRaw(w)
					i = e + 1
				elseif c == "-" and sub(src, i + 1, i + 1) == "-" then
					local bs, be = find(src, "^%[=*%[", i + 2)
					local stop
					if bs then
						local closer = "]" .. rep("=", be - bs - 1) .. "]"
						local _, ce = find(src, closer, be + 1, true)
						stop = ce or to
					else
						local nl = find(src, "\n", i + 2, true)
						stop = (nl and nl - 1) or to
					end
					local w = sub(src, i, stop)
					if find(w, "\n", 1, true) then
						pendingNL = true
					end
					pushComment(w)
					i = stop + 1
				elseif c == "[" and find(src, "^%[=*%[", i) then
					local bs, be = find(src, "^%[=*%[", i)
					local closer = "]" .. rep("=", be - bs - 1) .. "]"
					local _, ce = find(src, closer, be + 1, true)
					local stop = ce or to
					pushTok(sub(src, i, stop), "str")
					i = stop + 1
				elseif c == '"' or c == "'" then
					local j = i + 1
					while j <= to do
						local d = sub(src, j, j)
						if d == "\\" then
							j = j + 2
						elseif d == c or d == "\n" then
							break
						else
							j = j + 1
						end
					end
					if j > to then
						j = to
					end
					pushTok(sub(src, i, j), "str")
					i = j + 1
				elseif c == "`" then
					pushRaw("`")
					local j = i + 1
					local litStart = j
					while j <= to do
						local d = sub(src, j, j)
						if d == "\\" then
							j = j + 2
						elseif d == "`" then
							break
						elseif d == "{" then
							if j > litStart then
								pushRaw(sub(src, litStart, j - 1))
							end
							pushRaw("{")
							local depth, k = 1, j + 1
							while k <= to do
								local e2 = sub(src, k, k)
								if e2 == "{" then
									depth = depth + 1
									k = k + 1
								elseif e2 == "}" then
									depth = depth - 1
									if depth == 0 then
										break
									end
									k = k + 1
								elseif e2 == '"' or e2 == "'" then
									local q = e2
									k = k + 1
									while k <= to do
										local f2 = sub(src, k, k)
										if f2 == "\\" then
											k = k + 2
										elseif f2 == q then
											k = k + 1
											break
										else
											k = k + 1
										end
									end
								else
									k = k + 1
								end
							end
							if k > to then
								k = to + 1
							end
							if k - 1 >= j + 1 then
								lexChunk(j + 1, k - 1)
							end
							pushRaw("}")
							j = k + 1
							litStart = j
						else
							j = j + 1
						end
					end
					if j > to then
						j = to
					end
					if j >= litStart then
						pushRaw(sub(src, litStart, j))
					end
					i = j + 1
				elseif find(src, "^[%a_]", i) then
					local s, e = find(src, "^[%a_][%w_]*", i)
					local w = sub(src, s, e)
					pushTok(w, KEYWORDS[w] and "kw" or "name")
					i = e + 1
				elseif find(src, "^%d", i) or (c == "." and find(src, "^%.%d", i)) then
					local s, e = find(src, "^%.?%d[%w_%.]*", i)
					while true do
						local tail = sub(src, e, e)
						if (tail == "e" or tail == "E" or tail == "p" or tail == "P") and find(src, "^[%+%-]%d", e + 1) then
							local _, e2 = find(src, "^[%+%-][%d_]*", e + 1)
							e = e2
						else
							break
						end
					end
					pushTok(sub(src, s, e), "num")
					i = e + 1
				else
					local matched
					for n = 1, #OPS do
						local op = OPS[n]
						if sub(src, i, i + #op - 1) == op then
							matched = op
							break
						end
					end
					matched = matched or c
					pushTok(matched, "op")
					i = i + #matched
				end
			end
		end

		lexChunk(1, total)
		return pieces, toks, nt, comments, nc
	end

	--------------------------------------------------------------------------

	function FixGotoStatements(src)
		if type(src) ~= "string" or src == "" then
			return src
		end
		if not find(src, "goto", 1, true) then
			return src
		end

		local pieces, toks, ntoks = lex(src)

		local function isOp(i, v)
			local t = toks[i]
			return t ~= nil and t.k == "op" and t.v == v
		end
		local function isKw(i, v)
			local t = toks[i]
			return t ~= nil and t.k == "kw" and t.v == v
		end

		-- * `::name::` at i, stepping over one leading `;`
		local function labelAt(i)
			while isOp(i, ";") do
				i = i + 1
			end
			if isOp(i, "::") and toks[i + 1] and toks[i + 1].k == "name" and isOp(i + 2, "::") then
				return i, toks[i + 1].v
			end
			return nil
		end

		-- * Luau wants `continue` / `break` to be the last statement of a block
		local function terminatesBlock(i)
			while isOp(i, ";") do
				i = i + 1
			end
			local t = toks[i]
			if not t or t.k ~= "kw" then
				return false
			end
			return t.v == "end" or t.v == "else" or t.v == "elseif" or t.v == "until"
		end

		-- * `::l0::;` and `::l0:: ::l1::` are still the end of the body
		local function reachesBlockEnd(i)
			for _ = 1, 64 do
				if isOp(i, ";") then
					i = i + 1
				elseif isOp(i, "::") and toks[i + 1] and toks[i + 1].k == "name" and isOp(i + 2, "::") then
					i = i + 3
				else
					break
				end
			end
			return isKw(i, "end")
		end

		local blocks = {}
		local funcDepth = 0
		local pendingLoop = false
		local pendingIf = {}
		local labels = {}
		local gotos = {}

		-- * the loop a `goto` sits in, stopping at a function boundary and
		-- * refusing `repeat`, where Luau restricts `continue`
		local function enclosingLoop()
			for n = #blocks, 1, -1 do
				local b = blocks[n]
				if b.kind == "func" or b.kind == "repeat" then
					return nil
				end
				if b.isLoop then
					return b.openTok
				end
			end
			return nil
		end

		local function statementIf(i)
			local t = toks[i]
			if t.nl then
				return true
			end
			local prev = toks[i - 1]
			if not prev then
				return true
			end
			if prev.k == "op" and prev.v == ";" then
				return true
			end
			if prev.k == "kw" and (prev.v == "then" or prev.v == "else" or prev.v == "do" or prev.v == "repeat" or prev.v == "end") then
				return true
			end
			return false
		end

		local function noteLabel(at, name, kind, loopOpen)
			local known = labels[name]
			if known then
				if known.tokStart ~= at then
					known.count = known.count + 1
					known.kind = nil -- * the same name twice, too ambiguous to touch
				end
				return
			end
			labels[name] = {
				count = 1,
				kind = kind,
				tokStart = at,
				tokEnd = at + 2,
				loopOpen = loopOpen,
				funcDepth = funcDepth,
			}
		end

		local i = 1
		while i <= ntoks do
			local t = toks[i]
			if t.k == "kw" then
				local kw = t.v
				if kw == "for" or kw == "while" then
					pendingLoop = true
				elseif kw == "do" then
					blocks[#blocks + 1] = { kind = "do", isLoop = pendingLoop, openTok = i }
					pendingLoop = false
				elseif kw == "repeat" then
					blocks[#blocks + 1] = { kind = "repeat", openTok = i }
				elseif kw == "function" then
					if not (isOp(i - 1, ":") or isOp(i - 1, "::")) then
						funcDepth = funcDepth + 1
						blocks[#blocks + 1] = { kind = "func", openTok = i }
					end
				elseif kw == "if" then
					pendingIf[#pendingIf + 1] = statementIf(i)
				elseif kw == "then" then
					local isStmt = true
					if #pendingIf > 0 then
						isStmt = pendingIf[#pendingIf]
						pendingIf[#pendingIf] = nil
					end
					blocks[#blocks + 1] = { kind = isStmt and "then" or "thenexpr", openTok = i }
				elseif kw == "else" then
					if blocks[#blocks] and blocks[#blocks].kind == "thenexpr" then
						blocks[#blocks] = nil
					else
						blocks[#blocks] = nil
						blocks[#blocks + 1] = { kind = "then", openTok = i }
					end
				elseif kw == "elseif" then
					if blocks[#blocks] and blocks[#blocks].kind == "thenexpr" then
						blocks[#blocks] = nil
						pendingIf[#pendingIf + 1] = false
					else
						blocks[#blocks] = nil
						pendingIf[#pendingIf + 1] = true
					end
				elseif kw == "end" then
					while blocks[#blocks] and blocks[#blocks].kind == "thenexpr" do
						blocks[#blocks] = nil
					end
					local closed = blocks[#blocks]
					blocks[#blocks] = nil
					if closed then
						if closed.kind == "func" then
							funcDepth = funcDepth - 1
						elseif closed.isLoop then
							local at, name = labelAt(i + 1)
							if at then
								noteLabel(at, name, "break", closed.openTok)
							end
						end
					end
				elseif kw == "until" then
					while blocks[#blocks] and blocks[#blocks].kind == "thenexpr" do
						blocks[#blocks] = nil
					end
					blocks[#blocks] = nil
				end
				i = i + 1
			elseif t.k == "op" and t.v == "::" and toks[i + 1] and toks[i + 1].k == "name" and isOp(i + 2, "::") then
				local top = blocks[#blocks]
				local kind, loopOpen = nil, nil
				if reachesBlockEnd(i + 3) and top and top.isLoop then
					kind, loopOpen = "continue", top.openTok
				end
				noteLabel(i, toks[i + 1].v, kind, loopOpen)
				i = i + 3
			elseif t.k == "name" and t.v == "goto" and toks[i + 1] and toks[i + 1].k == "name" then
				local prev = toks[i - 1]
				local after = toks[i + 2]
				local isField = prev ~= nil and prev.k == "op" and (prev.v == "." or prev.v == ":")
				local isIndexed = after ~= nil and after.k == "op"
					and (after.v == "=" or after.v == "." or after.v == ":" or after.v == "(" or after.v == "[" or after.v == ",")
				if not isField and not isIndexed then
					gotos[#gotos + 1] = {
						name = toks[i + 1].v,
						tokGoto = i,
						tokName = i + 1,
						loopOpen = enclosingLoop(),
						funcDepth = funcDepth,
						terminates = terminatesBlock(i + 2),
					}
					i = i + 2
				else
					i = i + 1
				end
			else
				i = i + 1
			end
		end

		local byLabel = {}
		for n = 1, #gotos do
			local g = gotos[n]
			local list = byLabel[g.name]
			if not list then
				list = {}
				byLabel[g.name] = list
			end
			list[#list + 1] = g
		end

		-- * the `;` after `::l0::;` was part of the label statement
		local function labelStop(label)
			local stop = label.tokEnd
			while toks[stop + 1] and toks[stop + 1].k == "op" and toks[stop + 1].v == ";" do
				stop = stop + 1
			end
			return stop
		end

		local function blankRange(fromPiece, toPiece)
			for piece = fromPiece, toPiece do
				pieces[piece] = ""
			end
		end

		local function dropLeadingBlank(piece)
			local before = pieces[piece - 1]
			if before and find(before, "^[ \t\r\n]*$") then
				if find(before, "\n[ \t]*$") then
					pieces[piece - 1] = gsub(before, "\n[ \t]*$", "")
				else
					pieces[piece - 1] = gsub(before, "[ \t]+$", "")
				end
			end
		end

		local fixed = 0
		for name, list in pairs(byLabel) do
			local label = labels[name]
			if label and label.count == 1 and label.kind and label.loopOpen then
				local safe = true
				for n = 1, #list do
					local g = list[n]
					-- * same function, same loop, and in a position Luau accepts
					if not g.terminates or g.funcDepth ~= label.funcDepth or g.loopOpen ~= label.loopOpen then
						safe = false
						break
					end
				end
				if safe then
					local word = (label.kind == "continue") and "continue" or "break"
					for n = 1, #list do
						local g = list[n]
						pieces[toks[g.tokGoto].i] = word
						blankRange(toks[g.tokGoto].i + 1, toks[g.tokName].i)
					end
					blankRange(toks[label.tokStart].i, toks[labelStop(label)].i)
					dropLeadingBlank(toks[label.tokStart].i)
					label.removed = true
					fixed = fixed + 1
				end
			end
		end

		-- * a label nothing jumps to is dead; dropping it can only help the parse
		for _, label in pairs(labels) do
			if not label.removed and label.count == 1 and byLabel[toks[label.tokStart + 1].v] == nil then
				blankRange(toks[label.tokStart].i, toks[labelStop(label)].i)
				dropLeadingBlank(toks[label.tokStart].i)
				fixed = fixed + 1
			end
		end

		if fixed == 0 then
			return src
		end
		return concat(pieces)
	end

	-- * Decompilers emit `p1: function` / `p1: function?`, which Luau refuses to parse
	-- * ("Using 'function' as a type annotation is not supported"). Types are erased at
	-- * runtime, so swapping in `(...any) -> ...any` changes nothing but makes it parse.
	-- * A `function` keyword right after `:` `::` `->` can only be a type: methods are
	-- * called as `obj:name(...)` and `function` is never a valid name.
	local FUNCTION_TYPE = "(...any) -> ...any"
	function FixFunctionTypeAnnotations(src)
		if type(src) ~= "string" or src == "" or not find(src, "function", 1, true) then
			return src
		end

		local pieces, toks, ntoks = lex(src)
		local fixed = 0
		for n = 2, ntoks do
			local t = toks[n]
			if t.k == "kw" and t.v == "function" then
				local prev = toks[n - 1]
				local nxt = toks[n + 1]
				local isType = prev.k == "op" and (prev.v == ":" or prev.v == "::" or prev.v == "->")
				if not isType and prev.k == "op" and (prev.v == "|" or prev.v == "&") then
					isType = not (nxt and nxt.k == "op" and nxt.v == "(")
				end
				if isType then
					if (nxt and nxt.k == "op" and (nxt.v == "?" or nxt.v == "|" or nxt.v == "&")) or prev.v == "|" or prev.v == "&" then
						pieces[t.i] = "(" .. FUNCTION_TYPE .. ")"
					else
						pieces[t.i] = FUNCTION_TYPE
					end
					fixed = fixed + 1
				end
			end
		end

		if fixed == 0 then
			return src
		end
		return concat(pieces)
	end

	-- * Lines with `until x == x`: always true, so the loop runs once. Real code never says
	-- * that; it is the decompiler giving two different variables the same name (e.g.
	-- * `until next == next` for `until effect == firstEffect`). It compiles, but is wrong.
	function FindSuspiciousLines(src)
		local lines = {}
		if type(src) ~= "string" or not find(src, "until", 1, true) then
			return lines
		end
		local pieces, toks, ntoks = lex(src)
		local pieceLine, line = {}, 1
		for n = 1, #pieces do
			pieceLine[n] = line
			local _, newlines = gsub(pieces[n], "\n", "")
			line += newlines
		end
		local ACCESS = { ["."] = true, [":"] = true, ["["] = true, ["("] = true }
		for t = 1, ntoks - 3 do
			local kw, left, op, right, after = toks[t], toks[t + 1], toks[t + 2], toks[t + 3], toks[t + 4]
			if kw.k == "kw" and kw.v == "until"
				and left.k == "name" and right.k == "name" and left.v == right.v
				and op.k == "op" and op.v == "=="
				and not (after and after.k == "op" and ACCESS[after.v])
			then
				lines[#lines + 1] = pieceLine[kw.i]
			end
		end
		return lines
	end

	-- * Replaces the top level functions that contain `badLines` (line numbers in `src`) with
	-- * versions rebuilt from bytecode. Everything else stays exactly as the decompiler wrote
	-- * it. Returns the new source and how many functions were rebuilt, or nil and a reason
	-- * (e.g. when a bad line is in the main body of the script, not inside a function).
	function RebuildBrokenFunctions(src, chunk, badLines)
		local pieces, toks, ntoks = lex(src)

		-- * byte offset and line of every piece
		local pieceStart, pieceLine = {}, {}
		do
			local offset, line = 1, 1
			for n = 1, #pieces do
				pieceStart[n], pieceLine[n] = offset, line
				local piece = pieces[n]
				offset += #piece
				local _, newlines = gsub(piece, "\n", "")
				line += newlines
			end
		end
		local function tokStart(t)
			return pieceStart[toks[t].i]
		end
		local function tokEnd(t)
			return pieceStart[toks[t].i] + #pieces[toks[t].i] - 1
		end
		local function tokLine(t)
			return pieceLine[toks[t].i]
		end
		local function isOp(t, v)
			local tok = toks[t]
			return tok ~= nil and tok.k == "op" and tok.v == v
		end

		-- * function spans and the locals declared directly in the main body
		local spans = {}
		local mainLocals = {} -- name -> first token index it is declared at
		local blocks, pendingLoop, pendingIf = {}, false, {}
		local funcDepth = 0

		local function statementIf(t)
			local tok = toks[t]
			if tok.nl then
				return true
			end
			local prev = toks[t - 1]
			if not prev then
				return true
			end
			if prev.k == "op" and prev.v == ";" then
				return true
			end
			return prev.k == "kw"
				and (prev.v == "then" or prev.v == "else" or prev.v == "do" or prev.v == "repeat" or prev.v == "end")
		end
		local function noteLocal(name, t)
			if mainLocals[name] == nil then
				mainLocals[name] = t
			end
		end
		local function readLocalNames(t)
			-- * `local a, b: T, c = ...`
			local j = t + 1
			while toks[j] and toks[j].k == "name" do
				noteLocal(toks[j].v, j)
				j += 1
				if isOp(j, ":") then
					local nesting = 0
					j += 1
					while toks[j] do
						local tok = toks[j]
						if tok.k == "op" then
							if tok.v == "(" or tok.v == "{" or tok.v == "[" or tok.v == "<" then
								nesting += 1
							elseif tok.v == ")" or tok.v == "}" or tok.v == "]" or tok.v == ">" then
								nesting -= 1
							elseif nesting <= 0 and (tok.v == "," or tok.v == "=") then
								break
							end
						elseif nesting <= 0 and (tok.nl or tok.k == "kw") then
							break
						end
						j += 1
					end
				end
				if isOp(j, ",") then
					j += 1
				else
					break
				end
			end
		end

		for t = 1, ntoks do
			local tok = toks[t]
			if tok.k == "kw" then
				local kw = tok.v
				if kw == "local" and funcDepth == 0 then
					if toks[t + 1] and toks[t + 1].k == "kw" and toks[t + 1].v == "function" then
						if toks[t + 2] and toks[t + 2].k == "name" then
							noteLocal(toks[t + 2].v, t + 2)
						end
					else
						readLocalNames(t)
					end
				elseif kw == "for" or kw == "while" then
					pendingLoop = true
				elseif kw == "do" then
					if pendingLoop then
						pendingLoop = false
					end
					blocks[#blocks + 1] = { kind = "do" }
				elseif kw == "repeat" then
					blocks[#blocks + 1] = { kind = "repeat" }
				elseif kw == "function" then
					if not (isOp(t - 1, ":") or isOp(t - 1, "::") or isOp(t - 1, "->")) then
						blocks[#blocks + 1] = { kind = "func", start = t, depth = funcDepth + 1 }
						funcDepth += 1
					end
				elseif kw == "if" then
					pendingIf[#pendingIf + 1] = statementIf(t)
				elseif kw == "then" then
					local isStmt = true
					if #pendingIf > 0 then
						isStmt = pendingIf[#pendingIf]
						pendingIf[#pendingIf] = nil
					end
					blocks[#blocks + 1] = { kind = isStmt and "then" or "thenexpr" }
				elseif kw == "else" then
					local top = blocks[#blocks]
					blocks[#blocks] = nil
					if not (top and top.kind == "thenexpr") then
						blocks[#blocks + 1] = { kind = "then" }
					end
				elseif kw == "elseif" then
					local top = blocks[#blocks]
					blocks[#blocks] = nil
					pendingIf[#pendingIf + 1] = not (top and top.kind == "thenexpr")
				elseif kw == "end" then
					while blocks[#blocks] and blocks[#blocks].kind == "thenexpr" do
						blocks[#blocks] = nil
					end
					local closed = blocks[#blocks]
					blocks[#blocks] = nil
					if closed and closed.kind == "func" then
						funcDepth -= 1
						spans[#spans + 1] = { start = closed.start, stop = t, depth = closed.depth }
					end
				elseif kw == "until" then
					while blocks[#blocks] and blocks[#blocks].kind == "thenexpr" do
						blocks[#blocks] = nil
					end
					blocks[#blocks] = nil
				end
			end
		end

		-- * which top level functions contain the bad lines
		local targets, seen = {}, {}
		for _, line in badLines do
			local found
			for _, span in spans do
				if span.depth == 1 and tokLine(span.start) <= line and line <= tokLine(span.stop) then
					found = span
					break
				end
			end
			if not found then
				return nil, "line " .. line .. " is in the main body of the script, not inside a function"
			end
			if not seen[found] then
				seen[found] = true
				targets[#targets + 1] = found
			end
		end
		table.sort(targets, function(a, b)
			return a.start > b.start -- * splice from the end so earlier offsets stay valid
		end)

		local main = chunk.protos[chunk.main]
		local out = src
		for _, span in targets do
			-- * `(` ... `)` of the parameter list
			local open = span.start + 1
			while toks[open] and not isOp(open, "(") do
				open += 1
			end
			local close, nesting = open, 0
			while toks[close] do
				if isOp(close, "(") then
					nesting += 1
				elseif isOp(close, ")") then
					nesting -= 1
					if nesting == 0 then
						break
					end
				end
				close += 1
			end
			if not toks[close] or close > span.stop then
				return nil, "could not read a function header"
			end

			-- * the decompiler's comments right after the header: "-- Line: N, Name: X" / "-- upvalues: ..."
			local headerComments = sub(src, tokEnd(close) + 1, tokStart(close + 1) - 1)
			local lineDefined = tonumber(match(headerComments, "Line:%s*(%d+)"))
			local debugName = match(headerComments, "Name:%s*([%a_][%w_]*)")
			if not debugName then
				local nameTok = open - 1
				if toks[nameTok] and toks[nameTok].k == "name" then
					debugName = toks[nameTok].v
				end
			end

			local protoId
			local candidates = {}
			for _, id in main.p do
				local proto = chunk.protos[id]
				if lineDefined and proto.linedefined == lineDefined or not lineDefined and debugName and proto.debugname == debugName then
					candidates[#candidates + 1] = id
				end
			end
			if #candidates ~= 1 then
				return nil, "could not match function at line " .. tokLine(span.start) .. " to its bytecode (" .. #candidates .. " candidates)"
			end
			protoId = candidates[1]
			local proto = chunk.protos[protoId]

			-- * upvalue i -> the name the decompiler gave that variable
			local upnames = {}
			local upvalueList = match(headerComments, "upvalues:%s*([^\n]*)")
			if upvalueList then
				for item in string.gmatch(upvalueList, "[^,]+") do
					local name = match(item, "^%s*([%a_][%w_]*)%s*%(")
					if not name then
						return nil, "unreadable upvalue list: " .. upvalueList
					end
					upnames[#upnames + 1] = name
				end
			end
			if #upnames ~= proto.nups then
				return nil, "upvalue count mismatch for function at line " .. tokLine(span.start)
			end
			for _, name in upnames do
				local declared = mainLocals[name]
				if not declared or declared >= span.start then
					return nil, "upvalue '" .. name .. "' is not a local declared before the function"
				end
			end

			-- * the line the function starts on (`x = function(` does not start with `function`)
			local lineStart = tokStart(span.start)
			while lineStart > 1 and sub(src, lineStart - 1, lineStart - 1) ~= "\n" do
				lineStart -= 1
			end
			local indentText = match(src, "^[ \t]*", lineStart) or ""
			local indent = 0
			for _ in string.gmatch(indentText, "\t") do
				indent += 1
			end
			local _, spaces = gsub(indentText, " ", "")
			indent += spaces // 4

			local liftedOk, lifted, globals = pcall(BytecodeLifter.liftFunction, chunk, protoId, upnames, indent)
			if not liftedOk then
				return nil, "could not rebuild function at line " .. tokLine(span.start) .. ": " .. tostring(lifted)
			end
			for name in globals do
				local declared = mainLocals[name]
				if declared and declared < span.start then
					return nil, "global '" .. name .. "' is shadowed by a local of the same name"
				end
			end

			-- * keep the decompiler's (broken) attempt as a comment, it is still the readable one
			local original = sub(src, tokStart(span.start), tokEnd(span.stop))
			local level = ""
			while find(original, "]" .. level .. "]", 1, true) do
				level ..= "="
			end
			local note = indentText
				.. "--[" .. level .. "[ [BetterSaveinstance] The decompiler's version of the function below was broken, so it was rebuilt\n"
				.. indentText .. "     straight from the bytecode: it behaves exactly like the original (registers are __R[n],\n"
				.. indentText .. "     jumps set __pc). The decompiler's attempt, for reading:\n\n"
				.. original
				.. "\n" .. indentText .. "]" .. level .. "]\n"

			lifted = gsub(lifted, "^(%b())", function(params)
				return params .. " -- Line: " .. proto.linedefined .. (proto.debugname and ", Name: " .. proto.debugname or "") .. " (rebuilt from bytecode)"
			end, 1)
			out = sub(out, 1, lineStart - 1)
				.. note
				.. sub(out, lineStart, tokStart(open) - 1)
				.. lifted
				.. sub(out, tokEnd(span.stop) + 1)
		end
		return out, #targets
	end

	--------------------------------------------------------------------------
	-- main entry point
	--------------------------------------------------------------------------

	function RenameDecompiledVariables(src, wantBindings)
		if type(src) ~= "string" or #src < 8 then
			return src
		end
		if not find(src, "[%a_]_?%d") and not wantBindings then -- * nothing that even looks generic
			return src
		end

		-- * Long scripts must not freeze the game, so we hand time back every frame
		local lastStep = clock()
		local function breathe()
			if step and clock() - lastStep >= 0.25 then -- * Rare on purpose: a yielded frame in a heavy place costs far more than the work itself
				step()
				lastStep = clock()
			end
		end

		local pieces, toks, ntoks = lex(src)
		breathe()

		local decls = {}
		local bindOf = {} -- token index -> declaration it refers to
		local taken = {} -- every name already present in the source as a variable / global
		local rootFn = { used = {}, parent = nil, bodyFrom = 1, bodyTo = ntoks, paramCount = 0 }
		local scopes = { {} }
		local scopeFns = { rootFn }
		local nscopes = 1
		local budget = 40000

		local function currentFn()
			for s = nscopes, 1, -1 do
				if scopeFns[s] then
					return scopeFns[s]
				end
			end
			return rootFn
		end

		local function pushScope(fn)
			if fn then
				fn.parent = currentFn()
				fn.used = {}
			end
			nscopes = nscopes + 1
			scopes[nscopes] = {}
			scopeFns[nscopes] = fn or false
		end
		local function popScope(atTok)
			if nscopes <= 1 then
				return
			end
			local fn = scopeFns[nscopes]
			if fn then
				fn.bodyTo = atTok
			end
			scopes[nscopes] = nil
			scopeFns[nscopes] = nil
			nscopes = nscopes - 1
		end
		local function lookup(name)
			for s = nscopes, 1, -1 do
				local d = scopes[s][name]
				if d then
					return d
				end
			end
			return nil
		end

		local function isOp(i, v)
			local t = toks[i]
			return t ~= nil and t.k == "op" and t.v == v
		end
		local function isKw(i, v)
			local t = toks[i]
			return t ~= nil and t.k == "kw" and t.v == v
		end

		local pairCache = {}
		local function matchPair(i)
			local hit = pairCache[i]
			if hit then
				return hit
			end
			local depth = 0
			for j = i, ntoks do
				local t = toks[j]
				if t.k == "op" then
					if OPEN[t.v] then
						depth = depth + 1
					elseif CLOSE[t.v] then
						depth = depth - 1
						if depth == 0 then
							pairCache[i] = j
							return j
						end
					end
				end
			end
			pairCache[i] = ntoks
			return ntoks
		end

		-- * Inside a function body, `do` / `repeat` / an `if` statement open blocks of their own
		-- * that end with `end` / `until`; they must not be mistaken for the function's `end`.
		local function opensInnerBlock(j, blocks)
			if blocks == 0 then
				return false
			end
			local t = toks[j]
			if t.v == "do" or t.v == "repeat" then
				return true
			end
			if t.v ~= "if" then
				return false
			end
			if t.nl then
				return true
			end
			local prev = toks[j - 1]
			return prev ~= nil and ((prev.k == "op" and prev.v == ";")
				or (prev.k == "kw" and (prev.v == "then" or prev.v == "else" or prev.v == "do" or prev.v == "repeat" or prev.v == "end")))
		end

		local function stmtEnd(i)
			local depth, blocks = 0, 0
			local j = i
			while j <= ntoks do
				local t = toks[j]
				if t.nl and j > i and depth == 0 and blocks == 0 then
					return j - 1
				end
				if t.k == "op" then
					if OPEN[t.v] then
						depth = depth + 1
					elseif CLOSE[t.v] then
						if depth == 0 then
							return j - 1
						end
						depth = depth - 1
					elseif t.v == ";" and depth == 0 and blocks == 0 then
						return j - 1
					end
				elseif t.k == "kw" then
					if t.v == "function" or opensInnerBlock(j, blocks) then
						blocks = blocks + 1
					elseif t.v == "end" or t.v == "until" then
						if blocks > 0 then
							blocks = blocks - 1
						elseif depth == 0 then
							return j - 1
						end
					elseif STOPPERS[t.v] and depth == 0 and blocks == 0 and j > i then
						return j - 1
					end
				end
				j = j + 1
			end
			return ntoks
		end

		local function splitLogic(a, b)
			local parts, depth, start = nil, 0, a
			for j = a, b do
				local t = toks[j]
				if t.k == "op" then
					if OPEN[t.v] then
						depth = depth + 1
					elseif CLOSE[t.v] then
						depth = depth - 1
					end
				elseif t.k == "kw" and LOGIC[t.v] and depth == 0 then
					parts = parts or {}
					parts[#parts + 1] = { start, j - 1 }
					start = j + 1
				end
			end
			if parts then
				parts[#parts + 1] = { start, b }
			end
			return parts
		end

		local function findTopLevel(a, b, set)
			local depth, blocks = 0, 0
			for j = a, b do
				local t = toks[j]
				if t.k == "op" then
					if OPEN[t.v] then
						depth = depth + 1
					elseif CLOSE[t.v] then
						depth = depth - 1
					elseif depth == 0 and blocks == 0 and set[t.v] and j > a then
						return j
					end
				elseif t.k == "kw" then
					if t.v == "function" or opensInnerBlock(j, blocks) then
						blocks = blocks + 1
					elseif t.v == "end" or (t.v == "until" and blocks > 0) then
						blocks = blocks - 1
					elseif depth == 0 and blocks == 0 and set[t.v] and j > a then
						return j
					end
				end
			end
			return nil
		end

		local function splitCommas(a, b)
			local parts, depth = {}, 0
			local start = a
			if a > b then
				return parts
			end
			for j = a, b do
				local t = toks[j]
				if t.k == "op" then
					if OPEN[t.v] then
						depth = depth + 1
					elseif CLOSE[t.v] then
						depth = depth - 1
					elseif t.v == "," and depth == 0 then
						parts[#parts + 1] = { start, j - 1 }
						start = j + 1
					end
				end
			end
			parts[#parts + 1] = { start, b }
			return parts
		end

		----------------------------------------------------------------
		-- name inference
		----------------------------------------------------------------

		local inferRange
		local rawNameOf

		local function suffixChain(a, b)
			local t = toks[a]
			if not t then
				return nil
			end
			local chain = {}
			local i = a
			if t.k == "name" then
				chain[1] = { kind = "name", name = t.v, tok = a }
				i = a + 1
			elseif t.k == "op" and t.v == "(" then
				local close = matchPair(a)
				if close > b then
					return nil
				end
				chain[1] = { kind = "paren", a = a + 1, b = close - 1 }
				i = close + 1
			elseif t.k == "str" then
				chain[1] = { kind = "str" }
				i = a + 1
			elseif t.k == "num" then
				chain[1] = { kind = "num" }
				i = a + 1
			elseif t.k == "op" and t.v == "{" then
				local close = matchPair(a)
				if close > b then
					return nil
				end
				chain[1] = { kind = "table", a = a + 1, b = close - 1 }
				i = close + 1
			elseif t.k == "op" and t.v == "..." then
				chain[1] = { kind = "varargs" }
				i = a + 1
			elseif t.k == "kw" and (t.v == "nil" or t.v == "true" or t.v == "false") then
				chain[1] = { kind = t.v }
				i = a + 1
			elseif t.k == "kw" and t.v == "function" then
				return { { kind = "function" } }
			else
				return nil
			end

			while i <= b do
				local c = toks[i]
				if c.k == "op" and c.v == "." and toks[i + 1] and toks[i + 1].k == "name" then
					chain[#chain + 1] = { kind = "field", name = toks[i + 1].v }
					i = i + 2
				elseif c.k == "op" and c.v == "[" then
					local close = matchPair(i)
					if close > b then
						return nil
					end
					chain[#chain + 1] = { kind = "index", a = i + 1, b = close - 1 }
					i = close + 1
				elseif c.k == "op" and c.v == "(" then
					local close = matchPair(i)
					if close > b then
						return nil
					end
					chain[#chain + 1] = { kind = "call", args = splitCommas(i + 1, close - 1) }
					i = close + 1
				elseif c.k == "op" and c.v == ":" and toks[i + 1] and toks[i + 1].k == "name" and isOp(i + 2, "(") then
					local close = matchPair(i + 2)
					if close > b then
						return nil
					end
					chain[#chain + 1] = { kind = "method", name = toks[i + 1].v, args = splitCommas(i + 3, close - 1) }
					i = close + 1
				elseif c.k == "str" then
					chain[#chain + 1] = { kind = "call", args = { { i, i } } }
					i = i + 1
				elseif c.k == "op" and c.v == "{" then
					local close = matchPair(i)
					if close > b then
						return nil
					end
					chain[#chain + 1] = { kind = "call", args = { { i, close } } }
					i = close + 1
				else
					return nil
				end
			end
			return chain
		end

		local function calleePath(chain, upto)
			local parts = {}
			for n = 1, upto do
				local op = chain[n]
				if op.kind == "name" or op.kind == "field" then
					parts[#parts + 1] = op.name
				else
					return nil
				end
			end
			if #parts == 0 then
				return nil
			end
			return concat(parts, "."), parts[#parts], parts[1]
		end

		local function argCount(args)
			if not args or #args == 0 then
				return 0
			end
			if #args == 1 and args[1][1] > args[1][2] then
				return 0
			end
			return #args
		end

		local function nameFromArg(args, skipValueName, singular)
			local first = args and args[1]
			if not first or first[1] > first[2] then
				return nil
			end
			local t = toks[first[1]]
			if t.k == "str" and first[1] == first[2] then
				local text = stringContents(t.v)
				if text and text ~= "" and not looksLikePattern(text) then
					if singular then
						text = singularize(text)
					end
					local clean = sanitize(text)
					if clean and #clean >= 2 then
						return clean
					end
				end
				return nil
			end
			local inner = inferRange(first[1], first[2], skipValueName)
			if inner and singular then
				inner = singularize(inner)
			end
			return inner
		end

		local nameFromChain

		local function nameFromCall(chain, idx, skipValueName)
			local op = chain[idx]
			local path, last, first
			if op.kind == "method" then
				last = op.name
				path = op.name
			else
				path, last, first = calleePath(chain, idx - 1)
				if not path then
					local prev = chain[idx - 1]
					if prev and (prev.kind == "field" or prev.kind == "name") then
						last = prev.name
						path = prev.name
					else
						return nil
					end
				end
			end

			local nargs = argCount(op.args)
			local mapped = METHODS[path] or METHODS[last]
			if mapped == A1 then
				local got = nameFromArg(op.args, skipValueName, nargs >= 2)
				if got then
					return got
				end
			elseif mapped then
				return mapped
			end

			if last == "new" then
				local firstArg = op.args and op.args[1]
				if firstArg and firstArg[1] <= firstArg[2] and toks[firstArg[1]].k == "str" then
					local got = nameFromArg(op.args, skipValueName, false)
					if got then
						return got
					end
				end
				local base = chain[idx - 2]
				local baseName = (base and base.name) or first
				if baseName then
					local clean = sanitize(lower(baseName))
					if clean then
						return clean
					end
				end
			end

			if last == "require" then
				local got = nameFromArg(op.args, skipValueName, false)
				if got then
					return got
				end
			end

			for n = 1, #BOOL_PATTERNS do
				if find(last, BOOL_PATTERNS[n]) then
					return sanitize(last)
				end
			end

			for n = 1, #VERB_PATTERNS do
				local captured = match(last, VERB_PATTERNS[n])
				if captured and captured ~= "" then
					local clean = sanitize(captured)
					if clean then
						return clean
					end
				end
			end

			local firstArg = op.args and op.args[1]
			if firstArg and firstArg[1] <= firstArg[2] and toks[firstArg[1]].k == "str" then
				local got = nameFromArg(op.args, skipValueName, nargs >= 2)
				if got then
					return got
				end
			end

			local base = sanitize(last)
			if base then
				return base .. "_result"
			end
			return nil
		end

		function nameFromChain(chain, skipValueName)
			local n = #chain
			if skipValueName then
				while n > 1 do
					local op = chain[n]
					if op.kind == "field" and (op.name == "Value" or op.name == "Name" or op.name == "Text") then
						n = n - 1
					else
						break
					end
				end
			end

			local last = chain[n]
			if not last then
				return nil
			end
			local kind = last.kind

			if kind == "name" then
				local d = bindOf[last.tok] or lookup(last.name)
				if d then
					if d.rename or isWeakName(d.name) then
						local got = rawNameOf(d)
						if got then
							return got
						end
					end
					if d.rename then
						return nil
					end
					return sanitize(d.name)
				end
				if RESERVED[last.name] then
					return nil
				end
				return sanitize(last.name)
			elseif kind == "field" then
				return sanitize(last.name)
			elseif kind == "str" then
				return "text"
			elseif kind == "num" then
				return "number"
			elseif kind == "table" then
				if last.a > last.b then
					return "tbl"
				end
				if findTopLevel(last.a, last.b, SET_ASSIGN) then
					return "data"
				end
				return "list"
			elseif kind == "varargs" then
				return "args"
			elseif kind == "function" then
				return "callback"
			elseif kind == "nil" then
				return nil
			elseif kind == "true" or kind == "false" then
				return "flag"
			elseif kind == "paren" then
				return inferRange(last.a, last.b, skipValueName)
			elseif kind == "index" then
				local base = nil
				if n >= 2 then
					local head = {}
					for m = 1, n - 1 do
						head[m] = chain[m]
					end
					base = nameFromChain(head, skipValueName)
				end
				local it = toks[last.a]
				if last.a == last.b and it and it.k == "str" then
					local clean = sanitize(stringContents(it.v) or "")
					if clean then
						return clean
					end
				end
				if last.a == last.b and it and it.k == "num" then
					local idx = tonumber(it.v)
					if idx and idx >= 1 and idx <= 10 and idx == floor(idx) then
						local ordinal = ORDINALS[idx]
						if base then
							local one = singularize(base)
							if find(one, "_") then
								return ordinal .. "_" .. one
							end
							return ordinal .. upperFirst(one)
						end
						return ordinal .. "_item"
					end
				end
				if base then
					local one = singularize(base)
					if one ~= base then
						return one
					end
					return base .. "_item"
				end
				return "entry"
			elseif kind == "call" or kind == "method" then
				return nameFromCall(chain, n, skipValueName)
			end
			return nil
		end

		function inferRange(a, b, skipValueName, depth)
			depth = (depth or 0) + 1
			budget = budget - 1
			if a > b or depth > 10 or budget <= 0 then
				return nil
			end
			while isOp(a, "(") and matchPair(a) == b do
				a = a + 1
				b = b - 1
				if a > b then
					return nil
				end
			end

			local parts = splitLogic(a, b)
			if parts then
				-- * `x and x:FindFirstChild("Doors")`: the bare `x` guard tells us nothing,
				-- * so operands that are a single variable are only a last resort
				for pass = 1, 2 do
					for n = 1, #parts do
						local p = parts[n]
						if p[1] <= p[2] then
							local bare = p[1] == p[2] and toks[p[1]].k == "name"
							if pass == 2 or not bare then
								local got = inferRange(p[1], p[2], skipValueName, depth)
								if got then
									return got
								end
							end
						end
					end
				end
				return nil
			end

			local cmp = findTopLevel(a, b, COMPARE)
			if cmp then
				local side = inferRange(a, cmp - 1, true, depth) or inferRange(cmp + 1, b, true, depth)
				if side then
					for n = 1, #BOOL_PATTERNS do
						if find(side, BOOL_PATTERNS[n]) then
							return side
						end
					end
					return "is_" .. lower(side)
				end
				return "matched"
			end

			if findTopLevel(a, b, SET_CONCAT) then
				return "text"
			end

			local art = findTopLevel(a, b, ARITH)
			if art then
				local got = inferRange(a, art - 1, skipValueName, depth)
				if got and got ~= "number" then
					return got
				end
				return "number"
			end

			local head = toks[a]
			if head.k == "kw" and head.v == "not" then
				local got = inferRange(a + 1, b, skipValueName, depth)
				return got and ("not_" .. lower(got)) or "flag"
			end
			if head.k == "op" and head.v == "#" then
				local got = inferRange(a + 1, b, skipValueName, depth)
				return got and (got .. "_count") or "count"
			end
			if head.k == "op" and head.v == "-" then
				return inferRange(a + 1, b, skipValueName, depth)
			end
			if head.k == "kw" and head.v == "if" then
				local thenTok = findTopLevel(a, b, SET_THEN)
				if thenTok then
					return inferRange(thenTok + 1, b, skipValueName, depth)
				end
				return nil
			end

			local chain = suffixChain(a, b)
			if chain then
				return nameFromChain(chain, skipValueName)
			end
			return nil
		end

		----------------------------------------------------------------
		-- parameter inference, from how the parameter is used
		----------------------------------------------------------------

		local function operandAfter(i, limit)
			local depth = 0
			for j = i, limit do
				local t = toks[j]
				if t.nl and j > i and depth == 0 then
					return j - 1
				end
				if t.k == "op" then
					if OPEN[t.v] then
						depth = depth + 1
					elseif CLOSE[t.v] then
						if depth == 0 then
							return j - 1
						end
						depth = depth - 1
					elseif depth == 0 and (t.v == "," or t.v == ";") then
						return j - 1
					end
				elseif t.k == "kw" and depth == 0 and (LOGIC[t.v] or t.v == "then" or t.v == "do" or STOPPERS[t.v]) then
					return j - 1
				end
			end
			return limit
		end

		local function operandBefore(i, limit)
			local depth = 0
			for j = i, limit, -1 do
				local t = toks[j]
				if t.k == "op" then
					if CLOSE[t.v] then
						depth = depth + 1
					elseif OPEN[t.v] then
						if depth == 0 then
							return j + 1
						end
						depth = depth - 1
					elseif depth == 0 and (t.v == "," or t.v == ";" or t.v == "=") then
						return j + 1
					end
				elseif t.k == "kw" and depth == 0 and (LOGIC[t.v] or t.v == "then" or t.v == "if" or STOPPERS[t.v]) then
					return j + 1
				end
			end
			return limit
		end

		local function inferParam(d)
			local fn = d.fn
			local bodyTo = (fn and fn.bodyTo) or ntoks
			local bodyFrom = (fn and fn.bodyFrom) or 1

			if fn and fn.name and d.slot == 1 and fn.paramCount == 1 then
				local captured = match(fn.name, "^[Ss]et_?(%w.*)$")
				if captured and captured ~= "" then
					local clean = sanitize(captured)
					if clean then
						return clean
					end
				end
			end

			-- * only a bare `param == other` tells us what the parameter itself is;
			-- * `param.Name == other` is about the field, not the parameter
			local function isBareRef(ti)
				local after = toks[ti + 1]
				if after and after.k == "op" and (after.v == "." or after.v == ":" or after.v == "[" or after.v == "(") then
					return false
				end
				local before = toks[ti - 1]
				if before and before.k == "op" and (before.v == "." or before.v == ":") then
					return false
				end
				return true
			end

			local refs = d.refs
			for n = 1, #refs do
				local ti = refs[n]
				if isBareRef(ti) then
					local after = toks[ti + 1]
					if after and after.k == "op" and (after.v == "==" or after.v == "~=") then
						local got = inferRange(ti + 2, operandAfter(ti + 2, bodyTo), true)
						if got then
							return got
						end
					end
					local before = toks[ti - 1]
					if before and before.k == "op" and (before.v == "==" or before.v == "~=") then
						local got = inferRange(operandBefore(ti - 2, bodyFrom), ti - 2, true)
						if got then
							return got
						end
					end
				end
			end

			for n = 1, #refs do
				local ti = refs[n]
				if isOp(ti - 1, "(") and toks[ti - 2] and toks[ti - 2].k == "name" then
					local fname = toks[ti - 2].v
					if METHODS[fname] == A1 and (isOp(ti - 3, ":") or isOp(ti - 3, ".")) then
						local recv = toks[ti - 4]
						if recv and recv.k == "name" and not isGenericName(recv.v) then
							local base = sanitize(lower(singularize(recv.v)))
							if base then
								return base .. "_name"
							end
						end
					end
				end
			end

			local sawPlayer, sawInstance, sawCall, sawList = false, false, false, false
			for n = 1, #refs do
				local ti = refs[n]
				if isOp(ti + 1, ".") and toks[ti + 2] and toks[ti + 2].k == "name" then
					local field = toks[ti + 2].v
					if PLAYER_FIELDS[field] then
						sawPlayer = true
					elseif field == "Name" or field == "Parent" or field == "ClassName" then
						sawInstance = true
					end
				elseif isOp(ti + 1, ":") then
					sawInstance = true
				elseif isOp(ti + 1, "(") then
					sawCall = true
				elseif isOp(ti + 1, "[") or isOp(ti - 1, "#") then
					sawList = true
				end
			end
			if sawPlayer then
				return "player"
			end
			if sawList then
				return "list"
			end
			if sawCall then
				return "callback"
			end
			if sawInstance then
				return "instance"
			end

			local a = d.annotation
			if a then
				if a == "string" then
					return "text"
				elseif a == "number" then
					return "number"
				elseif a == "boolean" then
					return "flag"
				elseif a == "Instance" then
					return "instance"
				elseif a ~= "any" and a ~= "unknown" then
					local clean = sanitize(lowerFirst(a))
					if clean then
						return clean
					end
				end
			end

			local generic = d.name
			if find(generic, "^s%d+$") then
				return "text"
			elseif find(generic, "^n%d+$") then
				return "number"
			elseif find(generic, "^b%d+$") then
				return "flag"
			elseif find(generic, "^f%d+$") then
				return "callback"
			elseif find(generic, "^t%d+$") then
				return "tbl"
			end
			return nil
		end

		local function inferLoop(d)
			local info = d.loopInfo
			if not info then
				return nil
			end
			if info.numeric then
				return (info.slot == 1) and "i" or "bound"
			end
			local base, generator = nil, nil
			local collection = info.collection
			if collection then
				local gtok = toks[collection[1]]
				if gtok and gtok.k == "name" then
					generator = gtok.v
				end
				local chain = suffixChain(collection[1], collection[2])
				local tail = chain and chain[#chain]
				if tail and tail.kind == "call" and tail.args and tail.args[1] and tail.args[1][1] <= tail.args[1][2] then
					base = inferRange(tail.args[1][1], tail.args[1][2], false)
				end
				if not base then
					base = inferRange(collection[1], collection[2], false)
				end
			end
			if info.count == 1 then
				return base and singularize(base) or "item"
			elseif info.slot == 1 then
				return (generator == "ipairs" and "i") or "key"
			elseif info.slot == 2 then
				return base and singularize(base) or "value"
			end
			return "extra"
		end

		function rawNameOf(d)
			if d.rawDone then
				return d.raw
			end
			if d.busy then
				return nil
			end
			d.busy = true
			local got = nil
			if d.kind == "param" then
				got = inferParam(d)
			elseif d.kind == "loop" then
				got = inferLoop(d)
			else
				local exprs = d.exprs
				for n = 1, (exprs and #exprs or 0) do
					local e = exprs[n]
					got = inferRange(e[1], e[2], false)
					if got then
						break
					end
				end
			end
			d.busy = false
			d.raw = got and sanitize(got) or nil
			d.rawDone = true
			return d.raw
		end

		----------------------------------------------------------------
		-- pass 1: declarations, references, scopes
		----------------------------------------------------------------

		local function newDecl(name, kind, tokIdx, extra)
			local d = extra or {}
			d.name = name
			d.kind = kind
			d.tokens = { tokIdx }
			d.refs = {}
			d.exprs = d.exprs or {}
			d.rename = isGenericName(name)
			d.fnRec = d.fn or currentFn()
			if not d.rename then
				taken[name] = true
			end
			decls[#decls + 1] = d
			bindOf[tokIdx] = d
			return d
		end

		local function skipType(i)
			local depth = 0
			local j = i
			while j <= ntoks do
				local t = toks[j]
				if t.nl and j > i and depth == 0 then
					return j - 1
				end
				if t.k == "op" then
					if OPEN[t.v] then
						depth = depth + 1
					elseif CLOSE[t.v] then
						if depth == 0 then
							return j - 1
						end
						depth = depth - 1
					elseif depth == 0 and (t.v == "," or t.v == "=" or t.v == ";") then
						return j - 1
					end
				elseif t.k == "kw" and depth == 0 and STOPPERS[t.v] then
					return j - 1
				elseif t.k == "kw" and depth == 0 and (t.v == "do" or t.v == "then" or t.v == "in") then
					return j - 1
				end
				j = j + 1
			end
			return ntoks
		end

		local pendingRegister = {}
		local pendingPop = false
		local braceStack = {}
		local braceScope = {}
		local nbrace = 0
		local blocks = {} -- open blocks: "func" / "do" / "then" / "repeat" / "thenexpr"
		local pendingIf = {} -- for every `if` seen: is it a statement (not a Luau if expression)?

		local function popBlock()
			while #blocks > 0 and blocks[#blocks] == "thenexpr" do
				blocks[#blocks] = nil
			end
			if #blocks > 0 then
				blocks[#blocks] = nil
			end
		end

		-- * `if` starts a statement, or it is a Luau `if a then b else c` expression,
		-- * which has no `end` and must not open a scope
		local function isStatementIf(i)
			local t = toks[i]
			if t.nl then
				return true
			end
			local prev = toks[i - 1]
			if not prev then
				return true
			end
			if prev.k == "op" and prev.v == ";" then
				return true
			end
			if prev.k == "kw" and (prev.v == "then" or prev.v == "else" or prev.v == "do" or prev.v == "repeat" or prev.v == "end") then
				return true
			end
			return false
		end

		local function queueRegister(at, list)
			if #list == 0 then
				return
			end
			local bucket = pendingRegister[at]
			if not bucket then
				bucket = {}
				pendingRegister[at] = bucket
			end
			for n = 1, #list do
				bucket[#bucket + 1] = list[n]
			end
		end

		local ti = 1
		local steps = 0
		while ti <= ntoks do
			steps = steps + 1
			if steps % 4096 == 0 then
				breathe()
			end
			local bucket = pendingRegister[ti]
			if bucket then
				for n = 1, #bucket do
					local d = bucket[n]
					scopes[nscopes][d.name] = d
				end
				pendingRegister[ti] = nil
			end

			local t = toks[ti]
			if pendingPop and t.nl then
				popScope(ti)
				pendingPop = false
			end

			if t.k == "op" then
				if t.v == "{" or t.v == "(" or t.v == "[" then
					nbrace = nbrace + 1
					braceStack[nbrace] = (t.v == "{") and "table" or "other"
					braceScope[nbrace] = nscopes
				elseif CLOSE[t.v] then
					if nbrace > 0 then
						braceStack[nbrace] = nil
						braceScope[nbrace] = nil
						nbrace = nbrace - 1
					end
				end
				ti = ti + 1
			elseif t.k == "kw" then
				local kw = t.v
				if kw == "local" then
					if isKw(ti + 1, "function") and toks[ti + 2] and toks[ti + 2].k == "name" then
						local d = newDecl(toks[ti + 2].v, "localfunc", ti + 2)
						scopes[nscopes][d.name] = d
						ti = ti + 1
					else
						local slots = {}
						local j = ti + 1
						while toks[j] and toks[j].k == "name" do
							local slot = { tok = j, name = toks[j].v }
							slots[#slots + 1] = slot
							j = j + 1
							if isOp(j, ":") then
								local typeEnd = skipType(j + 1)
								if typeEnd == j + 1 and toks[j + 1] and toks[j + 1].k == "name" then
									slot.annotation = toks[j + 1].v
								end
								j = typeEnd + 1
							end
							if isOp(j, ",") then
								j = j + 1
							else
								break
							end
						end
						if #slots == 0 then
							ti = ti + 1
						else
							local created = {}
							local registerAt = j
							local parts = nil
							if isOp(j, "=") then
								local exprEnd = stmtEnd(j + 1)
								parts = splitCommas(j + 1, exprEnd)
								registerAt = exprEnd + 1
							end
							for n = 1, #slots do
								local slot = slots[n]
								local d = {
									annotation = slot.annotation,
									exprs = {},
								}
								d = newDecl(slot.name, "local", slot.tok, d)
								if parts then
									local p = parts[n] or parts[#parts]
									if p and p[1] <= p[2] then
										d.exprs[1] = p
									end
								end
								created[#created + 1] = d
								scopes[nscopes][slot.name] = nil
							end
							queueRegister(registerAt, created)
							ti = slots[#slots].tok + 1
						end
					end
				elseif kw == "function" then
					-- * `callback: function?` is a type annotation, not a definition. Decompilers
					-- * emit those, and opening a scope for one would leave it unclosed.
					if isOp(ti - 1, ":") or isOp(ti - 1, "::") then
						ti = ti + 1
					else
					local fn = { paramCount = 0, bodyFrom = ti, bodyTo = ntoks }
					local j = ti + 1
					if toks[j] and toks[j].k == "name" then
						fn.name = toks[j].v
						-- * `function u1.new()` assigns THROUGH the local `u1`, so the base
						-- * name is an ordinary reference and has to be renamed along with
						-- * its declaration. Only the `.field` / `:method` parts are fields.
						local baseDecl = lookup(fn.name)
						if baseDecl then
							if baseDecl.tokens[1] ~= j then -- not the `local function f` name itself
								bindOf[j] = baseDecl
								if baseDecl.rename then
									baseDecl.refs[#baseDecl.refs + 1] = j
									baseDecl.tokens[#baseDecl.tokens + 1] = j
								end
							end
						elseif not RESERVED[fn.name] and not isGenericName(fn.name) then
							taken[fn.name] = true
						end
						j = j + 1
						while (isOp(j, ".") or isOp(j, ":")) and toks[j + 1] and toks[j + 1].k == "name" do
							fn.name = toks[j + 1].v
							j = j + 2
						end
					else
						local prev = toks[ti - 1]
						if prev and prev.k == "op" and prev.v == "=" then
							local owner = toks[ti - 2]
							if owner and owner.k == "name" then
								fn.name = owner.v
							elseif owner and owner.k == "str" then
								fn.name = stringContents(owner.v)
							end
						end
					end
					blocks[#blocks + 1] = "func"
					pushScope(fn)
					if isOp(j, "(") then
						local close = matchPair(j)
						local k = j + 1
						local slot = 0
						while k < close do
							local pt = toks[k]
							if pt.k == "name" then
								slot = slot + 1
								local annotation = nil
								local after = k + 1
								if isOp(after, ":") then
									local typeEnd = skipType(after + 1)
									if typeEnd == after + 1 and toks[after + 1] and toks[after + 1].k == "name" then
										annotation = toks[after + 1].v
									end
									after = typeEnd + 1
								end
								if pt.v ~= "self" then
									local d = newDecl(pt.v, "param", k, { fn = fn, slot = slot, annotation = annotation })
									scopes[nscopes][pt.v] = d
								end
								k = after
							else
								k = k + 1
							end
						end
						fn.paramCount = slot
						fn.bodyFrom = close + 1
						ti = close + 1
					else
						ti = j
					end
					end
				elseif kw == "for" then
					local names = {}
					local j = ti + 1
					while toks[j] and toks[j].k == "name" do
						names[#names + 1] = { tok = j, name = toks[j].v }
						j = j + 1
						if isOp(j, ":") then
							j = skipType(j + 1) + 1
						end
						if isOp(j, ",") then
							j = j + 1
						else
							break
						end
					end
					local doTok = nil
					local scanTo = j + 4096
					if scanTo > ntoks then
						scanTo = ntoks
					end
					for m = j, scanTo do
						if isKw(m, "do") then
							doTok = m
							break
						end
					end
					local numeric = isOp(j, "=")
					local collection = nil
					if not numeric and isKw(j, "in") and doTok and doTok > j + 1 then
						collection = { j + 1, doTok - 1 }
					end
					local created = {}
					for n = 1, #names do
						local d = newDecl(names[n].name, "loop", names[n].tok, {
							loopInfo = {
								numeric = numeric,
								slot = n,
								count = #names,
								collection = collection,
							},
						})
						created[#created + 1] = d
						scopes[nscopes][names[n].name] = nil
					end
					queueRegister((doTok and doTok + 1) or j, created)
					ti = (names[#names] and names[#names].tok + 1) or (ti + 1)
				elseif kw == "if" then
					pendingIf[#pendingIf + 1] = isStatementIf(ti)
					ti = ti + 1
				elseif kw == "then" then
					local isStmt = true
					if #pendingIf > 0 then
						isStmt = pendingIf[#pendingIf]
						pendingIf[#pendingIf] = nil
					end
					if isStmt then
						blocks[#blocks + 1] = "then"
						pushScope(nil)
					else
						blocks[#blocks + 1] = "thenexpr"
					end
					ti = ti + 1
				elseif kw == "do" or kw == "repeat" then
					blocks[#blocks + 1] = kw
					pushScope(nil)
					ti = ti + 1
				elseif kw == "end" then
					popBlock()
					popScope(ti)
					ti = ti + 1
				elseif kw == "until" then
					popBlock()
					pendingPop = true
					ti = ti + 1
				elseif kw == "else" then
					if blocks[#blocks] == "thenexpr" then
						blocks[#blocks] = nil
					else
						popScope(ti)
						pushScope(nil)
					end
					ti = ti + 1
				elseif kw == "elseif" then
					if blocks[#blocks] == "thenexpr" then
						blocks[#blocks] = nil
						pendingIf[#pendingIf + 1] = false
					else
						popBlock()
						popScope(ti)
						pendingIf[#pendingIf + 1] = true
					end
					ti = ti + 1
				else
					ti = ti + 1
				end
			elseif t.k == "name" then
				local prev = toks[ti - 1]
				local isField = prev ~= nil and prev.k == "op" and (prev.v == "." or prev.v == ":")
				local isKey = false
				-- * a table key, but only when we are directly inside the constructor;
				-- * `{ f = function() v16 = 1 end }` assigns to the variable, it is no key
				if not isField and braceStack[nbrace] == "table" and braceScope[nbrace] == nscopes and isOp(ti + 1, "=") then
					if prev and prev.k == "op" and (prev.v == "{" or prev.v == "," or prev.v == ";") then
						isKey = true
					end
				end
				if not isField and not isKey then
					local d = lookup(t.v)
					if d then
						bindOf[ti] = d
						if d.rename then
							d.refs[#d.refs + 1] = ti
							d.tokens[#d.tokens + 1] = ti
							if isOp(ti + 1, "=") and (t.nl or (prev and prev.k == "op" and prev.v == ";")) then
								local e = stmtEnd(ti + 2)
								if ti + 2 <= e then
									d.exprs[#d.exprs + 1] = { ti + 2, e }
								end
							end
						end
					elseif not RESERVED[t.v] and not isGenericName(t.v) then
						taken[t.v] = true
					end
				end
				ti = ti + 1
			else
				ti = ti + 1
			end
		end

		----------------------------------------------------------------
		-- pass 2: settle on the final names and write them back
		----------------------------------------------------------------

		local FALLBACK = { param = "value", loop = "item", ["local"] = "value", localfunc = "callback" }
		local renamed = 0

		-- * A name is free for this declaration when nothing in the source already uses it
		-- * and no other new name in this function or any function enclosing it uses it.
		-- * Sibling functions can therefore reuse the same name without ever shadowing.
		local function isFree(name, fnRec)
			if taken[name] or RESERVED[name] then
				return false
			end
			local rec = fnRec
			while rec do
				if rec.used and rec.used[name] then
					return false
				end
				rec = rec.parent
			end
			return true
		end

		for n = 1, #decls do
			if n % 2048 == 0 then
				breathe()
			end
			local d = decls[n]
			if d.rename then
				local base = rawNameOf(d)
				if not base or base == "" then
					base = FALLBACK[d.kind] or "value"
				end
				local fnRec = d.fnRec or rootFn
				fnRec.used = fnRec.used or {}
				fnRec.cursor = fnRec.cursor or {}
				-- * resume where this base name left off: without the cursor, N locals
				-- * that all infer the same name would cost N^2 to number
				local cursor = fnRec.cursor
				local suffix = cursor[base] or 1
				local final = (suffix == 1) and base or (base .. "_" .. suffix)
				while not isFree(final, fnRec) or isGenericName(final) do
					suffix = suffix + 1
					final = base .. "_" .. suffix
					if isGenericName(final) or suffix > 400 then
						-- * `i_7` would just be another generic name, so widen the base instead
						base = ALIAS[base] or (base .. "_value")
						suffix = cursor[base] or 1
						final = (suffix == 1) and base or (base .. "_" .. suffix)
					end
				end
				cursor[base] = suffix
				fnRec.used[final] = true
				d.final = final
				for m = 1, #d.tokens do
					pieces[toks[d.tokens[m]].i] = final
				end
				renamed = renamed + 1
			end
		end

		-- * debug only: a fingerprint of "which declaration does every identifier bind to".
		-- * Renaming must never change it; the test harness compares input against output.
		local bindings = nil
		if wantBindings then
			local out = {}
			for i = 1, ntoks do
				if toks[i].k == "name" then
					local d = bindOf[i]
					out[#out + 1] = d and d.tokens[1] or 0
				end
			end
			bindings = concat(out, ",")
		end

		if renamed == 0 then
			return src, bindings
		end
		local result = concat(pieces)
		-- * Safety net: renaming must never leave a reference to a variable that no longer
		-- * exists (it would read nil at runtime). Any name that is free afterwards but was not
		-- * free before means a reference was missed, so the script is kept as it was.
		local before, after = FreeNames(src), FreeNames(result)
		for name in after do
			if not before[name] then
				return src, bindings
			end
		end
		return result, bindings
	end

	-- * Names a script reads without declaring them (globals, as far as text can tell)
	function FreeNames(src)
		local _, toks, ntoks = lex(src)
		local declared, used = {}, {}
		local function isOp(i, v)
			local t = toks[i]
			return t ~= nil and t.k == "op" and t.v == v
		end
		local function skipType(i)
			-- * `name: Type` up to the next `,` `=` `)` or line, at bracket depth 0
			local depth = 0
			while i <= ntoks do
				local t = toks[i]
				if t.k == "op" then
					if OPEN[t.v] then
						depth += 1
					elseif CLOSE[t.v] then
						if depth == 0 then
							return i
						end
						depth -= 1
					elseif depth == 0 and (t.v == "," or t.v == "=") then
						return i
					end
				elseif depth == 0 and t.nl then
					return i
				elseif depth == 0 and t.k == "kw" and (t.v == "in" or t.v == "do") then
					return i
				end
				i += 1
			end
			return i
		end
		local function nameList(i)
			while toks[i] and toks[i].k == "name" do
				declared[toks[i].v] = true
				i += 1
				if isOp(i, ":") then
					i = skipType(i + 1)
				end
				if isOp(i, ",") then
					i += 1
				else
					break
				end
			end
			return i
		end
		for i = 1, ntoks do
			local t = toks[i]
			if t.k == "kw" then
				if t.v == "local" then
					if toks[i + 1] and toks[i + 1].k == "kw" and toks[i + 1].v == "function" then
						if toks[i + 2] and toks[i + 2].k == "name" then
							declared[toks[i + 2].v] = true
						end
					else
						nameList(i + 1)
					end
				elseif t.v == "for" then
					nameList(i + 1)
				elseif t.v == "function" then
					local j = i + 1
					while toks[j] and toks[j].k == "name" and (isOp(j + 1, ".") or isOp(j + 1, ":")) do
						j += 2
					end
					if toks[j] and toks[j].k == "name" then
						j += 1
					end
					if isOp(j, "(") then
						nameList(j + 1)
					end
				end
			elseif t.k == "name" then
				local prev = toks[i - 1]
				local isField = prev and prev.k == "op" and (prev.v == "." or prev.v == ":" or prev.v == "::")
				-- * `{ key = value }` keys are not variables
				local isKey = isOp(i + 1, "=") and prev and prev.k == "op" and (prev.v == "{" or prev.v == "," or prev.v == ";")
				if not isField and not isKey then
					used[t.v] = true
				end
			end
		end
		local free = {}
		for name in used do
			if not declared[name] and name ~= "self" then
				free[name] = true
			end
		end
		return free
	end
end

local function synsaveinstance(CustomOptions, CustomOptions2)
	if GLOBAL_ENV.USSI then
		return
	end
	GLOBAL_ENV.USSI = true
	do
		local setthreadidentity = global_container.setthreadidentity
		if setthreadidentity then
			pcall(setthreadidentity, 8) -- ? Arceus X Fix
		end
	end

	local currentstr, currentsize, totalsize, chunks = "", 0, 0, table.create(1)
	local savebuffer, savebuffer_size = {}, 1
	local header =
		'<!-- Saved by UniversalSynSaveInstance (Join to Copy Games) https://discord.gg/wx4ThpAsmw --><roblox version="4">'

	local StatusText

	local OPTIONS = {
		mode = "optimized",
		noscripts = false,
		scriptcache = true,
		decomptype = "builtin",
		timeout = 10,
		-- * New:
		__DEBUG_MODE = false,
		Crashlog = false,
		-- Binary = false, -- true in syn newer versions (false in our case because no binary support yet), Description: Saves everything in Binary Mode (rbxl/rbxm).
		Callback = false,
		--Clipboard/CopyToClipboard = false, -- Description: If set to true, the serialized data will be set to the clipboard, which can be later pasted into studio easily. Useful for saving models. -- Seems to not work with XML form
		-- MaxThreads = 3 -- Description: The number of decompilation threads that can run at once. More threads means it can decompile for scripts at a time.
		-- DisableCompression = false, --Description: Disables compression in the binary output

		RenameVariables = true,
		ScriptHeaders = false,
		MatchLineNumbers = true,
		FixGoto = true,
		DecompilerFallback = true,
		RebuildFromBytecode = true,
		DecompileJobless = false,
		DecompileIgnore = { -- * Clean these up (merged Old Syn and New Syn)
			-- "Chat",
			"TextChatService",
			ModuleScript = nil,
		},
		IgnoreDefaultPlayerScripts = not ArrayToDict({ "Wave", "Potassium", "Volcano", "Solara"})[EXECUTOR_NAME],
		SaveBytecode = false,
		SaveBytecodeIfDecompilerFails = false,
		SaveCompilationErrors = true,
		IgnoreProperties = {},

		IgnoreList = { "CoreGui", "CorePackages" },
		SaveAsAttributes = false,
		ExtraInstances = {},
		NilInstances = false,
		NilInstancesFixes = {},

		SaveCacheInterval = 0x1600 * 10,
		ShowStatus = true,
		SafeMode = false,
		ShutdownWhenDone = false,
		AntiIdle = true,
		Anonymous = false,
		ReadMe = true,
		FilePath = false,
		Object = false,
		IsModel = false,

		IgnoreDefaultProperties = true,
		IgnoreNotArchivable = true,
		IgnorePropertiesOfNotScriptsOnScriptsMode = false,
		IgnoreSpecialProperties = ArrayToDict({ "Fluxus", "Solara", "WRD", "JJSploit x Xeno"})[EXECUTOR_NAME] or false, -- ! Please submit more Executors that crash on gethiddenproperty (with this disabled basically). Visual is becaues binarystring gets cut off, JJSploit is because gethiddenproperty returns 0 when it can't read a property instead of failing.

		IsolateLocalPlayer = false, --  #service.StarterGui:GetChildren() == 0
		IsolateLocalPlayerCharacter = false,
		IsolatePlayers = false,
		IsolateStarterPlayer = false,
		RemovePlayerCharacters = true,

		SaveNotCreatable = false,
		NotCreatableFixes = {
			-- "CloudLocalizationTable",
			-- "InputObject",
			-- "LodDataEntity",
			-- "Path",
			-- "Translator",
			"", -- * FilteredSelection
			"AnimationTrack",
			"Player",
			"PlayerGui",
			"PlayerScripts",
			"PlayerMouse",
			"ScreenshotHud",
			"StudioData",
			"TextSource",
			"TouchTransmitter",
			"Dragger",
			"AdvancedDragger"
		},
		SavePropsAsAttributesForNotCreatableFixes = false,
		-- ! Risky

		IgnoreSharedStrings = not ArrayToDict({ "Wave", "Zenith", "Swift", "Potassium", "Volcano", "Velocity"})[EXECUTOR_NAME],
		SharedStringOverwrite = false,
		TreatUnionsAsParts = ArrayToDict({ "Solara", "Xeno", "WRD", "Zorara", "JJSploit x Xeno" })[EXECUTOR_NAME] or false,
		AlternativeWritefile = not ArrayToDict({ "WRD", "Xeno", "Zorara", "JJSploit x Xeno" })[EXECUTOR_NAME],

		OptionsAliases = { -- You can't really modify these as a user
			DecompileTimeout = "timeout",
			FileName = "FilePath",
			IgnoreArchivable = "IgnoreNotArchivable",
			IgnoreDefaultProps = "IgnoreDefaultProperties",
			SaveNonCreatable = "SaveNotCreatable",
			SavePlayers = "IsolatePlayers",
			IsolatePlayerGui = "IsolateLocalPlayer",
		},
	}

	local OPTIONS_lowercase, CustomOptions_valid = {}, {}
	for option_name in OPTIONS do
		local option_name_lowercase = string.lower(option_name)
		if OPTIONS_lowercase[option_name_lowercase] then
			warn("DUPLICATE OPTION", option_name)
		else
			OPTIONS_lowercase[option_name_lowercase] = option_name
		end
	end
	for option_alias, option_name in OPTIONS.OptionsAliases do
		local option_name_lowercase = string.lower(option_alias)
		if OPTIONS_lowercase[option_name_lowercase] then
			warn("DUPLICATE ALIAS", option_alias)
		else
			OPTIONS_lowercase[option_name_lowercase] = option_name
		end
	end

	do -- * Load Settings
		local function construct_NilinstanceFix(Name, ClassName, Separate)
			return function(instance, instancePropertyOverrides)
				local Exists

				if not Separate then
					Exists = OPTIONS.NilInstancesFixes[Name]
				end

				local Fix

				local DoesntExist = not Exists
				if DoesntExist then
					Fix = Instance.new(ClassName)
					if not Separate then
						OPTIONS.NilInstancesFixes[Name] = Fix
					end
					-- Fix.Name = Name

					instancePropertyOverrides[Fix] =
						{ __SaveSpecific = true, __Children = { instance }, Properties = { Name = Name } }
				else
					Fix = Exists
					table.insert(instancePropertyOverrides[Fix].__Children, instance)
				end

				-- InstancesOverrides[instance].Parent = AnimationController
				if DoesntExist then
					return Fix
				end
			end
		end

		-- TODO: Merge BaseWrap & Attachment & AdPortal fix (put all under MeshPart container)
		-- TODO?:
		-- DebuggerWatch DebuggerWatch must be a child of ScriptDebugger
		-- PluginAction Parent of PluginAction must be Plugin or PluginMenu that created it!
		OPTIONS.NilInstancesFixes.Animator = 
			construct_NilinstanceFix("Animator has to be placed under Humanoid or AnimationController", "AnimationController")
		OPTIONS.NilInstancesFixes.AdPortal = 
			construct_NilinstanceFix("AdPortal must be parented to a Part", "Part")
		OPTIONS.NilInstancesFixes.Attachment =
			construct_NilinstanceFix("Attachments must be parented to a BasePart or another Attachment", "Part") -- * Bones inherit from Attachments
		OPTIONS.NilInstancesFixes.BaseWrap =
			construct_NilinstanceFix("BaseWrap must be parented to a MeshPart", "MeshPart")
		OPTIONS.NilInstancesFixes.PackageLink =
			construct_NilinstanceFix("Package already has a PackageLink", "Folder", true)
		if CustomOptions2 and type(CustomOptions2) == "table" then
			local tmp = CustomOptions
			local Type = typeof(tmp)
			CustomOptions = CustomOptions2
			if Type == "Instance" then
				CustomOptions.Object = tmp
			elseif Type == "table" and typeof(tmp[1]) == "Instance" then
				CustomOptions.ExtraInstances = tmp
				OPTIONS.IsModel = true
			end
		end

		local Type = typeof(CustomOptions)

		if Type == "table" then
			if typeof(CustomOptions[1]) == "Instance" then
				OPTIONS.mode = "invalidmode"
				OPTIONS.ExtraInstances = CustomOptions
				OPTIONS.IsModel = true
				CustomOptions = {}
			else
				for key, value in CustomOptions do
					local option = OPTIONS_lowercase[string.lower(key)]

					if option then
						OPTIONS[option] = value
						CustomOptions_valid[option] = true
					end
				end
				local Decompile = CustomOptions.Decompile
				if Decompile ~= nil then
					OPTIONS.noscripts = not Decompile
				end
				local SavePlayerCharacters = CustomOptions.SavePlayerCharacters
				if SavePlayerCharacters ~= nil then
					OPTIONS.RemovePlayerCharacters = not SavePlayerCharacters
				end
				local RemovePlayers = CustomOptions.RemovePlayers
				if RemovePlayers ~= nil then
					OPTIONS.IsolatePlayers = not RemovePlayers
				end
			end
		elseif Type == "Instance" then
			OPTIONS.mode = "invalidmode"
			OPTIONS.Object = CustomOptions
			CustomOptions = {}
		else
			CustomOptions = {}
		end
	end

	if OPTIONS.IgnoreDefaultPlayerScripts then
		-- TODO This is a bad workaround, find a better automatic way
		-- TODO Look into https://robloxapi.github.io/ref/class/LuaSourceContainer.html#member-isPlayerScript
		local DecompileIgnore = OPTIONS.DecompileIgnore

		local Path = service.StarterPlayer:FindFirstChild("StarterPlayerScripts")
		local Exclude = { ModuleScript = { "PlayerModule" }, LocalScript = { "RbxCharacterSounds" } }
		if Path then
			for _, className in Exclude do
				for _, name in className do
					local Found = Path:FindFirstChild(name)
					if Found then
						table.insert(DecompileIgnore, Found)
					end
				end
			end
		end
	end

	local InstancesOverrides = {}

	local DecompileIgnore, IgnoreList, IgnoreProperties, NotCreatableFixes =
		ArrayToDict(OPTIONS.DecompileIgnore, true),
		ArrayToDict(OPTIONS.IgnoreList, true),
		ArrayToDict(OPTIONS.IgnoreProperties),
		ArrayToDict(OPTIONS.NotCreatableFixes, true, "Folder")
		
	local Crashlog = OPTIONS.Crashlog
	local __DEBUG_MODE = OPTIONS.__DEBUG_MODE
	local old_warn
	
	if Crashlog and not old_warn then
		__DEBUG_MODE = true
		local CRASHLOG_ID = service.HttpService:GenerateGUID(false)
		writefile("CRASHLOG_"..CRASHLOG_ID, "BetterSaveinstance crashlog (id:"..CRASHLOG_ID..", placeid:"..tostring(game.PlaceId)..") below")
		Crashlog = function(text)
			appendfile("CRASHLOG_"..CRASHLOG_ID, "\n ["..tostring(DateTime.now().UnixTimestampMillis).."] "..text)
		end
		old_warn = warn
		function warn(...)
			old_warn(...)
			local text = table.concat({...}, " ")
			Crashlog(text)
		end
	end

	if __DEBUG_MODE and type(__DEBUG_MODE) ~= "function" then
		__DEBUG_MODE = warn
	end

	local FilePath = OPTIONS.FilePath
	local SaveCacheInterval = OPTIONS.SaveCacheInterval
	local ToSaveInstance = OPTIONS.Object
	local IsModel = OPTIONS.IsModel

	if ToSaveInstance and CustomOptions.IsModel == nil then
		IsModel = true
	end

	local IgnoreDefaultProperties = OPTIONS.IgnoreDefaultProperties
	local IgnoreNotArchivable = not OPTIONS.IgnoreNotArchivable
	local IgnorePropertiesOfNotScriptsOnScriptsMode = OPTIONS.IgnorePropertiesOfNotScriptsOnScriptsMode

	local old_gethiddenproperty
	if OPTIONS.IgnoreSpecialProperties and gethiddenproperty then
		old_gethiddenproperty = gethiddenproperty
		gethiddenproperty = nil
	end
	
	local SaveAsAttributes = OPTIONS.SaveAsAttributes
	local SaveNotCreatable = OPTIONS.SaveNotCreatable
	local SavePropsAsAttributesForNotCreatableFixes = OPTIONS.SavePropsAsAttributesForNotCreatableFixes
	if SavePropsAsAttributesForNotCreatableFixes then
		SaveNotCreatable = true
	end
	local TreatUnionsAsParts = OPTIONS.TreatUnionsAsParts

	local RenameVariables = OPTIONS.RenameVariables
	local ScriptHeaders = OPTIONS.ScriptHeaders
	local MatchLineNumbers = OPTIONS.MatchLineNumbers
	local FixGoto = OPTIONS.FixGoto
	local DecompilerFallback = OPTIONS.DecompilerFallback
	local RebuildFromBytecode = OPTIONS.RebuildFromBytecode
	local DecompileJobless = OPTIONS.DecompileJobless
	if DecompileJobless then
		OPTIONS.scriptcache = true
	end
	local ScriptCache = OPTIONS.scriptcache and getscriptbytecode

	local Timeout = OPTIONS.timeout
	local Anonymous
	if OPTIONS.Anonymous then
		Anonymous = type(OPTIONS.Anonymous) == "table" and OPTIONS.Anonymous
						or { UserId = "1", Name = "Roblox" }
	end
	local IgnoreSharedStrings = OPTIONS.IgnoreSharedStrings
	local SharedStringOverwrite = OPTIONS.SharedStringOverwrite

	local ldeccache = GLOBAL_ENV.scriptcache

	local DecompileIgnoring, ToSaveList, ldecompile, placename, elapse_t, SaveNotCreatableWillBeEnabled, RecoveredScripts

	if OPTIONS.ReadMe then
		RecoveredScripts = {}
	end

	-- * The cache lives in the executor's global environment, so it outlives this run. Output from an
	-- * older saveinstance (or another decompiler) must not be reused: bump CACHE_VERSION whenever
	-- * decompiled output changes.
	local CACHE_VERSION = "2026-10-07h " .. string.lower(tostring(OPTIONS.decomptype or "")) .. (OPTIONS.MatchLineNumbers == false and " compact" or "")
	if ldeccache and (type(ldeccache) ~= "table" or ldeccache.__version ~= CACHE_VERSION) then
		ldeccache = nil
	end
	if ScriptCache and not ldeccache then
		ldeccache = { __version = CACHE_VERSION }
		GLOBAL_ENV.scriptcache = ldeccache
	end

	if ToSaveInstance == game then
		OPTIONS.mode = "full"
		ToSaveInstance = nil
		IsModel = nil
	end

	local function isLuaSourceContainer(instance)
		return instance:IsA("LuaSourceContainer")
	end

	do
		local mode = OPTIONS.mode
		local modetype = type(mode) -- if mode is a table of strings then it is a custom mode
		if modetype == "string" then
			mode = string.lower(mode)
		end
		local tmp = table.clone(OPTIONS.ExtraInstances)

		local PlaceName = game.PlaceId

		pcall(function()
			PlaceName ..= " " .. service.MarketplaceService:GetProductInfo(PlaceName).Name
		end)

		local function sanitizeFileName(str)
			return string.sub(string.gsub(string.gsub(string.gsub(str, "[^%w _]", ""), " +", " "), " +$", ""), 1, 240)
		end

		if ToSaveInstance then
			if mode == "optimized" then -- ! NOT supported with Model file mode
				mode = "full"
			end

			for _, key in
				{
					"IsolateLocalPlayer",
					"IsolateLocalPlayerCharacter",
					"IsolatePlayers",
					"IsolateStarterPlayer",
					"NilInstances",
				}
			do
				if CustomOptions_valid[key] == nil then
					OPTIONS[key] = false
				end
			end
		end

		local Filetype
		if IsModel then
			FileType = ".rbxmx"
			placename = (
				FilePath
				or sanitizeFileName("model " .. PlaceName .. " " .. (ToSaveInstance or tmp[1] or game):GetFullName())
			)
		else
			FileType = ".rbxlx"
			placename = (FilePath or sanitizeFileName("place " .. PlaceName))
		end

		-- Simple loop to find an avbaible file name. Not the most elegant or optimized solution, this is the only repeat loop in the entire file, but it shouldn't impact performance unless you are saving with the same filename 1 million times.
		local PlaceNameCounter = 1
		local TempName
		repeat
			if PlaceNameCounter == 1 then
				TempName = placename
			else
				TempName = placename .. "(" .. PlaceNameCounter .. ")"
			end
			PlaceNameCounter = PlaceNameCounter + 1
		until not isfile(TempName .. FileType)
		placename = TempName .. FileType

		if GLOBAL_ENV[placename] then
			-- warn("UniversalSynSaveInstance is already saving to this file")
			return
		end

		GLOBAL_ENV[placename] = true
		GLOBAL_ENV.USSI = nil
		if mode ~= "scripts" then
			IgnorePropertiesOfNotScriptsOnScriptsMode = nil
		end

		local TempRoot = ToSaveInstance or game

		if mode == "full" then
			if not ToSaveInstance then
				local Children = TempRoot:GetChildren()
				if 0 < #Children then
					local tmp_dict = ArrayToDict(tmp)
					for _, child in Children do
						if not tmp_dict[child] then
							table.insert(tmp, child)
						end
					end
				end
			end
		elseif mode == "optimized" or type(mode) == "table" then -- ! Incompatible with .rbxmx (Model file) mode
			-- if IsolatePlayers then
			-- 	table.insert(_list_0, "Players")
			-- end
			local tmp_dict = ArrayToDict(tmp)
			local ServicesToSave
			if mode == "optimized" then
				ServicesToSave = {
					"Workspace",
					"Players",
					"Lighting",
					"MaterialService",
					"ReplicatedFirst",
					"ReplicatedStorage",

					"ServerScriptService", -- LoadStringEnabled property (doesn't replicate); Just in case
					"ServerStorage", -- Just in case

					"StarterGui",
					"StarterPack",
					"StarterPlayer",
					"Teams",
					"SoundService",
					"Chat",
					"TextChatService",

					"LocalizationService", -- For LocalizationTables
					-- "InsertService",
					"JointsService",

					-- "TestService",
					-- "VoiceChatService",
				}
			else
				ServicesToSave = mode
			end	
			for _, serviceName in ServicesToSave do
				local _service = game:FindService(serviceName)
				if _service and not tmp_dict[_service] then
					table.insert(tmp, _service)
				end
			end
		elseif mode == "scripts" then
			-- TODO: Only save paths that lead to scripts (nothing else)
			-- Currently saves paths along with children of each tree
			local unique = {}
			for _, instance in TempRoot:GetDescendants() do
				if isLuaSourceContainer(instance) then
					local Parent = instance.Parent
					while Parent and Parent ~= TempRoot do
						instance = instance.Parent
						Parent = instance.Parent
					end
					if Parent then
						unique[instance] = true
					end
				end
			end
			for instance in unique do
				table.insert(tmp, instance)
			end
		end

		ToSaveList = tmp

		if ToSaveInstance then
			table.insert(ToSaveList, 1, ToSaveInstance)
		end
	end

	local IsolateLocalPlayer = OPTIONS.IsolateLocalPlayer
	local IsolateLocalPlayerCharacter = OPTIONS.IsolateLocalPlayerCharacter
	local IsolatePlayers = OPTIONS.IsolatePlayers
	local IsolateStarterPlayer = OPTIONS.IsolateStarterPlayer
	local NilInstances = OPTIONS.NilInstances

	if NilInstances and enablenilinstances then -- ? Solara fix
		enablenilinstances()
	end
	local function get_size_format()
		local Size

		-- local totalsize = #totalstr

		for i, unit in
			{
				"B",
				"KB",
				"MB",
				"GB",
				"TB",
			}
		do
			if totalsize < 0x400 ^ i then
				Size = math.floor(totalsize / (0x400 ^ (i - 1)) * 10) / 10 .. " " .. unit
				break
			end
		end

		return Size
	end

	local RunService = service.RunService
	local function wait_for_render()
		RunService.RenderStepped:Wait()
	end

	local Loading
	local function run_with_loading(text, keepStatus, waitForRender, taskFunction, ...)
		local previousStatus

		if StatusText then
			if keepStatus then
				previousStatus = StatusText.Text
			end
			Loading = task.spawn(function()
				local spinner_count = 0
				local chars = { "|", "/", "—", "\\" }
				local chars_size = #chars

				local function getLoadingText()
					spinner_count += 1

					if chars_size < spinner_count then
						spinner_count = 1
					end

					return chars[spinner_count]
				end

				text ..= " "

				while true do
					StatusText.Text = text .. getLoadingText()
					task.wait(0.25)
				end
			end)
			if waitForRender then
				wait_for_render()
			end
		end

		local result = { taskFunction(...) }

		if Loading then
			task.cancel(Loading)
			Loading = nil
			if previousStatus then
				StatusText.Text = previousStatus
			end
		end

		return unpack(result)
	end

	local function construct_TimeoutHandler(timeout, f, timeout_ret)
		return timeout < 0 and function(script)
			return pcall(f, script)
		end or function(script) -- TODO Ideally use ... (vararg) instead of `script` in case this is reused for something other than `decompile` & `getscriptbytecode`
			if f == getscriptbytecode then
				if Crashlog then Crashlog("  Getting bytecode for "..script:GetFullName()) end
			end
			local thread = coroutine.running()
			local finished, waiting, timedOut, timeoutThread
			local ok, result

			-- * task.spawn runs the worker right away. Native decompilers / getscriptbytecode
			-- * never yield, so they are already finished when task.spawn returns and we hand
			-- * the result back in the same frame. Only a call that actually yields (HTTP or
			-- * Luau-based decompilers) has to wait, and only then is the timeout armed.
			task.spawn(function()
				local o, r = pcall(f, script)
				if timedOut then
					return
				end
				finished, ok, result = true, o, r
				if waiting then
					task.cancel(timeoutThread)
					task.spawn(thread, o, r)
				end
			end)

			if finished then
				return ok, result
			end

			waiting = true
			timeoutThread = task.delay(timeout, function()
				if finished then
					return
				end
				timedOut = true
				task.spawn(thread, nil, timeout_ret)
			end)

			return coroutine.yield()
		end
	end

	local getbytecode
	if getscriptbytecode then
		getbytecode = construct_TimeoutHandler(3, getscriptbytecode) -- ? Solara fix
	end

	local SaveBytecode
	if OPTIONS.SaveBytecode then
		OPTIONS.SaveBytecodeIfDecompilerFails = false
	end
	if OPTIONS.SaveCompilationErrors and getscriptbytecode then
		CompilationError = function(script)
			local s, bytecode = getbytecode(script)

			if s and bytecode and bytecode ~= "" then
				if string.byte(bytecode, 1, 1) == 0 then -- in scripts that failed to compile, byte 1, the version header (which is 6 is all other cases) is replaced with a null byte. Look a konstant source code for proof.
					return("-- The script has a compilation error:\n-- "..string.sub(bytecode, 2)) -- the formatted string for a compilation error. String.sub is to cut off the heading byte.
				end
			end		
		end	
	end
	
	if (OPTIONS.SaveBytecode or OPTIONS.SaveBytecodeIfDecompilerFails) and getscriptbytecode then
		SaveBytecode = function(script)
			local s, bytecode = getbytecode(script)

			if s and bytecode and bytecode ~= "" then
				return "-- Bytecode (Base64):\n-- " .. base64encode(bytecode) .. "\n\n"
			end
		end
	end
	local KONSTANT_URL = "https://raw.githubusercontent.com/exacaca/BetterSaveinstance/refs/heads/main/Dependencies/Konstant%20V2.1.luau"
	local KonstantModule -- * nil = not tried yet, false = failed to load
	local function GetKonstant()
		if KonstantModule == nil then
			KonstantModule = false
			if __DEBUG_MODE then __DEBUG_MODE("Attempting to load Konstant Decompiler. If there is an error/crash after this, set the option decomptype to any string other than custom") end
			local ok, konstant = pcall(function()
				return loadstring(game:HttpGet(KONSTANT_URL, true), "Konstant")()
			end)
			if ok and type(konstant) == "table" and type(konstant.decompile) == "function" then
				KonstantModule = konstant
				if __DEBUG_MODE then __DEBUG_MODE("Konstant Decompiler loaded") end
			else
				warn("Failed to load the Konstant decompiler:", konstant)
			end
		end
		return KonstantModule or nil
	end

	-- * "builtin" (default): BetterDecompiler, in this file. "executor": the executor's own
	-- * `decompile`. "custom": Konstant.
	local DecompType = string.lower(tostring(OPTIONS.decomptype or ""))
	if DecompType == "" then
		DecompType = "builtin"
	end
	local ExecutorDecompiler = decompile
	local UsingKonstant = false
	if getscriptbytecode then
		if DecompType == "custom" or (DecompType == "executor" and ExecutorDecompiler == nil) then
			local konstant = GetKonstant()
			if konstant then
				ExecutorDecompiler = konstant.decompile
				UsingKonstant = true
			end
		end
	end

	local BuiltinDecompile
	if DecompType == "builtin" and getscriptbytecode then
		-- * No yielding in the middle of a script: pausing mid-decompile made random functions
		-- * fall back to low level on some executors.
		BetterDecompiler.onFunction = nil
		do
			-- * The file asks for `--!optimize 1`. If an executor compiled it with -O2 anyway, Luau's
			-- * inliner bug is live (this builds a node that contains itself) and output can be wrong.
			local function probe(k, t)
				t = t or {}
				t.k = k
				return t
			end
			local node = probe("a", {})
			node = probe("b", { obj = node })
			if node.obj == node then
				warn("[BetterSaveinstance] This executor compiled saveinstance with -O2 (ignoring --!optimize 1). Luau's -O2 inliner has a bug that can corrupt decompiled scripts; report your executor's name.")
			end
		end
		BuiltinDecompile = function(script)
			local bytecode = getscriptbytecode(script)
			if type(bytecode) ~= "string" or bytecode == "" then
				error("could not read the script's bytecode", 0)
			end
			local chunk = BytecodeLifter.parse(bytecode)
			local scriptName = typeof(script) == "Instance" and script.Name or nil
			local text, stats = BetterDecompiler.decompile(chunk, { scriptName = scriptName, matchLines = MatchLineNumbers ~= false })
			local header = "-- Decompiled with BetterSaveinstance's built-in decompiler (" .. stats.structured + stats.lifted .. " functions"
			if stats.lifted > 0 then
				header ..= ", " .. stats.lifted .. " rebuilt low-level: search for \"[low-level]\""
			end
			return header .. ")\n\n" .. text
		end
	end

	-- * Compiles without running anything. Returns the error message, or nil when the
	-- * source parses (or when there is no way to check it).
	local function GetSyntaxError(source)
		if not loadstring then
			return nil
		end
		local called, f, err = pcall(loadstring, source, "=decompiled")
		if not called or f then
			return nil
		end
		return (string.gsub(tostring(err or "unknown syntax error"), "[\r\n]+", " "))
	end

	-- * Repairs that cannot change what the script does, only whether it parses
	local function RepairDecompiledSource(source)
		source = string.gsub(source, "\0", "\\0") -- ? Some decompilers sadly output \0 which prevents files from opening
		local annotations_ok, annotated = pcall(FixFunctionTypeAnnotations, source)
		if annotations_ok and type(annotated) == "string" and annotated ~= "" then
			source = annotated
		end
		if FixGoto then
			local goto_ok, gotoed = pcall(FixGotoStatements, source)
			if goto_ok and type(gotoed) == "string" and gotoed ~= "" then
				source = gotoed
			end
		end
		return source
	end

	do
		local Decompiler = ExecutorDecompiler
		if BuiltinDecompile then
			Decompiler = function(script)
				local ok, result = pcall(BuiltinDecompile, script)
				if ok then
					return result
				end
				-- * e.g. a bytecode version it does not know yet: let the executor's decompiler try
				if ExecutorDecompiler then
					return "-- NOTE: the built-in decompiler could not read this script (" .. tostring(result) .. "), so the executor's decompiler was used\n\n"
						.. tostring(ExecutorDecompiler(script))
				end
				error(result, 0)
			end
		end

		-- if Decompiler == custom_decompiler then -- Cope
		-- 	local key = "DecompileTimeout"
		-- 	if CustomOptions[key] == nil then
		-- 		local Option = GetAlias(key)
		-- 		if CustomOptions[Option] == nil then
		-- 			Timeout = 1
		-- 		end
		-- 	end

		-- end

		if OPTIONS.noscripts then
			ldecompile = function(script)
				local output = "-- Decompiling is disabled"
					if OPTIONS.SaveBytecodeIfDecompilerFails and SaveBytecode then
						local bc = SaveBytecode(script)
						if bc then
							output = bc..output
						end
					end
				return output
			end
		elseif Decompiler then
			local decomp = construct_TimeoutHandler(Timeout, Decompiler, "Decompiler timed out")
			local fallback_decomp -- * Konstant, only built the first time a script needs it

			-- * Second opinion for scripts whose output does not compile (e.g. a `goto l0`
			-- * with no label, which happens when the decompiler cannot rebuild a loop).
			-- * Returns repaired Konstant output only if THAT one compiles.
			local function TryFallbackDecompiler(script)
				if not DecompilerFallback or UsingKonstant or not getbytecode then
					return nil
				end
				if fallback_decomp == nil then
					local konstant = GetKonstant()
					fallback_decomp = konstant and construct_TimeoutHandler(Timeout, konstant.decompile, "Decompiler timed out") or false
				end
				if not fallback_decomp then
					return nil
				end
				local s, bytecode = getbytecode(script)
				if not s or type(bytecode) ~= "string" or bytecode == "" then
					return nil
				end
				local ok, result = run_with_loading("Retrying with Konstant " .. script.Name, true, nil, fallback_decomp, bytecode)
				-- * Konstant marks every function it could not analyse with KONSTANTERROR and leaves
				-- * it empty or partial. That still compiles, so it must be rejected explicitly.
				if not ok or type(result) ~= "string" or result == "" or string.find(result, "KONSTANTERROR", 1, true) then
					return nil
				end
				result = RepairDecompiledSource(result)
				if GetSyntaxError(result) then
					return nil
				end
				return result
			end

			local function GetChunk(script)
				if not RebuildFromBytecode then
					return nil, "RebuildFromBytecode is disabled"
				end
				if not getbytecode then
					return nil, "no getscriptbytecode"
				end
				local s, bytecode = getbytecode(script)
				if not s or type(bytecode) ~= "string" or bytecode == "" then
					return nil, "could not read the bytecode"
				end
				local parsed, chunk = pcall(BytecodeLifter.parse, bytecode)
				if not parsed then
					return nil, tostring(chunk)
				end
				return chunk
			end

			-- * Rebuilds, from bytecode, every top level function that does not compile or
			-- * contains `until x == x`. Returns the new source, how many functions were
			-- * rebuilt, and why it stopped if something is still wrong.
			local function RebuildFunctions(chunk, source)
				local rebuilt = 0
				for _ = 1, 64 do
					local lines
					local syntax_error = GetSyntaxError(source)
					if syntax_error then
						local line = tonumber(string.match(syntax_error, ":(%d+):"))
						if not line then
							return source, rebuilt, "no line number in: " .. syntax_error
						end
						lines = { line }
					else
						lines = FindSuspiciousLines(source)
						if #lines == 0 then
							return source, rebuilt
						end
					end
					local new, count = RebuildBrokenFunctions(source, chunk, lines)
					if not new then
						return source, rebuilt, count
					end
					source = new
					rebuilt += count
				end
				return source, rebuilt, "too many broken functions"
			end

			ldecompile = function(script)
				if Crashlog then Crashlog("  Decompiling "..script:GetFullName()) end
				-- local name = scr.ClassName .. scr.Name
				local hashed_bytecode
				if ScriptCache then
					local s, bytecode = getbytecode(script)
					local cached

					if s then
						if not bytecode or bytecode == "" then
							if Crashlog then Crashlog("  Script "..script:GetFullName().." is empty") end
							return "-- The Script is Empty"
						end
						-- * Keyed by the bytecode itself, not a hash of it: some executors' `hash` stops at the
						-- * first zero byte, so scripts that start alike (same constant strings) collided and
						-- * got each other's decompiled source.
						hashed_bytecode = bytecode
						cached = ldeccache[hashed_bytecode]
					end

					if cached then
						if __DEBUG_MODE then
							__DEBUG_MODE("Found in Cache", script:GetFullName())
						end
						return cached
					end
				else
					if DecompileJobless then
						return "-- Not found in already decompiled ScriptCache"
					end

					task.wait() -- TODO Maybe remove?
				end

				local ok, result = run_with_loading("Wait Decompiling " .. script.Name, true, nil, decomp, script)
				if not result then
					ok, result = false, "Empty Output"
				end

				local output
				if ok and type(result) ~= "string" then
					ok, result = false, "Decompiler returned " .. typeof(result)
				end
				if ok then
					result = RepairDecompiledSource(result)

					local syntax_error = GetSyntaxError(result)
					local note
					if syntax_error or #FindSuspiciousLines(result) > 0 then
						local original_error = syntax_error
						local chunk, why = GetChunk(script)

						-- * 1. rebuild just the broken functions, the rest stays as decompiled
						if chunk then
							local fixed, count, reason = RebuildFunctions(chunk, result)
							why = reason
							if count > 0 then
								result = fixed
								syntax_error = GetSyntaxError(result)
								note = "-- NOTE: The decompiler got " .. count .. " function(s) in this script wrong; they were rebuilt from bytecode\n"
									.. "-- and behave exactly like the original (search for \"rebuilt from bytecode\").\n\n"
							end
						end

						if syntax_error then
							original_error = original_error or syntax_error
							-- * 2. Konstant, if it decompiles the whole script cleanly
							local fallback = TryFallbackDecompiler(script)
							if fallback then
								note = "-- NOTE: The main decompiler's output did not compile (" .. original_error .. "), so this script was decompiled with Konstant instead.\n\n"
								result, syntax_error = fallback, nil
							elseif chunk then
								-- * 3. rebuild the whole script (the problem is in its main body)
								local whole_ok, whole = pcall(BytecodeLifter.liftScript, chunk)
								if whole_ok and not GetSyntaxError(whole) then
									local level = "="
									while string.find(result, "]" .. level .. "]", 1, true) do
										level ..= "="
									end
									note = "-- NOTE: The decompiler's output did not compile (" .. original_error .. ") and the problem is in the\n"
										.. "-- main body of the script, so the whole script was rebuilt from bytecode. It behaves exactly like\n"
										.. "-- the original but is low level (registers are __R[n], jumps set __pc). The decompiler's\n"
										.. "-- readable attempt is kept in a comment at the end of the script.\n\n"
									result = whole
										.. "\n\n--[" .. level .. "[ The decompiler's output, for reading (does not compile: " .. original_error .. "):\n\n"
										.. result .. "\n]" .. level .. "]\n"
									syntax_error = nil
								elseif not whole_ok then
									why = tostring(whole)
								end
							end
						end

						if syntax_error then
							note = "-- WARNING: This decompiled script does NOT compile: " .. syntax_error .. "\n"
								.. "-- It could not be repaired automatically" .. (why and " (" .. why .. ")" or "") .. ".\n\n"
							warn("Decompiled script does not compile:", script:GetFullName(), syntax_error, why)
						end
					end

					-- * The built-in decompiler already names variables from what they hold and how
					-- * they are used; the text renamer is for other decompilers' v1 / p2 names.
					local named_by_builtin = string.find(result, "^%-%- Decompiled with BetterSaveinstance's built%-in decompiler") ~= nil
					if RenameVariables and not named_by_builtin then
						local renamed_ok, renamed = pcall(RenameDecompiledVariables, result)
						if renamed_ok and type(renamed) == "string" and renamed ~= "" then
							-- * Never let renaming be the thing that breaks a script
							if syntax_error or not GetSyntaxError(renamed) then
								result = renamed
							elseif __DEBUG_MODE then
								__DEBUG_MODE("RenameVariables broke the syntax, keeping the unrenamed output for", script:GetFullName())
							end
						elseif __DEBUG_MODE then
							__DEBUG_MODE("RenameVariables failed, keeping the original output for", script:GetFullName(), renamed)
						end
					end
					if not ScriptHeaders then
						-- * no banner in every script: line numbers stay closer to the original
						result = string.gsub(result, "^%-%- Decompiled with BetterSaveinstance's built%-in decompiler[^\n]*\n\n", "", 1)
					end
					output = note and note .. result or result
				else
					output = "--[[ Failed to decompile. Reason:\n" .. (result or "") .. "\n]]"
				end

				if ScriptCache and hashed_bytecode then -- TODO there might(?) be an edgecase where it manages to decompile (built-in) even though getscriptbytecode failed, and the output won't get cached
					ldeccache[hashed_bytecode] = output -- ? Should we cache even if it timed out?
					if __DEBUG_MODE then
						__DEBUG_MODE("Cached", script:GetFullName())
					end
				end
				if Crashlog then Crashlog("  Successfully decompiled "..script:GetFullName()) end
				return output
			end
		else
			ldecompile = function(script)
				local output = "-- Your Executor does NOT have a Decompiler"
					if OPTIONS.SaveBytecodeIfDecompilerFails and SaveBytecode then
						local bc = SaveBytecode(script)
						if bc then
							output = bc..output
						end
					end
				return output
			end
		end
	end

	local function GetLocalPlayer()
		return service.Players.LocalPlayer
			or service.Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
			or service.Players.LocalPlayer
	end

	local function filterLinkedSource(str)
		local o, r = pcall(service.HttpService.JSONDecode, service.HttpService, str)
		if o and r.errors then
			return
		end
		return true
	end

	local function replaceClassName(instance, InstanceName, ClassName)
		local InstanceOverride
		if InstanceName ~= ClassName then -- TODO Compare against default instance instead (TouchTransmitter is called TouchInterest by default)
			InstanceOverride = InstancesOverrides[instance]
			if not InstanceOverride then
				InstanceOverride = { Properties = { Name = "[" .. ClassName .. "] " .. InstanceName } }
				InstancesOverrides[instance] = InstanceOverride
			end
		end
		return InstanceOverride
	end

	local function filterPropVal(result, propertyName, category) -- ? raw == nil thanks to SerializedDefaultAttributes; "can't get value" - due to WriteOnly tag;  "Invalid value for enum " - "StreamingPauseMode" (old games probably) Roexec
		return result == nil
			or result == "can't get value"
			or type(result) == "string"
				and (category == "Enum" or string_find(result, "Unable to get property " .. propertyName))
	end

	local __BREAK = "__BREAK" .. service.HttpService:GenerateGUID(false)

	local function ReadProperty(instance, property, propertyName, special, category, optional)
		local raw = __BREAK

		local InstanceOverride = InstancesOverrides[instance]
		if InstanceOverride then
			local PropertiesOverride = InstanceOverride.Properties
			if PropertiesOverride then
				local PropertyOverride = PropertiesOverride[propertyName]
				if PropertyOverride ~= nil then
					return PropertyOverride
				end
			end
		end

		local CanRead = property.CanRead

		if CanRead == false then -- * Skips because we've checked this property before
			return __BREAK
		end

		if special then
			if gethiddenproperty then
				if EXECUTOR_NAME == "Velocity" and not ArrayToDict({"BinaryString", "SharedString"})[property.ValueType] then
					property.CanRead = false
					return __BREAK
				end
				local ok, result = pcall(gethiddenproperty, instance, propertyName)

				if ok then
					raw = result
				end

				if filterPropVal(raw, propertyName, category) then
					-- * Skip next time we encounter this too perhaps (unless there's a chance for it to be readable on other instance, somehow)

					if result ~= nil or not optional then
						if __DEBUG_MODE then
							__DEBUG_MODE("Filtered", propertyName)
						end
						-- Property.Special = false
						property.CanRead = false
					end

					return __BREAK -- ? We skip it because even if we use "" it will just reset to default in most cases, unless it's a string tag for example (same as not being defined)
				end
			end
		else
			if CanRead then
				raw = instance[propertyName]
			else -- Assuming CanRead == nil (untested)
				local ok, result = pcall(index, instance, propertyName)

				if ok then
					raw = result
				elseif gethiddenproperty then -- ! Be careful with this 'and gethiddenproperty' logic
					ok, result = pcall(gethiddenproperty, instance, propertyName)

					if ok then
						raw = result

						property.Special = true
					end
				end

				property.CanRead = ok

				if not ok or filterPropVal(raw, propertyName, category) then
					return __BREAK
				end
			end
		end

		return raw
	end
	
	local function ReadPropertyFull(instance, Property, PropertyName, Special, Category, Optional)
		if Crashlog then Crashlog("  Reading property "..PropertyName) end
		
		local raw = ReadProperty(instance, Property, PropertyName, Special, Category, Optional)

		if raw == __BREAK then -- ! Assuming __BREAK is always returned when there's a failure to read a property
			if Crashlog then Crashlog("    Failed to read property "..PropertyName.." trying UGCValidationService fallback") end
			local ok, result = pcall(gethiddenproperty_fallback, instance, PropertyName) -- * This helps in reading: Vector3int16, OptionalCoordinateFrame DataTypes. It also acts as an almost entire fallback for gethiddenproperty in case it is missing

			if result == nil and not Optional then
				ok = nil
			end

			if ok then
				raw = result
			else
				local Fallback = Property.Fallback

				if Fallback then
					if Crashlog then Crashlog("    Failed to read property "..PropertyName.." trying fallback") end
					ok, result = pcall(Fallback, instance)

					if ok then
						raw = result
					else
						if __DEBUG_MODE then
							-- TODO Maybe remove the fix during runtime if it fails to avoid re-trying
							__DEBUG_MODE("Fix Failed", PropertyName)
						end
						return __BREAK
					end
				else
					if Crashlog then Crashlog("    Failed to read property "..PropertyName) end
					return __BREAK
				end
			end
		end
		if Crashlog then Crashlog("    Property "..PropertyName.." read successfully") end
		return raw
	end
	
	local function ReturnItem(className, instance)
		return '<Item class="' .. className .. '" referent="' .. GetRef(instance) .. '"><Properties>' -- TODO: Ideally this shouldn't return <Properties> as well as the line below to close it IF  IgnorePropertiesOfNotScriptsOnScriptsMode is Enabled OR If all properties are default (reduces file size by at least 1.4%)
	end

	local function ReturnProperty(tag, propertyName, value)
		return "<" .. tag .. ' name="' .. propertyName .. '">' .. value .. "</" .. tag .. ">"
	end

	local function ReturnValueAndTag(raw, valueType, descriptor)
		local value, tag = (descriptor or XML_Descriptors[valueType])(raw)

		return value, tag or valueType
	end
	
	local function ReturnAttributeValue(Property, raw)
		local ValueType, Category = Property.ValueType, Property.Category
		if raw == nil then
			return
		end
		if Category == "Enum" then
			ValueType = "Enum"
		elseif Category == "Class" then
			if Anonymous then
				raw = raw:GetFullName()
				ValueType = "string"
			else
				return raw:GetFullName() -- There is probally a better way to save class properties within attributes
			end	
		end
		
		if Anonymous then
			local LocalPlayer = service.Players.LocalPlayer
			if LocalPlayer then
				if ValueType == "string" then
					return gsubCaseInsensitive(
							string.gsub(raw, LocalPlayer.UserId, Anonymous.UserId),
							LocalPlayer.Name,
							Anonymous.Name
						)
				elseif ArrayToDict({"int", "int64", "double", "float"})[ValueType] then
					if raw == LocalPlayer.UserId then 
						return Anonymous.UserId
					end	
				end
			end
		end
		
		-- Types not added: CSGPropertyData, Color3uint8, Content, FacsReplicationData, QDir (should never be used), QFont, (should never be used) ReplicationPV, SecurityCapabilities (should never be used), UniqueId
		if ArrayToDict({"string", "bool", "UDim", "UDim2", "BrickColor", "Color3", "Vector2", "Vector3", "CFrame", "NumberSequence", "ColorSequence", "NumberRange", "Rect", "Font", "SystemAddress", "Enum", "int", "int64", "double", "float", "BinaryString", "SharedString", "ContentId", "OptionalCoordinateFrame"})[ValueType] then
			return(raw)	
		elseif ArrayToDict({"PhysicalProperties", "TweenInfo", "Faces", "Region3int16", "Ray", "Path2DControlPoint", "Axes"})[ValueType] then
			return(tostring(raw))
		elseif ValueType == "DateTime" then
			return(raw.UnixTimestampMillis) -- Milliseconds since January 1st, 1970 at 00:00 UTC
		elseif ValueType == "Vector3int16" then
			return(Vector3.new(raw.X, raw.Y, raw.Z))
		elseif ValueType == "ProtectedString" then
			return -- All the properties with the ProtectedString valuetype are source related, and thus useless
		else
			--if __DEBUG_MODE then
				warn("No type support for "..ValueType.." for SaveAsAttributes") -- * We print this anyway because very important
			--end
		end
		
	end
	
	local function InheritsFix(fixes, className, instance)
		local Fix = fixes[className]
		if Fix then
			return Fix
		elseif Fix == nil then
			for class_name, fix in fixes do
				if instance:IsA(class_name) then
					return fix
				end
			end
		end
	end

	local function GetInheritedProps(className, useNotSaveableProperties, classesToStopBefore)
		local prop_list = {}
		local layer = ClassList[className]
		while layer do
			local layer_props
			if useNotSaveableProperties then
				layer_props = layer.NotSaveableProperties
			else
				layer_props = layer.Properties
			end
			table.move(layer_props, 1, #layer_props, #prop_list + 1, prop_list)

			-- for _, prop in layer.Properties do
			-- 	prop_list[prop_count] = prop -- ? table.clone is needed for case where .Default is modified
			-- 	prop_count += 1
			-- end
			local SuperClass = layer.Superclass
			layer = ClassList[SuperClass]
			if classesToStopBefore then
				if ArrayToDict(classesToStopBefore)[SuperClass] then
					layer = nil
				end
			end
		end
		return prop_list
	end

	local CHUNK_LIMIT = 200 * 1024 * 1024 -- string length overflow prevention
	local function save_cache(final)
		local savestr = table.concat(savebuffer)
		currentstr ..= savestr -- TODO: Causes "not enough memory" error on some exec

		-- writefile(placename, totalstr)
		-- appendfile(placename, savestr) -- * supposedly causes uneven amount of Tags (e.g. <Item> must be closed with </Item> but sometimes there's more of one than the other). While being under load, the function produces unexpected output?
		local savestr_len = #savestr
		totalsize += savestr_len
		currentsize += savestr_len

		table.clear(savebuffer)
		savebuffer_size = 1

		if CHUNK_LIMIT < currentsize or final then
			table.insert(chunks, { size = currentsize, str = currentstr })
			currentstr, currentsize = "", 0
		end

		if StatusText then
			StatusText.Text = "Saving.. Size: " .. get_size_format()
		end
		-- ? Needed for at least 1fps (status text)
		-- task.wait()
		wait_for_render()
	end

	local function save_specific(className, properties)
		local Ref = Instance.new(className) -- ! Assuming anything passed here is Creatable
		local Item = ReturnItem(Ref.ClassName, Ref)

		for propertyName, val in properties do
			local whitelisted, value, tag

			-- TODO: Improve all sort of overrides & exceptions in the code (code below is awful)
			if "Source" == propertyName then
				tag = "ProtectedString"
				value = XML_Descriptors.__PROTECTEDSTRING(val)
				whitelisted = true
			elseif "Name" == propertyName then
				whitelisted = true
				value, tag = ReturnValueAndTag(val, "string") -- * Doubt ValueType will change
			end

			if whitelisted then
				Item ..= ReturnProperty(tag, propertyName, value)
			end
		end
		Item ..= "</Properties>"
		return Item
	end
	local function SaveAttributes(instance, useNotSaveableProperties, Prefix, InstanceToSet, classesToStopBefore)
		if not InstanceToSet then
			InstanceToSet = instance
		end	
		
		local ClassName = instance.ClassName
		local TableToUse
		if useNotSaveableProperties then 
			TableToUse = notsaveable_inherited_properties
		else
			TableToUse = notcreatablefixes_inherited_properties
		end
		local proplist = TableToUse[ClassName]
		if not proplist then
			proplist = GetInheritedProps(ClassName, useNotSaveableProperties, classesToStopBefore)
			TableToUse[ClassName] = proplist
		end
		for _, Property in proplist do
			local PropertyName = Property.Name
			if IgnoreProperties[PropertyName] or ArrayToDict({"PrivateServerOwnerId", "PrivateServerId", "VIPServerId", "VIPServerOwnerId"})[PropertyName] then
				continue
			end

			if IgnoreSharedStrings and Property.ValueType == "SharedString" then -- ? More info in Options
				continue
			end

			local Special, Category, Optional = Property.Special, Property.Category, Property.Optional

			local raw = ReadPropertyFull(instance, Property, PropertyName, Special, Category, Optional)
						
			if raw == __BREAK then
				continue
			end
					
			local value = ReturnAttributeValue(Property, raw)
			if value ~= nil then
				local ok, errorm = pcall(function()
					InstanceToSet:SetAttribute(Prefix .. PropertyName:gsub("[^%w_]+", ""), value) -- Attribute name has the prefix __NotSaveable_ or (insert other prefix)_  then the property name with all non alphanumeric characters removed besides underscores
				end)
				if not ok and __DEBUG_MODE then
					__DEBUG_MODE("Failed to set property "..PropertyName.." for SaveAsAttributes. Error Message: "..errorm)
				end
			end
		end
	end
	local function save_hierarchy(hierarchy)
		for _, instance in hierarchy do
			if IgnoreNotArchivable and not instance.Archivable then
				continue
			end

			local SkipEntirely = IgnoreList[instance]
			if SkipEntirely then
				continue
			end

			local ClassName = instance.ClassName

			local InstanceName = instance.Name

			do
				local OnIgnoredList = IgnoreList[ClassName]
				if OnIgnoredList and (OnIgnoredList == true or OnIgnoredList[InstanceName]) then
					continue
				end
			end
			
			if Crashlog then Crashlog("Saving Instance "..instance:GetFullName().." Class "..ClassName) end
			
			if SaveAsAttributes then
				SaveAttributes(instance, true, "__NotSaveable_")	
			end
			
			if not DecompileIgnoring then
				DecompileIgnoring = DecompileIgnore[instance]

				if DecompileIgnoring == nil then
					local DecompileIgnored = DecompileIgnore[ClassName]
					if DecompileIgnored then
						DecompileIgnoring = DecompileIgnored == true or DecompileIgnored[InstanceName]
					end
				end

				if DecompileIgnoring then
					DecompileIgnoring = instance
				elseif DecompileIgnoring == false then
					DecompileIgnoring = 1 -- Ignore one instance
				end
			end

			local InstanceOverride, ClassNameOverride, ClassTagOverride

			do
				local Fix = NotCreatableFixes[ClassName]

				if Fix then
					if SaveNotCreatable then
						if SavePropsAsAttributesForNotCreatableFixes then
							local classesToStopBefore = {Fix, "Instance"}
							SaveAttributes(instance, false, "__NotCreatableFix_", nil, classesToStopBefore)
						end
						ClassName, InstanceOverride = Fix, replaceClassName(instance, InstanceName, ClassName)
					else
						continue -- They won't show up in Studio anyway (Enable SaveNotCreatable if you wish to bypass this)
					end
				else -- ! Assuming nothing that is a PartOperation or inherits from it is in NotCreatableFixes
					if TreatUnionsAsParts and instance:IsA("PartOperation") then
						ClassName, InstanceOverride = "Part", replaceClassName(instance, InstanceName, ClassName)
						ClassNameOverride = "BasePart" -- * Mutual Superclass for PartOperation and Part; For properties only
					elseif not ClassList[ClassName] then -- ? API Dump is outdated then
						if __DEBUG_MODE then
							__DEBUG_MODE("Class not Found", ClassName)
						end

						ClassTagOverride = ClassName -- ? To at least retain .ClassName unlike the rest of the class-specific properties
						ClassName = "Folder" -- ? replaceClassName is not needed because of the ClassTagOverride
					end
				end
			end

			if not InstanceOverride then
				InstanceOverride = InstancesOverrides[instance]
			end

			-- ? The reason we only save .Name (and few other props in save_specific) is because
			-- ? we can be sure this is a custom container (ex. NilInstancesFixes)
			-- ? However, in case of NotCreatableFixes, the Instance might have Tags, Attributes etc. that can potentially be saved (even though it's a Folder)
			if InstanceOverride and InstanceOverride.__SaveSpecific then
				savebuffer[savebuffer_size] = save_specific(ClassName, InstanceOverride.Properties) -- ! Assuming anything that has __SaveSpecific will have .Properties
				savebuffer_size += 1
			else
				-- local Properties =
				savebuffer[savebuffer_size] = ReturnItem(ClassTagOverride or ClassName, instance) -- TODO: Ideally this shouldn't return <Properties> as well as the line below to close it IF  IgnorePropertiesOfNotScriptsOnScriptsMode is ENABLED
				savebuffer_size += 1
				if not (IgnorePropertiesOfNotScriptsOnScriptsMode and not isLuaSourceContainer(instance)) then
					local default_instance, new_def_inst

					if IgnoreDefaultProperties then
						default_instance = default_instances[ClassName]
						if not default_instance then
							local ClassTags = ClassList[ClassName].Tags
							if not (ClassTags and ClassTags.NotCreatable) then -- __api_dump_class_not_creatable__ also indicates this
								-- ! NotCreatableFixes are exceptions to the check above meaning if we don't keep the NotCreatableFixes updated then Instance.new below might start erroring in the future potentially; HOWEVER IsPropertyModified solves this issue and no updates are really needed as NotCreatableFixes is up-to-date as of VERSION-HERE (which is when IPM gets enabled)
								new_def_inst = Instance.new(ClassName) -- ! Assuming anything that doesn't have NotCreatable is possible to create (therefore no pcall); EXCEPTION NOTED ABOVE

								default_instance = {}

								default_instances[ClassName] = default_instance
							elseif __DEBUG_MODE then
								__DEBUG_MODE("Unable to create default Instance", ClassName)
							end
						end
					end
					local proplist
					do
						local class = ClassNameOverride or ClassName
						proplist = inherited_properties[class]
						if not proplist then
							proplist = GetInheritedProps(class)
							inherited_properties[class] = proplist
						end
					end
					for _, Property in proplist do
						local PropertyName = Property.Name

						if IgnoreProperties[PropertyName] then
							continue
						end

						local ValueType = Property.ValueType

						if IgnoreSharedStrings and ValueType == "SharedString" then -- ? More info in Options
							continue
						end

						local Special, Category, Optional = Property.Special, Property.Category, Property.Optional

						local raw = ReadPropertyFull(instance, Property, PropertyName, Special, Category, Optional)
						
						if raw == __BREAK then
							continue
						end

						if SharedStringOverwrite and ValueType == "BinaryString" then -- TODO: Convert this to table if more types are added
							ValueType = "SharedString"
						end

						-- Special = Property.Special -- ? Read TODO below (must be updated if it's used frequently afterwards)

						if
							default_instance
							and not Property.Special -- TODO: .Special is checked more than once (because it might be updated during ReadProperty)
							and not (PropertyName == "Source" and isLuaSourceContainer(instance))
						then -- ? Could be not just "Source" in the future
							if new_def_inst then
								default_instance[PropertyName] = index(new_def_inst, PropertyName)
							end
							if default_instance[PropertyName] == raw then
								continue
							end
						end

						-- Serialization start

						local tag, value
						if Category == "Class" then
							tag = "Ref"
							if raw then
								if SaveNotCreatableWillBeEnabled then
									local Fix = NotCreatableFixes[raw.ClassName]
									if
										Fix
										and (
											PropertyName == "PlayerToHideFrom"
											or ValueType ~= "Instance" and ValueType ~= Fix
										)
									then
										-- * To avoid errors
										continue
									end
								end

								value = GetRef(raw)
							else
								value = "null"
							end
						elseif Category == "Enum" then -- ! We do this order (Enums before Descriptors) specifically because Font Enum might get a Font Descriptor despite having Enum Category, unlike Font DataType which that Descriptor is meant for
							value, tag = XML_Descriptors.__ENUM(raw)
						else
							local Descriptor = XML_Descriptors[ValueType]

							if Descriptor then
								value, tag = ReturnValueAndTag(raw, ValueType, Descriptor)
							elseif "ProtectedString" == ValueType then -- TODO: Try fitting this inside Descriptors
								tag = ValueType

								if PropertyName == "Source" then
									if DecompileIgnoring then -- ? Should this really prevent extraction of the original source if present ?
										if DecompileIgnoring == 1 then
											DecompileIgnoring = nil
										end
										value = "-- Ignored"
									else
										local should_decompile = true
										local LinkedSource
										local LinkedSource_Url = instance.LinkedSource -- ! Assuming every Class that has ProtectedString Source property also has a LinkedSource property
										local hasLinkedSource = LinkedSource_Url ~= ""
										local LinkedSource_type
										if hasLinkedSource then
											local Path = instance:GetFullName()
											if RecoveredScripts then
												table.insert(RecoveredScripts, Path)
											end

											LinkedSource = string.match(LinkedSource_Url, "%w+$") -- TODO: No sure if this pattern matches all possible cases. Example is: 'rbxassetid://0&hash=cd73dd2fe5e5013137231c227da3167e'
											if LinkedSource then
												if ScriptCache then
													local cached = ldeccache[LinkedSource]

													if cached then
														value = cached
														should_decompile = nil
													end
												end
												if should_decompile then
													if DecompileJobless then
														value = "-- Not found in LinkedSource ScriptCache"
														should_decompile = nil
													end

													LinkedSource_type = string.find(LinkedSource, "%a") and "hash"
														or "id"

													local asset = LinkedSource_type .. "=" .. LinkedSource

													local ok, source = pcall(function()
														-- Credits @halffalse
														return game:HttpGet(
															"https://assetdelivery.roproxy.com/v1/asset/?" .. asset
														)
													end)

													if ok and filterLinkedSource(source) then
														if ScriptCache then
															ldeccache[LinkedSource] = source
														end

														value = source

														should_decompile = nil
													end
												end
											else --if __DEBUG_MODE then -- * We print this anyway because very important
												warn(
													"FAILED TO EXTRACT ORIGINAL SCRIPT SOURCE (OPEN A GITHUB ISSUE): ",
													instance:GetFullName(),
													LinkedSource_Url
												)
											end
										end

										if should_decompile then
											local isLocalScript = instance:IsA("LocalScript")
											if
												isLocalScript and instance.RunContext == Enum.RunContext.Server
												or not isLocalScript
													and instance:IsA("Script")
													and instance.RunContext ~= Enum.RunContext.Client
											then
												value = "-- [FilteringEnabled] Server Scripts are IMPOSSIBLE to save" -- TODO: Could be not just server scripts in the future
											else
												local IsCompilationError = false
												if CompilationError then
													local CompilationMessage = CompilationError(instance)
													if CompilationMessage then
														value = CompilationMessage
														IsCompilationError = true
													else
														value = ldecompile(instance)
													end	
												else
													value = ldecompile(instance)
												end
												
												local DecompilerFailedMessages = {"Failed to decompile", "Something went wrong when decompiling", "Decompilation failed", "Update the decompiling script", "Check decompiling options for errors", "Failed to generate AST"} -- Some from Konstant, Oracle and USSI. If you have anymore decompiler errors please submit them.
												if OPTIONS.SaveBytecodeIfDecompilerFails and SaveBytecode and not IsCompilationError then
													for _, v in DecompilerFailedMessages do
														if string.find(value, v, 1, true) then
															local bc = SaveBytecode(instance)
															if bc then
																value = bc..value
															end
															break
														end
													end
												end
												if OPTIONS.SaveBytecode and SaveBytecode and not IsCompilationError then
													local output = SaveBytecode(instance)
													if output then
														value = output .. value
													end
												end
											end
										end

										value = (ScriptHeaders and "-- Saved by UniversalSynSaveInstance (Join to Copy Games) https://discord.gg/wx4ThpAsmw\n\n" or "")
											.. (hasLinkedSource and "-- Original Source: https://assetdelivery.roblox.com/v1/asset/?" .. (LinkedSource_type or "id") .. "=" .. (LinkedSource or LinkedSource_Url) .. "\n\n" or "")
											.. value
									end
								end
								value = XML_Descriptors.__PROTECTEDSTRING(value)
							else
								--OptionalCoordinateFrame and so on, we make it dynamic

								if Optional then
									Descriptor = XML_Descriptors[Optional]

									if Descriptor then
										if raw == nil then
											-- * It can be empty, because it's optional
											-- ? Though why even save it if it's empty considering it's optional
											continue
										-- value, tag = "", ValueType
										else
											value, tag = ReturnValueAndTag(raw, ValueType, Descriptor)
										end
									end
								end
							end
						end

						if tag then
							savebuffer[savebuffer_size] = ReturnProperty(tag, PropertyName, value)
							savebuffer_size += 1
						else --if __DEBUG_MODE then -- * We print this anyway because very important
							warn("UNSUPPORTED TYPE (OPEN A GITHUB ISSUE): ", ValueType, ClassName, PropertyName)
						end
					end
				end
				savebuffer[savebuffer_size] = "</Properties>"
				savebuffer_size += 1

				if SaveCacheInterval < savebuffer_size then
					save_cache()
				end
			end

			if SkipEntirely ~= false then -- ? We save instance without it's descendants in this case (== false)
				local Children = InstanceOverride and InstanceOverride.__Children or instance:GetChildren()

				if #Children ~= 0 then
					save_hierarchy(Children)
				end
			end

			if DecompileIgnoring and DecompileIgnoring == instance then
				DecompileIgnoring = nil
			end

			savebuffer[savebuffer_size] = "</Item>"
			savebuffer_size += 1
		end
	end

	local function save_extra(name, hierarchy, customClassName, source)
		savebuffer[savebuffer_size] = save_specific((customClassName or "Folder"), { Name = name, Source = source })
		savebuffer_size += 1
		if hierarchy then
			save_hierarchy(hierarchy)
		end
		savebuffer[savebuffer_size] = "</Item>"
		savebuffer_size += 1
	end

	local function save_game()
		do
			if IsModel then
				--[[ 
			-- ? Roblox encodes the following additional attributes. These are not required. Moreover, any defined schemas are ignored, and not required for a file to be valid: xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd"  
			Also http can be converted to https but not sure if Roblox cares
			-- ? <External>null</External><External>nil</External>  - <External> is a legacy concept that is no longer used.
		]]
				header ..= '<Meta name="ExplicitAutoJoints">true</Meta>'
			end

			writefile(placename, header) -- TODO This is sort of useless if writefile will be used at the end (like if AlternativeWritefile and Callback are unused)
		end

		-- TODO Find a better solution for this
		SaveNotCreatableWillBeEnabled = SaveNotCreatable
			or (IsolateLocalPlayer or IsolateLocalPlayerCharacter) and IsolateLocalPlayer
			or IsolatePlayers
			or NilInstances and global_container.getnilinstances -- ! Make sure this accurately reflects everything below

		save_hierarchy(ToSaveList)

		if IsolateLocalPlayer or IsolateLocalPlayerCharacter then
			local LocalPlayer = service.Players.LocalPlayer
			if LocalPlayer then
				if IsolateLocalPlayer then
					SaveNotCreatable = true
					save_extra("LocalPlayer", LocalPlayer:GetChildren())
				end
				if IsolateLocalPlayerCharacter then
					local LocalPlayerCharacter = LocalPlayer.Character
					if LocalPlayerCharacter then
						save_extra("LocalPlayer Character", LocalPlayerCharacter:GetChildren(), "Model")
					end
				end
			end
		end

		if IsolateStarterPlayer then
			-- SaveNotCreatable = true -- TODO: Enable if StarterPlayerScripts or StarterCharacterScripts stop showing up in isolated folder in Studio
			save_extra("StarterPlayer", service.StarterPlayer:GetChildren())
		end

		if IsolatePlayers then
			SaveNotCreatable = true
			save_extra("Players", service.Players:GetChildren())
		end

		if NilInstances and global_container.getnilinstances then
			local nil_instances, nil_instances_size = {}, 1

			local NilInstancesFixes = OPTIONS.NilInstancesFixes

			for _, instance in global_container.getnilinstances() do
				if instance == game then
					instance = nil
					-- break
				else
					local ClassName = instance.ClassName

					local Fix = InheritsFix(NilInstancesFixes, ClassName, instance)

					if Fix then
						instance = Fix(instance, InstancesOverrides)
						-- continue
					end

					local Class = ClassList[ClassName]
					if Class then
						local ClassTags = Class.Tags
						if ClassTags and ClassTags.Service then -- For CSGDictionaryService, NonReplicatedCSGDictionaryService, LogService, ProximityPromptService, TestService & more
							-- instance.Parent = game
							instance = nil
							-- continue
						end
					end
				end
				if instance then
					nil_instances[nil_instances_size] = instance
					nil_instances_size += 1
				end
			end
			SaveNotCreatable = true
			save_extra("Nil Instances", nil_instances)
		end

		if OPTIONS.ReadMe then
			save_extra(
				"README",
				nil,
				"Script",
				"--[[\n"
					.. (#RecoveredScripts ~= 0 and "\t\tIMPORTANT: Original Source of these Scripts was Recovered: " .. service.HttpService:JSONEncode(
						RecoveredScripts
					) .. "\n" or "")
					.. [[
		Thank you for using BetterSaveinstance (Fork of UniversalSynSaveInstance). Their discord: https://discord.gg/wx4ThpAsmw.

		If you didn't save in Binary (rbxl) - it's recommended to save the game right away to take advantage of the binary format & to preserve values of certain properties if you used IgnoreDefaultProperties setting (as they might change in the future).
		You can do that by going to FILE -> Save to File As -> Make sure File Name ends with .rbxl -> Save

		ServerStorage, ServerScriptService and Server Scripts are IMPOSSIBLE to save because of FilteringEnabled.

		If your player cannot spawn into the game, please move PlayerModule in StarterPlayer somewhere else. Then run `game:GetService("Players").CharacterAutoLoads = true`.
		And use "Play Here" to start game instead of "Play" to spawn your Character where your Camera currently is.

		If the chat system does not work, please use the explorer and delete everything inside the TextChatService/Chat service(s). 
		Or run `game:GetService("Chat"):ClearAllChildren() game:GetService("TextChatService"):ClearAllChildren()`
				
		If Union and MeshPart collisions don't work, run the script below in the Studio Command Bar:
				
				
		local C = game:GetService("CoreGui")
		local D = Enum.CollisionFidelity.Default
				
		for _, v in game:GetDescendants() do
			if v:IsA("TriangleMeshPart") and not v:IsDescendantOf(C) then
				v.CollisionFidelity = D
			end
		end
		print("Done")
				
		If you can't move the Camera, run this script in the Studio Command Bar:
			
		workspace.CurrentCamera.CameraType = Enum.CameraType.Fixed
		
		Or Destroy the Camera.

		This file was generated with the following settings:
		]]
					.. service.HttpService:JSONEncode(OPTIONS)
					.. "\n\n\t\tElapsed time: "
					.. os.clock() - elapse_t
					.. " PlaceId: "
					.. game.PlaceId
					.. " PlaceVersion: "
					.. game.PlaceVersion
					.. " Client Version: "
					.. version()
					.. " Executor: "
					.. (identify_executor and table.concat({ identify_executor() }, " ") or "Unknown")
					.. "\n]]"
			)
		end
		do
			local tmp = { "<SharedStrings>" }
			for identifier, value in SharedStrings do
				table.insert(tmp, '<SharedString md5="' .. identifier .. '">' .. value .. "</SharedString>")
			end

			if 1 < #tmp then -- TODO: This sucks so much because we try to iterate a table just to check this (check above)
				savebuffer[savebuffer_size] = table.concat(tmp)
				savebuffer_size += 1
				savebuffer[savebuffer_size] = "</SharedStrings>"
				savebuffer_size += 1
			end
		end

		savebuffer[savebuffer_size] =
			"</roblox><!-- Saved by UniversalSynSaveInstance (Join to Copy Games) https://discord.gg/wx4ThpAsmw -->"
		savebuffer_size += 1
		save_cache(true)
		do
			-- ! Assuming we only write to file once hence why we only filter once
			-- TODO This might cause issues on non-unique Usernames (ex. "Cake" if game is about cakes then everything supposedly related to your name will be replaced with "Roblox"); Certain UserIds might also affect numbers, like if your UserId is 2481848 and there is some number that goes like "1.248184818837" then that the matched part will be replaced with 1, potentially making the number incorrect.
			-- TODO So for now it's best to keep this disabled by default
			-- TODO It's also not smart to filter entire file string at the end as this might also affect decompiled scripts content, which has no way of containing any user-related information. It would be better to use gsub in string Descriptor and such
			if Anonymous then
				local LocalPlayer = service.Players.LocalPlayer
				if LocalPlayer then
					for _, chunk in chunks do
						chunk.str = gsubCaseInsensitive(
							string.gsub(chunk.str, LocalPlayer.UserId, Anonymous.UserId),
							LocalPlayer.Name,
							Anonymous.Name
						)
					end
				end
			end

			local Callback = OPTIONS.Callback
			if Callback then
				local totalstr = header
				for _, chunk in chunks do
					totalstr ..= chunk.str
				end
				Callback(totalstr, chunks, totalsize)
			elseif OPTIONS.AlternativeWritefile and appendfile then
				local SEGMENT_SIZE = 4145728 -- Celery has an arbitrary savefile/appendfile size limit of ~4MB for reasons unknown. This is a workaround to save the file in segments.

				local totallen, currentlen = math.ceil(totalsize / SEGMENT_SIZE), 1

				for _, chunk in chunks do
					local length = math.ceil(chunk.size / SEGMENT_SIZE)
					for i = 1, length do
						local savestr = string.sub(chunk.str, (i - 1) * SEGMENT_SIZE + 1, i * SEGMENT_SIZE)

						run_with_loading(
							"Writing to File " .. math.round(currentlen / totallen * 100) .. "% (Depends on Exec)",
							nil,
							true,
							appendfile,
							placename,
							savestr
						)
						currentlen += 1

						if i ~= length then
							task.wait()
						end
					end
				end
			else
				local totalstr = header
				for _, chunk in chunks do
					totalstr ..= chunk.str
				end
				run_with_loading(
					"Writing " .. get_size_format() .. " to File (Depends on Exec)",
					nil,
					true,
					writefile,
					placename,
					totalstr
				)
			end
		end
		table.clear(SharedStrings)
	end

	local Connections
	do
		local Players = service.Players

		if IgnoreList.Model ~= true then
			Connections = {}
			local function ignoreCharacter(player)
				table.insert(
					Connections,
					player.CharacterAdded:Connect(function(character)
						IgnoreList[character] = true
					end)
				)

				local Character = player.Character
				if Character then
					IgnoreList[Character] = true
				end
			end

			if OPTIONS.RemovePlayerCharacters then
				table.insert(
					Connections,
					Players.PlayerAdded:Connect(function(player)
						ignoreCharacter(player)
					end)
				)
				for _, player in Players:GetPlayers() do
					ignoreCharacter(player)
				end
			else
				IgnoreNotArchivable = false -- TODO Bad solution (Characters are NotArchivable); Also make sure the next solution is compatible with IsolateLocalPlayerCharacter
				if IsolateLocalPlayerCharacter then
					task.spawn(function()
						ignoreCharacter(GetLocalPlayer())
					end)
				end
			end
		end
		if IsolateLocalPlayer and IgnoreList.Player ~= true then
			task.spawn(function()
				IgnoreList[GetLocalPlayer()] = true
			end)
		end
	end

	if IsolateStarterPlayer then
		IgnoreList.StarterPlayer = false
	end

	if IsolatePlayers then
		IgnoreList.Players = false
	end

	if OPTIONS.ShowStatus then
		do
			local Exists = GLOBAL_ENV._statustext
			if Exists then
				Exists:Destroy()
			end
		end

		local StatusGui = Instance.new("ScreenGui")

		GLOBAL_ENV._statustext = StatusGui

		StatusGui.DisplayOrder = 2e9
		pcall(function() -- ? Compatibility with level 2
			StatusGui.OnTopOfCoreBlur = true
		end)

		StatusText = Instance.new("TextLabel")

		StatusText.Text = "Saving..."

		StatusText.BackgroundTransparency = 1
		StatusText.Font = Enum.Font.Code
		StatusText.AnchorPoint = Vector2.new(1)
		StatusText.Position = UDim2.new(1)
		StatusText.Size = UDim2.new(0.3, 0, 0, 20)

		StatusText.TextColor3 = Color3.new(1, 1, 1)
		StatusText.TextScaled = true
		StatusText.TextStrokeTransparency = 0.7
		StatusText.TextXAlignment = Enum.TextXAlignment.Right
		StatusText.TextYAlignment = Enum.TextYAlignment.Top

		StatusText.Parent = StatusGui

		local function randomString()
			local length = math.random(10, 20)
			local randomarray = table.create(length)
			for i = 1, length do
				randomarray[i] = string.char(math.random(32, 126))
			end
			return table.concat(randomarray)
		end

		if global_container.gethui then
			StatusGui.Name = randomString()
			StatusGui.Parent = global_container.gethui()
		else
			if global_container.protectgui then
				StatusGui.Name = randomString()
				global_container.protectgui(StatusGui)
				StatusGui.Parent = game:GetService("CoreGui")
			else
				local RobloxGui = game:GetService("CoreGui"):FindFirstChild("RobloxGui")
				if RobloxGui then
					StatusGui.Parent = RobloxGui
				else
					StatusGui.Name = randomString()
					StatusGui.Parent = game:GetService("CoreGui")
				end
			end
		end
	end

	do
		local SafeMode = OPTIONS.SafeMode
		if SafeMode then
			task.spawn(function()
				local LocalPlayer = GetLocalPlayer()

				local PlayerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
				if PlayerScripts then
					local function construct_InstanceOverride(instance)
						local children = instance:GetChildren()
						InstancesOverrides[instance] = {
							__Children = children,
						}
						for _, child in children do
							construct_InstanceOverride(child)
						end
					end
					construct_InstanceOverride(PlayerScripts)

					InstancesOverrides[LocalPlayer] = {
						__Children = LocalPlayer:GetChildren(),
						Properties = { Name = "[" .. LocalPlayer.ClassName .. "] " .. LocalPlayer.Name },
					}
				end

				LocalPlayer:Kick("\n[SAFEMODE] Saving in Progress..\nPlease do NOT leave")
				wait_for_render()
				task.delay(10, service.GuiService.ClearError, service.GuiService)
			end)

			service.RunService:Set3dRenderingEnabled(false)
		end
		if SaveAsAttributes and not (OPTIONS.IsModel or OPTIONS.Object) then
			-- Could be remade to use save_extra with some modifications 
			local DataModelProperties = Instance.new("Configuration")
			DataModelProperties.Name = "DataModelProperties"
			SaveAttributes(game, true, "__NotSaveable_", DataModelProperties)
			DataModelProperties.Parent = game
			table.insert(ToSaveList, DataModelProperties)
		end
		local anti_idle
		if OPTIONS.AntiIdle then
			task.spawn(function()
				local Idled = GetLocalPlayer().Idled
				if getconnections then
					for _, c in getconnections(Idled) do
						if not pcall(function()
							c:Disable()
						end) then
							pcall(function()
								c:Disconnect()
							end)
						end
					end
				end
				anti_idle = Idled:Connect(function()
					service.VirtualInputManager:SendMouseWheelEvent(
						service.UserInputService:GetMouseLocation().X,
						service.UserInputService:GetMouseLocation().Y,
						true,
						game
					)
				end)
			end)
		end

		elapse_t = os.clock()

		local ok, err = xpcall(save_game, function(err)
			return debug.traceback(err)
		end)

		if SafeMode then
			service.GuiService:ClearError()
			service.RunService:Set3dRenderingEnabled(true)
		end

		if old_gethiddenproperty then
			gethiddenproperty = old_gethiddenproperty
		end

		if anti_idle then
			anti_idle:Disconnect()
		end
		if Connections then
			for _, connection in Connections do
				connection:Disconnect()
			end
		end
		GLOBAL_ENV[placename] = nil
		if StatusText then
			task.spawn(function()
				elapse_t = os.clock() - elapse_t
				local Log10 = math.log10(elapse_t)
				local ExtraTime = 10
				if ok then
					StatusText.Text = string.format("Saved! Time %.3f seconds; Size %s", elapse_t, get_size_format())
					StatusText.TextColor3 = Color3.new(0, 1)
					task.wait(Log10 * 2 + ExtraTime)
				else
					if Loading then
						task.cancel(Loading)
						Loading = nil
					end
					StatusText.Text = "Failed! Check F9 console for more info"
					StatusText.TextColor3 = Color3.new(1)
					warn("Error found while saving:")
					warn(err)
					task.wait(Log10 + ExtraTime)
				end
				StatusText:Destroy()
			end)
		end

		if OPTIONS.ShutdownWhenDone and ok then
			game:Shutdown()
		end
	end
end

return synsaveinstance
