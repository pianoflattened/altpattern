--[[
altpattern.lua

this is a library that will let you use the pipe `|` alternator as a magic
character in lua's native pattern matching functions
--]]

local M = {}
local rawfind   = string.find
local rawgmatch = string.gmatch
local rawgsub   = string.gsub
local rawgmatch = string.match

local function escape_len(text, i)
    if text:sub(i+1, i+1) == "b" then
        return 4 end
    return 2
end

local function skip_set(text, i)
	local n = #text
	i = i + 1
	if text:sub(i, i) == "^" then i = i+1 end
	if text:sub(i, i) == "]" then i = i+1 end
	while i <= n do
		local c = text:sub(i, i)
		if c == "%" then i = i + escape_len(text, i)
		elseif c == "]" then return i+1
		else i = i+1 end
	end
	return i
end

local function skip_group(text, i)
	local n = #text
	local depth = 0
	while i <= n do
		local c = text:sub(i, i)
		if c == "%" then i = i + escape_len(text, i)
		elseif c == "[" then i = skip_set(text, i)
		elseif c == "(" then 
		    depth = depth+1
		    i = i+1
		elseif c == ")" then
			depth = depth-1
			i = i+1
			if depth == 0 then return i end
		else i = i+1 end
	end
	return i
end

local function split_top_level(text)
	local branches, buf = {}, {}
	local i, n = 1, #text

	while i <= n do
		local c = text:sub(i, i)
		if c == "%" then
			local elen = escape_len(text, i)
			buf[#buf + 1] = text:sub(i, i + elen-1)
			i = i + elen
		elseif c == "[" then
			local j = skip_set(text, i)
			buf[#buf+1] = text:sub(i, j-1)
			i = j
		elseif c == "(" then
			local j = skip_group(text, i)
			buf[#buf+1] = text:sub(i, j-1)
			i = j
		elseif c == "|" then
			branches[#branches+1] = table.concat(buf)
            buf = {} 
			i = i+1
		else
			buf[#buf+1] = c
			i = i + 1
		end
	end
	
	branches[#branches+1] = table.concat(buf)
    buf = {} 
	return branches
end

local function atomize(branch)
	local n = #branch
	if n == 1 then
		local c = branch
		if c == "]" then return "%]" end
		if c == "^" then return "%^" end
		if c == "-" then return "%-" end
		if c == "%" then return nil end
		return c
	elseif n == 2 and branch:sub(1, 1) == "%" then
		return branch
	elseif n >= 2 and branch:sub(1, 1) == "[" and branch:sub(2, 2) ~= "^" then
		if skip_set(branch, 1) == n+1 then
			return branch:sub(2, n-1)
		end
	end
	return nil
end

local QUANTIFIERS = {["+"] = true, ["*"] = true, ["-"] = true, ["?"] = true}

local compile_scope
local function cartesian_programs(pieces)
	local results = { {} }
	for _, fragments in ipairs(pieces) do
		local next_results = {}
		for _, prog in ipairs(results) do
			for _, frag in ipairs(fragments) do
				local new_prog = {}
				for _, st in ipairs(prog) do new_prog[#new_prog+1] = st end
				for _, st in ipairs(frag) do
					local last = new_prog[#new_prog]
					if st.kind == "lit" and last and last.kind == "lit" then
						new_prog[#new_prog] = {
						    kind = "lit", 
						    text = last.text..st.text,
						}
					else
						new_prog[#new_prog+1] = st
					end
				end
				next_results[#next_results+1] = new_prog
			end
		end
		results = next_results
	end
	return results
end

local function compile_branch(text)
	local pieces, buf = {}, {}
	local i, n = 1, #text
	
	while i <= n do
		local c = text:sub(i, i)
		if c == "%" then
			local elen = escape_len(text, i)
			buf[#buf+1] = text:sub(i, i + elen-1)
			i = i + elen
		elseif c == "[" then
			local j = skip_set(text, i)
			buf[#buf+1] = text:sub(i, j-1)
			i = j
		elseif c == "(" then
			local j = skip_group(text, i)
			local inner = text:sub(i+1, j-2)
			local raw_alts = split_top_level(inner)
			local has_alt = #raw_alts > 1
			local quant = has_alt and QUANTIFIERS[text:sub(j, j)] and text:sub(j, j) or nil

			if #buf > 0 then
				pieces[#pieces+1] = {{{kind = "lit", text = table.concat(buf)}}}
				buf = {}
			end

			if quant then
				local contents, mergeable = {}, true
				for _, br in ipairs(raw_alts) do
					local a = atomize(br)
					if not a then 
					    mergeable = false 
					    break end
					contents[#contents+1] = a
				end
				if mergeable then
					pieces[#pieces+1] = {{{kind = "lit", text = "["..table.concat(contents).."]"..quant}}}
				else
					local alt_programs = {}
					for _, br in ipairs(raw_alts) do
						for _, prog in ipairs(compile_branch(br)) do
							for _, st in ipairs(prog) do
								if st.kind == "capture" then
									error(("altpattern: capture in a quantified multi-character" ..
												 "alternation group (%s)"):format(text:sub(i, j)), 0)
								end
							end
							alt_programs[#alt_programs+1] = prog
						end
					end
					
					pieces[#pieces+1] = {{{
						kind = "repeat", 
						alts = alt_programs, 
						quant = quant
					}}}
				end
				i = j+1
			else
				local inner_programs = compile_scope(inner)
				if has_alt then pieces[#pieces+1] = inner_programs
				else
					local opts = {}
					for _, prog in ipairs(inner_programs) do
						opts[#opts+1] = {{kind = "capture", steps = prog}} end
					pieces[#pieces+1] = opts
				end
				i = j
			end
		else
			buf[#buf+1] = c
			i = i+1
		end
	end
	
	if #buf > 0 then
		pieces[#pieces+1] = {{{
			kind = "lit", 
			text = table.concat(buf)
		}}}
		buf = {}
	end
	return cartesian_programs(pieces)
end

compile_scope = function(text)
	local results = {}
	for _, branch in ipairs(split_top_level(text)) do
		for _, prog in ipairs(compile_branch(branch)) do
			results[#results + 1] = prog
		end
	end
	return results
end

local function program_has_repeat(prog)
	for _, st in ipairs(prog) do
		if st.kind == "repeat" then return true
		elseif st.kind == "capture" and program_has_repeat(st.steps) then return true end
	end
	return false
end

local function render_program(prog)
	local parts = {}
	for _, st in ipairs(prog) do
		if st.kind == "lit" then parts[#parts+1] = st.text
		else parts[#parts+1] = "("..render_program(st.steps)..")" end
	end
	return table.concat(parts)
end

local compiled_cache = {}
local function get_compiled(pattern)
	local cached = compiled_cache[pattern]
	if cached then return cached end

	local programs = compile_scope(pattern)
	local any_repeat = false
	for _, prog in ipairs(programs) do
		if program_has_repeat(prog) then 
		    any_repeat = true 
		    break 
        end
	end

	local compiled
	if any_repeat then compiled = {mode = "program", programs = programs}
	else
		local flat = {}
		for _, prog in ipairs(programs) do flat[#flat+1] = render_program(prog) end
		compiled = {mode = "flat", alts = flat}
	end
	compiled_cache[pattern] = compiled
	return compiled
end

local function best_find(s, alts, init)
	local best
	for _, alt in ipairs(alts) do
		local res = {rawfind(s, alt, init)}
		local st = res[1]
		if st and (not best or st < best[1]) then
			best = res
		end
	end
	return best
end

local run_seq
local function match_repeat(step, s, pos0, steps, idx)
	local quant = step.quant
	local min_reps = (quant == "+") and 1 or 0
	local alts = step.alts
	local n_alts = #alts

	local stack = {{pos = pos0, reps = 0, alt_idx = 1, tried_stop = false}}
	local top = 1

	while top >= 1 do
		local f = stack[top]

		if quant == "-" then
			if not f.tried_stop then
				f.tried_stop = true
				if f.reps >= min_reps then
					local e, c = run_seq(steps, idx, s, f.pos)
					if e then return e, c end
				end
			end
		elseif quant == "?" and f.reps >= 1 then f.alt_idx = n_alts+1
		end

		local advanced = nil
		while f.alt_idx <= n_alts do
			local prog = alts[f.alt_idx]
			f.alt_idx = f.alt_idx + 1
			local end_pos = run_seq(prog, 1, s, f.pos)
			if end_pos and end_pos ~= f.pos then
				advanced = end_pos
				break
			end
		end

		if advanced then
			top = top+1
			stack[top] = {pos = advanced, reps = f.reps+1, alt_idx = 1, tried_stop = false}
		else
			if quant ~= "-" and not f.tried_stop then
				f.tried_stop = true
				if f.reps >= min_reps then
					local e, c = run_seq(steps, idx, s, f.pos)
					if e then return e, c end
				end
			end
			top = top-1
		end
	end

	return nil
end

run_seq = function(steps, idx, s, pos)
	if idx > #steps then
		return pos, {}
	end
	local step = steps[idx]

	if step.kind == "lit" then
		if not step.anchored then
			step.anchored = (step.text:sub(1, 1) == "^") and step.text or ("^" .. step.text)
		end
		local st, en = rawfind(s, step.anchored, pos)
		if not st then return nil end
		return run_seq(steps, idx+1, s, en+1)

	elseif step.kind == "capture" then
		local inner_end, inner_caps = run_seq(step.steps, 1, s, pos)
		if not inner_end then return nil end
		local whole = s:sub(pos, inner_end - 1)
		local rest_end, rest_caps = run_seq(steps, idx+1, s, inner_end)
		if not rest_end then return nil end
		local caps = { whole }
		for _, c in ipairs(inner_caps) do caps[#caps+1] = c end
		for _, c in ipairs(rest_caps) do caps[#caps+1] = c end
		return rest_end, caps

	elseif step.kind == "repeat" then
		return match_repeat(step, s, pos, steps, idx+1)
	end
end

local function run_programs_at(programs, s, pos)
	for _, prog in ipairs(programs) do
		local end_pos, caps = run_seq(prog, 1, s, pos)
		if end_pos then return end_pos, caps end
	end
	return nil
end

local function program_find(programs, s, init)
	for pos = init, #s + 1 do
		local end_pos, caps = run_programs_at(programs, s, pos)
		if end_pos then return pos, end_pos-1, caps end
	end
	return nil
end

local function normalize_init(s, init)
	init = init or 1
	local len = #s
	if init < 0 then
		init = len + init + 1
		if init < 1 then init = 1 end
	elseif init == 0 then
		init = 1
	end
	return init
end

local function pattern_find(s, pattern, init)
	local compiled = get_compiled(pattern)
	init = normalize_init(s, init)
	if compiled.mode == "flat" then
		local best = best_find(s, compiled.alts, init)
		if not best then return nil end
		return best[1], best[2], {table.unpack(best, 3)}
	else
		return program_find(compiled.programs, s, init)
	end
end

local function apply_repl(repl, whole, caps)
	local capvals = (#caps > 0) and caps or { whole }
	local t = type(repl)

	if t == "string" or t == "number" then
		repl = tostring(repl)
		local out = rawgsub(repl, "%%([%%%d])", function(d)
			if d == "%" then return "%" end
			local idx = tonumber(d)
			if idx == 0 then return whole end
			return tostring(capvals[idx] or "")
		end)
		return out
	elseif t == "table" then
		local v = repl[capvals[1]]
		if v == nil or v == false then return whole end
		return tostring(v)
	elseif t == "function" then
		local v = repl(table.unpack(capvals))
		if v == nil or v == false then return whole end
		return tostring(v)
	else
		error("bad replacement type: " .. t)
	end
end

function M.find(s, pattern, init, plain)
	if plain then return rawfind(s, pattern, init, plain) end
	local st, en, caps = pattern_find(s, pattern, init)
	if not st then return nil end
	if #caps > 0 then return st, en, table.unpack(caps) end
	return st, en
end

function M.match(s, pattern, init)
	local st, en, caps = pattern_find(s, pattern, init)
	if not st then return nil end
	if #caps > 0 then return table.unpack(caps) end
	return s:sub(st, en)
end

function M.gmatch(s, pattern)
	local compiled = get_compiled(pattern)
	if compiled.mode == "flat" and #compiled.alts == 1 then
		return rawgmatch(s, compiled.alts[1]) end

	local pos = 1
	local len = #s
	return function()
		if pos > len+1 then return nil end
		local st, en, caps = pattern_find(s, pattern, pos)
		if not st then
			pos = len + 2
			return nil
		end
		pos = (en < st) and (st+1) or (en+1)
		if #caps > 0 then return table.unpack(caps) end
		return s:sub(st, en)
	end
end

function M.gsub(s, pattern, repl, max_n)
	local compiled = get_compiled(pattern)
	if compiled.mode == "flat" and #compiled.alts == 1 then
		return rawgsub(s, compiled.alts[1], repl, max_n) end

	local pieces = {}
	local pos, count, len = 1, 0, #s

	while pos <= len+1 do
		if max_n and count >= max_n then break end
		local st, en, caps = pattern_find(s, pattern, pos)
		if not st then break end

		local whole = s:sub(st, en)
		pieces[#pieces+1] = s:sub(pos, st-1)
		pieces[#pieces+1] = apply_repl(repl, whole, caps)
		count = count+1

		if en < st then
			if st <= len then pieces[#pieces+1] = s:sub(st, st) end
			pos = st+1
		else pos = en+1 end
	end

	pieces[#pieces+1] = s:sub(pos)
	return table.concat(pieces), count
end

function M:overload(t)
    if t == nil then
        string.rawfind   = rawfind
        string.rawgmatch = rawgmatch
        string.rawgsub   = rawgsub
        string.rawmatch  = rawmatch
    else
        t.find   = rawfind
        t.gmatch = rawgmatch
        t.gsub   = rawgsub
        t.match  = rawmatch
    end

    string.find   = M.find
    string.gmatch = M.gmatch
    string.gsub   = M.gsub
    string.match  = M.match
end

return M
