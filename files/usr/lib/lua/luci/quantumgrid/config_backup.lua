module("luci.quantumgrid.config_backup", package.seeall)

local MAX_ARCHIVE_BYTES = 64 * 1024 * 1024

function validate_confirmation(value)
	if value ~= "1" then
		return nil, "Explicit confirmation is required before creating a configuration backup."
	end
	return true
end

function validate_temp_path(path)
	if type(path) ~= "string" or #path > 128
		or not path:match("^/tmp/quantumgrid%-config%-backup%.[%w]+$") then
		return nil, "The temporary backup path is not a reserved QuantumGrid /tmp file name."
	end
	return path
end

function validate_restore_temp_path(path)
	if type(path) ~= "string" or #path > 128
		or not path:match("^/tmp/quantumgrid%-config%-restore%.[%w]+$") then
		return nil, "The temporary restore path is not a reserved QuantumGrid /tmp file name."
	end
	return path
end

function validate_rollback_temp_path(path)
	if type(path) ~= "string" or #path > 128
		or not path:match("^/tmp/quantumgrid%-config%-rollback%.[%w]+$") then
		return nil, "The temporary rollback path is not a reserved QuantumGrid /tmp file name."
	end
	return path
end

function validate_archive_size(size)
	if type(size) ~= "number" or size ~= math.floor(size)
		or size < 1 or size > MAX_ARCHIVE_BYTES then
		return nil, "The generated backup is empty or exceeds the 64 MiB download limit."
	end
	return size
end

function validate_restore_confirmation(confirmed, same_device_confirmed)
	if confirmed ~= "1" or same_device_confirmed ~= "1" then
		return nil, "Explicit restore confirmation and same-device acknowledgement are required."
	end
	return true
end

local function valid_archive_path(path)
	if type(path) ~= "string" or #path < 1 or #path > 512 or
		path:find("[%z\1-\31\127]") or path:find("\\", 1, true) or
		path:sub(1, 1) == "/" or path:find("//", 1, true) then
		return nil
	end
	if path:sub(1, 2) == "./" then path = path:sub(3) end
	if path:sub(-1) == "/" then path = path:sub(1, -2) end
	if path == "" or path:sub(1, 1) == "/" then return nil end
	local count = 0
	for component in path:gmatch("[^/]+") do
		count = count + 1
		if component == "." or component == ".." or #component > 128 or
			not component:match("^[%w_%.%+@%-]+$") then return nil end
	end
	if count < 1 or path:sub(-1) == "/" then return nil end
	if path ~= "etc" and path ~= "root" and
		not path:match("^etc/") and not path:match("^root/") then return nil end
	return path
end

function validate_archive_listing(listing)
	if type(listing) ~= "string" or #listing < 1 or #listing > 4 * 1024 * 1024 then
		return nil, "The archive member listing is unavailable or exceeds the safe inspection limit."
	end
	local entries = {}
	local seen = {}
	local has_config = false
	local device_id_path = nil
	local profile_path = nil
	local release_path = nil
	local count = 0
	local expanded_size = 0
	for line in listing:gmatch("[^\r\n]+") do
		count = count + 1
		if count > 8192 then
			return nil, "The archive contains too many entries for a safe configuration restore."
		end
		if line:find(" link to ", 1, true) or line:find(" -> ", 1, true) then
			return nil, "The archive contains a hard link or symbolic link; links are never restored."
		end
		local kind = line:sub(1, 1)
		if kind ~= "-" and kind ~= "d" then
			return nil, "The archive contains a link or special file; only regular files and directories can be restored."
		end
		local tokens = {}
		for token in line:gmatch("%S+") do tokens[#tokens + 1] = token end
		local mode = tokens[1]
		if type(mode) ~= "string" or #mode ~= 10 or
			(mode:sub(1, 1) ~= "-" and mode:sub(1, 1) ~= "d") or
			mode:find("[sStT]") then
			return nil, "The archive contains an invalid, set-ID or sticky permission mode."
		end
		local entry_size = nil
		for index, token in ipairs(tokens) do
			if token:match("^%d%d%d%d%-%d%d%-%d%d$") then
				local candidate = tokens[index - 1]
				if candidate and candidate:match("^%d+$") then entry_size = tonumber(candidate) end
				break
			end
		end
		if entry_size == nil or entry_size < 0 then
			return nil, "The archive listing format is not recognised; restore was refused."
		end
		if kind == "-" then
			expanded_size = expanded_size + entry_size
			if expanded_size > 128 * 1024 * 1024 then
				return nil, "The uncompressed archive exceeds the 128 MiB restore safety limit."
			end
		end
		local raw_path = line:match("%s([^%s]+)$")
		local path = valid_archive_path(raw_path)
		if not path then
			return nil, "The archive contains a path outside the permitted etc/ and root/ trees."
		end
		if seen[path] then return nil, "The archive contains duplicate member paths." end
		seen[path] = true
		if path:match("^etc/config/[^/]+$") and kind == "-" then has_config = true end
		if path == "etc/quantumgrid/device-id" then
			if kind ~= "-" then return nil, "The device identity in the archive must be a regular file." end
			device_id_path = raw_path
		elseif path == "etc/quantumgrid/device-profile.json" then
			if kind ~= "-" then return nil, "The hardware profile in the archive must be a regular file." end
			profile_path = raw_path
		elseif path == "etc/openwrt_release" then
			if kind ~= "-" then return nil, "The OpenWrt release marker in the archive must be a regular file." end
			release_path = raw_path
		end
		entries[#entries + 1] = { path = path, kind = kind, size = entry_size }
	end
	if count == 0 or not has_config then
		return nil, "The archive does not contain a native /etc/config backup."
	end
	if not device_id_path or not profile_path or not release_path then
		return nil, "The archive is missing its device identity, hardware profile or OpenWrt target marker; create a fresh backup with this firmware before restoring."
	end
	return {
		entries = entries,
		count = count,
		expanded_size = expanded_size,
		device_id_path = device_id_path,
		profile_path = profile_path,
		release_path = release_path
	}
end

function validate_platform_compatibility(archive_target, current_target, archive_arch, current_arch)
	if type(archive_target) ~= "string" or type(current_target) ~= "string" or
		type(archive_arch) ~= "string" or type(current_arch) ~= "string" or
		#archive_target < 1 or #current_target < 1 or #archive_arch < 1 or #current_arch < 1 or
		#archive_target > 128 or #current_target > 128 or #archive_arch > 128 or #current_arch > 128 or
		archive_target:find("[%c]") or current_target:find("[%c]") or
		archive_arch:find("[%c]") or current_arch:find("[%c]") then
		return nil, "The archive or current firmware target metadata is unavailable or malformed."
	end
	if archive_target ~= current_target or archive_arch ~= current_arch then
		return nil, "This backup targets a different OpenWrt target or architecture. Cross-platform restore is blocked."
	end
	return true
end

function validate_device_identity(archive_id, current_id)
	if type(archive_id) ~= "string" or type(current_id) ~= "string" then
		return nil, "The current or archived QuantumGrid device identity is unavailable."
	end
	archive_id = archive_id:gsub("\n$", "")
	current_id = current_id:gsub("\n$", "")
	if #archive_id ~= 32 or #current_id ~= 32 or
		not archive_id:match("^[0-9a-f]+$") or not current_id:match("^[0-9a-f]+$") then
		return nil, "The archive or router device identity is malformed."
	end
	if archive_id ~= current_id then
		return nil, "This backup belongs to a different QuantumGrid device. Cross-device restore is blocked."
	end
	return true
end

return _M
