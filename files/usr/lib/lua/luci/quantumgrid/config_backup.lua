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

function validate_archive_size(size)
	if type(size) ~= "number" or size ~= math.floor(size)
		or size < 1 or size > MAX_ARCHIVE_BYTES then
		return nil, "The generated backup is empty or exceeds the 64 MiB download limit."
	end
	return size
end

return _M
