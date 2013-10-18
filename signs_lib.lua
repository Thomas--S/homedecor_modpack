
-- Boilerplate to support localized strings if intllib mod is installed.
local S
if homedecor.intllib_modpath then
    dofile(homedecor.intllib_modpath.."/intllib.lua")
    S = intllib.Getter(minetest.get_current_modname())
else
    S = function ( s ) return s end
end

-- CONSTANTS

local MP = minetest.get_modpath("homedecor")

-- Used by `build_char_db' to locate the file.
local FONT_FMT = "%s/hdf_%02x.png"

-- Simple texture name for building text texture.
local FONT_FMT_SIMPLE = "hdf_%02x.png"

-- Path to the textures.
local TP = MP.."/textures"

local TEXT_SCALE = {x=0.9, y=0.5}

-- Lots of overkill here. KISS advocates, go away, shoo! ;) -- kaeza

local PNG_HDR = string.char(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)

-- Read the image size from a PNG file.
-- Returns image_w, image_h.
-- Only the LSB is read from each field!
local function read_png_size(f)
	f:seek("set", 0x0)
	local hdr = f:read(8)
	if hdr ~= PNG_HDR then return end
	f:seek("set", 0x13)
	local ws = f:read(1)
	f:seek("set", 0x17)
	local hs = f:read(1)
	return ws:byte(), hs:byte()
end

-- Set by build_char_db()
local LINE_HEIGHT
local SIGN_WIDTH
local SIGN_PADDING

-- Size of the canvas, in characters.
-- Please note that CHARS_PER_LINE is multiplied by the average character
-- width to get the total width of the canvas, so for proportional fonts,
-- either more or fewer characters may fit on a line.
local CHARS_PER_LINE = 30
local NUMBER_OF_LINES = 6

-- Separation between lines. 1.0 means no separation (ypos offset by text
-- height), 2.0 is one "line" (ypos offset by two times text height), etc.
local LINE_SEP = 1.2

-- This holds the individual character widths.
-- Indexed by the actual character (e.g. charwidth["A"])
local charwidth = { }

-- File to cache the font size to.
local CHARDB_FILE = minetest.get_worldpath().."/homedecor_chardb"

local function check_random_chars()
	for i = 1, 5 do
		local c = math.random(32, 126)
		local filename = FONT_FMT:format(TP, c)
		local f = io.open(filename)

		-- File does not exist (or cannot be read, or ...).
		-- Just assume it's different.
		if not f then return true end

		local w, h = read_png_size(f)
		f:close()

		-- File is not a PNG... wut?
		-- Just assume it's different.
		if not (w and h) then return true end

		local ch = string.char(c)
		if  (not charwidth[ch])                     -- Char is not cached.
		 or (charwidth[ch] ~= w)                    -- Width differs.
		 or (LINE_HEIGHT and (LINE_HEIGHT ~= h))    -- Height differs
		 then
			-- In any case, file is different; rebuild cache.
			return true
		end
	end
	-- OK, our superficial check passed. If the textures are messed up,
	-- it's not our problem.
	return false
end

local function build_char_db()

	LINE_HEIGHT = nil
	SIGN_WIDTH = nil
	SIGN_PADDING = nil

	-- To calculate average char width.
	local total_width = 0
	local char_count = 0

	-- Try to load cached data to avoid heavy disk I/O.

	local cdbf = io.open(CHARDB_FILE, "rt")

	if cdbf then
		minetest.log("info", "[homedecor] Reading cached character database.")
		for line in cdbf:lines() do
			local ch, w = line:match("(0x[0-9A-Fa-f]+)%s+([0-9][0-9]*)")
			if ch and w then
				local c = tonumber(ch)
				w = tonumber(w)
				print("*** DEBUG: c="..tostring(c)..", w="..tostring(w))
				if c and w then
					if c == 0 then
						LINE_HEIGHT = w
					elseif (c >= 32) and (c < 127) then
						charwidth[string.char(c)] = w
						total_width = total_width + w
						char_count = char_count + 1
					end
				end
			end
		end
		cdbf:close()
		if LINE_HEIGHT then
			-- Check some random characters to see if the file on disk differs
			-- from the cached one. If so, then ditch cached data and rebuild
			-- (font probably was changed).
			print("*** DEBUG: Randomly checking cache.")
			if not check_random_chars() then
				print("*** DEBUG: yey all ok.")
			end
			print("*** DEBUG: something's fucked up; rebuild cache.")
		else
			print("[homedecor] Warning:"
				.." Could not find font line height in cached DB."
				.." Trying brute force."
			)
			minetest.log("warning", "[homedecor]"
				.." Could not find font line height in cached DB."
				.." Trying brute force."
			)
		end
	end

	if not LINE_HEIGHT then
		-- OK, something went wrong... try brute force loading from texture files.

		charwidth = { }

		total_width = 0
		char_count = 0
		LINE_HEIGHT = nil

		for c = 32, 126 do
			local filename = FONT_FMT:format(TP, c)
			local f = io.open(filename)
			if f then
				local ch = string.char(c)
				local w, h = read_png_size(f)
				f:close()
				if w and h then
					charwidth[ch] = w
					total_width = total_width + w
					char_count = char_count + 1
					if not LINE_HEIGHT then LINE_HEIGHT = h end
				end
			end
		end

		if not LINE_HEIGHT then
			error("Could not find font line height.")
		end

	end

	-- XXX: Is there a better way to calc this?
	-- XXX: Remember to change similar lines below if this changes.
	SIGN_WIDTH = math.floor((total_width / char_count) * CHARS_PER_LINE)
	SIGN_PADDING = SIGN_WIDTH / 16 -- Totally arbitrary.

	-- Try to save cached list back to disk.

	local e -- Note: `cdbf' is already declared local above.
	cdbf, e = io.open(CHARDB_FILE, "wt")
	if not cdbf then
		minetest.log("warning", "[homedecor] Could not save cached char DB: "..(e or ""))
		return
	end

	cdbf:write(("0x00 %d\n"):format(LINE_HEIGHT))
	for c = 32, 126 do
		local w = charwidth[string.char(c)]
		if w then
			cdbf:write(("0x%02X %d\n"):format(c, w))
		end
	end
	cdbf:close()

end

local signs = {
    {delta = {x =  0,     y = 0.15, z =  0.399}, yaw = 0},
    {delta = {x =  0.399, y = 0.15, z =  0    }, yaw = math.pi / -2},
    {delta = {x =  0,     y = 0.15, z = -0.399}, yaw = math.pi},
    {delta = {x = -0.399, y = 0.15, z =  0    }, yaw = math.pi / 2},
}

local signs_yard = {
    {delta = {x =  0,     y = 0.15, z = -0.05}, yaw = 0},
    {delta = {x = -0.05,  y = 0.15, z =  0   }, yaw = math.pi / -2},
    {delta = {x =  0,     y = 0.15, z =  0.05}, yaw = math.pi},
    {delta = {x =  0.05,  y = 0.15, z =  0   }, yaw = math.pi / 2},
}

local signs_post = {
    {delta = {x = 0,      y = 0.15, z = -0.226}, yaw = 0},
    {delta = {x = -0.226, y = 0.15, z = 0     }, yaw = math.pi / -2},
    {delta = {x = 0,      y = 0.15, z = 0.226 }, yaw = math.pi},
    {delta = {x = 0.226,  y = 0.15, z = 0     }, yaw = math.pi / 2},
}

local sign_groups = {choppy=2, dig_immediate=2}

local fences_with_sign = { }

-- some local helper functions

local homedecor_create_lines = function(text)
	local tab = {}
	for line in text:gmatch("([^|]+)|?") do
		line = line:gsub("^%s*(.*)%s*$", "%1") -- Trim whitespace
		table.insert(tab, line)
		if #tab >= NUMBER_OF_LINES then break end
	end
	return tab
end

local math_max = math.max

local homedecor_generate_line = function(s, lineno)

	local width = 0
	local maxw = 0

	local chars = { }

	local max_line_w = SIGN_WIDTH - (SIGN_PADDING * 2)

	-- We check which chars are available here.
	for i = 1, #s do
		local c = s:sub(i, i)
		local w = charwidth[c]
		if w then
			width = width + w + 1
			maxw = math_max(width, maxw)
			if width >= max_line_w then
				width = 0
			end
			table.insert(chars, c)
		end
	end

	maxw = maxw - 1

	-- Okay, we actually build the "line texture" here.

	local start_xpos = math.floor((SIGN_WIDTH - 2 * SIGN_PADDING - maxw) / 2 + SIGN_PADDING)
	local xpos = start_xpos
	local texture = { }
	local ypos = (LINE_HEIGHT * (lineno --[[+ 1]]))

	width = 0

	for i = 1, #s do
		local c = s:sub(i, i)
		local w = charwidth[c]
		local tex = FONT_FMT_SIMPLE:format(c:byte())
		table.insert(texture, (":%d,%d=%s"):format(xpos, ypos, tex))
		xpos = xpos + w + 1
		width = width + w + 1
		if width > max_line_w then
			xpos = start_xpos
			ypos = ypos + (LINE_HEIGHT * LINE_SEP)
			width = 0
			lineno = lineno + 1
		end
		if lineno >= NUMBER_OF_LINES then break end
	end

	return table.concat(texture, ""), lineno
end

local function copy ( t )
    local nt = { };
    for k, v in pairs(t) do
        if type(v) == "table" then
            nt[k] = copy(v)
        else
            nt[k] = v
        end
    end
    return nt
end

local homedecor_generate_texture = function(lines)
    local texture = { ("[combine:%dx%d"):format(SIGN_WIDTH, LINE_HEIGHT * NUMBER_OF_LINES * LINE_SEP) }
    local lineno = 0
    for i = 1, #lines do
		if lineno >= NUMBER_OF_LINES then break end
        local linetex, ln = homedecor_generate_line(lines[i], lineno)
        table.insert(texture, linetex)
        lineno = ln + 1
    end
    return table.concat(texture, "")
end

local function set_obj_text(obj, text)
	obj:set_properties({
		textures={homedecor_generate_texture(homedecor_create_lines(text))},
		visual_size = TEXT_SCALE,
	})
end

homedecor.construct_sign = function(pos)
    local meta = minetest.get_meta(pos)
	meta:set_string("formspec", "field[text;;${text}]")
	meta:set_string("infotext", "")
end

homedecor.destruct_sign = function(pos)
    local objects = minetest.get_objects_inside_radius(pos, 0.5)
    for _, v in ipairs(objects) do
        if v:get_entity_name() == "signs:text" then
            v:remove()
        end
    end
end

homedecor.update_sign = function(pos, fields)
    local meta = minetest.get_meta(pos)
	if fields then
		meta:set_string("infotext", table.concat(homedecor_create_lines(fields.text), "\n"))
		meta:set_string("text", fields.text)
	end
    local text = meta:get_string("text")
    local objects = minetest.get_objects_inside_radius(pos, 0.5)
    for _, v in ipairs(objects) do
        if v:get_entity_name() == "signs:text" then
			set_obj_text(v, text)
			return
        end
    end
	
	-- if there is no entity
	local sign_info
	if minetest.get_node(pos).name == "signs:sign_yard" then
		sign_info = signs_yard[minetest.get_node(pos).param2 + 1]
	elseif minetest.get_node(pos).name == "default:sign_wall" then
		sign_info = signs[minetest.get_node(pos).param2 + 1]
	else --if minetest.get_node(pos).name == "signs:sign_post" then
		sign_info = signs_post[minetest.get_node(pos).param2 + 1]
	end
	if sign_info == nil then
		return
	end
	local text = minetest.add_entity({x = pos.x + sign_info.delta.x,
										y = pos.y + sign_info.delta.y,
										z = pos.z + sign_info.delta.z}, "signs:text")
	text:setyaw(sign_info.yaw)
end

if not homedecor.disable_signs then
	minetest.register_node(":default:sign_wall", {
		description = "Sign",
		inventory_image = "default_sign_wall.png",
		wield_image = "default_sign_wall.png",
		node_placement_prediction = "",
		paramtype = "light",
		sunlight_propagates = true,
		paramtype2 = "facedir",
		drawtype = "nodebox",
		node_box = {type = "fixed", fixed = {-0.45, -0.15, 0.4, 0.45, 0.45, 0.498}},
		selection_box = {type = "fixed", fixed = {-0.45, -0.15, 0.4, 0.45, 0.45, 0.498}},
		tiles = {"signs_top.png", "signs_bottom.png", "signs_side.png", "signs_side.png", "signs_back.png", "signs_front.png"},
		groups = sign_groups,

		on_place = function(itemstack, placer, pointed_thing)
			local name
			name = minetest.get_node(pointed_thing.under).name
			if fences_with_sign[name] then
				if homedecor:node_is_owned(pointed_thing.under, placer) then
					return itemstack
				end
			else
				name = minetest.get_node(pointed_thing.above).name
				local def = minetest.registered_nodes[name]
				if homedecor:node_is_owned(pointed_thing.above, placer)
				 or (not def.buildable_to) then
					return itemstack
				end
			end

		local node=minetest.get_node(pointed_thing.under)

		if minetest.registered_nodes[node.name] and minetest.registered_nodes[node.name].on_rightclick then
			return minetest.registered_nodes[node.name].on_rightclick(pointed_thing.under, node, placer)
		else
			local above = pointed_thing.above
			local under = pointed_thing.under
			local dir = {x = under.x - above.x,
						 y = under.y - above.y,
						 z = under.z - above.z}

			local wdir = minetest.dir_to_wallmounted(dir)

			local placer_pos = placer:getpos()
			if placer_pos then
				dir = {
					x = above.x - placer_pos.x,
					y = above.y - placer_pos.y,
					z = above.z - placer_pos.z
				}
			end

			local fdir = minetest.dir_to_facedir(dir)

			local sign_info
			local pt_name = minetest.get_node(under).name
			print(dump(pt_name))

			if fences_with_sign[pt_name] then
				minetest.add_node(under, {name = fences_with_sign[pt_name], param2 = fdir})
				sign_info = signs_post[fdir + 1]

			elseif wdir == 0 then
				--how would you add sign to ceiling?
				minetest.add_item(above, "default:sign_wall")
					itemstack:take_item()
					return itemstack
			elseif wdir == 1 then
				minetest.add_node(above, {name = "signs:sign_yard", param2 = fdir})
				sign_info = signs_yard[fdir + 1]
			else
				minetest.add_node(above, {name = "default:sign_wall", param2 = fdir})
				sign_info = signs[fdir + 1]
			end

			local text = minetest.add_entity({x = above.x + sign_info.delta.x,
												  y = above.y + sign_info.delta.y,
												  z = above.z + sign_info.delta.z}, "signs:text")
			text:setyaw(sign_info.yaw)

			
			if not homedecor.expect_infinite_stacks then
				itemstack:take_item()
			end
			return itemstack
		end
		end,
		on_construct = function(pos)
			homedecor.construct_sign(pos)
		end,
		on_destruct = function(pos)
			homedecor.destruct_sign(pos)
		end,
		on_receive_fields = function(pos, formname, fields, sender)
			if fields then
				print(S("%s wrote \"%s\" to sign at %s"):format(
					(sender:get_player_name() or ""),
					fields.text,
					minetest.pos_to_string(pos)
				))
			end
			if homedecor:node_is_owned(pos, sender) then return end
			homedecor.update_sign(pos, fields)
		end,
		on_punch = function(pos, node, puncher)
			homedecor.update_sign(pos)
		end,
	})
end

minetest.register_node(":signs:sign_yard", {
    paramtype = "light",
	sunlight_propagates = true,
    paramtype2 = "facedir",
    drawtype = "nodebox",
    node_box = {type = "fixed", fixed = {
        {-0.45, -0.15, -0.049, 0.45, 0.45, 0.049},
        {-0.05, -0.5, -0.049, 0.05, -0.15, 0.049}
    }},
    selection_box = {type = "fixed", fixed = {-0.45, -0.15, -0.049, 0.45, 0.45, 0.049}},
    tiles = {"signs_top.png", "signs_bottom.png", "signs_side.png", "signs_side.png", "signs_back.png", "signs_front.png"},
    groups = {choppy=2, dig_immediate=2},
    drop = "default:sign_wall",

    on_construct = function(pos)
        homedecor.construct_sign(pos)
    end,
    on_destruct = function(pos)
        homedecor.destruct_sign(pos)
    end,
    on_receive_fields = function(pos, formname, fields, sender)
        if fields then
            print(S("%s wrote \"%s\" to sign at %s"):format(
                (sender:get_player_name() or ""),
                fields.text,
                minetest.pos_to_string(pos)
            ))
        end
		if homedecor:node_is_owned(pos, sender) then return end
        homedecor.update_sign(pos, fields)
    end,
	on_punch = function(pos, node, puncher)
		homedecor.update_sign(pos)
	end,
})

minetest.register_node(":signs:sign_post", {
    paramtype = "light",
	sunlight_propagates = true,
    paramtype2 = "facedir",
    drawtype = "nodebox",
    node_box = {
	type = "fixed",
	fixed = { 
		{ -0.125, -0.5, -0.125, 0.125, 0.5, 0.125 },
		{ -0.45, -0.15, -0.225, 0.45, 0.45, -0.125 },
	}
    },
    selection_box = {
	type = "fixed",
	fixed = { 
		{ -0.125, -0.5, -0.125, 0.125, 0.5, 0.125 },
		{ -0.45, -0.15, -0.225, 0.45, 0.45, -0.125 },
	}
    },
    tiles = {
	"signs_post_top.png",
	"signs_post_bottom.png",
	"signs_post_side.png",
	"signs_post_side.png",
	"signs_post_back.png",
	"signs_post_front.png",
    },
    groups = {choppy=2, dig_immediate=2},
    drop = {
	max_items = 2,
	items = {
		{ items = { "default:sign_wall" }},
		{ items = { "default:fence_wood" }},
	},
    },
})

local signs_text_on_activate

if not homedecor.disable_signs then
	signs_text_on_activate = function(self)
		local meta = minetest.get_meta(self.object:getpos())
		local text = meta:get_string("text")
		set_obj_text(self.object, text)
	end
else
	signs_text_on_activate = function(self)
		self.object:remove()
	end
end


minetest.register_entity(":signs:text", {
    collisionbox = { 0, 0, 0, 0, 0, 0 },
    visual = "upright_sprite",
    textures = {},

	on_activate = signs_text_on_activate,
})

-- And the good stuff here! :-)

function homedecor.register_fence_with_sign(fencename, fencewithsignname)
    local def = minetest.registered_nodes[fencename]
    local def_sign = minetest.registered_nodes[fencewithsignname]
    if not (def and def_sign) then
        minetest.log("warning", "[homedecor] Attempt to register unknown node as fence")
        return
    end
    def = copy(def)
    def_sign = copy(def_sign)
    fences_with_sign[fencename] = fencewithsignname

    def.on_place = function(itemstack, placer, pointed_thing, ...)
		local node_above = minetest.get_node(pointed_thing.above)
		local node_under = minetest.get_node(pointed_thing.under)
		local def_above = minetest.registered_nodes[node_above.name]
		local def_under = minetest.registered_nodes[node_under.name]
		local fdir = minetest.dir_to_facedir(placer:get_look_dir())
		if def_under and def_under.on_rightclick then
			return def_under.on_rightclick(pointed_thing.under, node_under, placer, itemstack) or itemstack
		elseif (not homedecor:node_is_owned(pointed_thing.under, placer))
		 and def_under.buildable_to then
			minetest.add_node(pointed_thing.under, {name = fencename, param2 = fdir})
			if not homedecor.expect_infinite_stacks then
				itemstack:take_item()
			end
			placer:set_wielded_item(itemstack)
			return itemstack
		elseif (not homedecor:node_is_owned(pointed_thing.above, placer))
		 and def_above.buildable_to then
			minetest.add_node(pointed_thing.above, {name = fencename, param2 = fdir})
			if not homedecor.expect_infinite_stacks then
				itemstack:take_item()
			end
			placer:set_wielded_item(itemstack)
			return itemstack
		end
	end
	def_sign.on_construct = function(pos, ...)
		homedecor.construct_sign(pos)
	end
	def_sign.on_destruct = function(pos, ...)
		homedecor.destruct_sign(pos)
	end
	def_sign.on_receive_fields = function(pos, formname, fields, sender, ...)
        if fields then
            print(S("%s wrote \"%s\" to sign at %s"):format(
                (sender:get_player_name() or ""),
                fields.text,
                minetest.pos_to_string(pos)
            ))
        end
		if homedecor:node_is_owned(pos, sender) then return end
		homedecor.update_sign(pos, fields)
	end
	def_sign.on_punch = function(pos, node, puncher, ...)
		homedecor.update_sign(pos)
	end
	local fencename = fencename
	def_sign.after_dig_node = function(pos, node, ...)
	    node.name = fencename
	    minetest.add_node(pos, node)
	end
    def_sign.drop = "default:sign_wall"
	minetest.register_node(":"..fencename, def)
	minetest.register_node(":"..fencewithsignname, def_sign)
	print("Registered "..fencename.." and "..fencewithsignname)
end

build_char_db()

if minetest.setting_get("log_mods") then
	minetest.log("action", S("signs loaded"))
end
