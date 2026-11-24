module("luci.controller.quantumgrid_policing", package.seeall)

local function respond(http, status, payload)
	if status then
		http.status(status, status == 400 and "Bad Request" or
			status == 403 and "Forbidden" or status == 404 and "Not Found" or
			status == 405 and "Method Not Allowed" or status == 409 and "Conflict" or
			status == 502 and "Bad Gateway" or status == 503 and "Service Unavailable" or
			"Internal Server Error")
	end
	http.header("Cache-Control", "no-store")
	http.prepare_content("application/json; charset=UTF-8")
	http.write_json(payload)
end

local function safe_name(value)
	return type(value) == "string" and #value > 0 and #value <= 64 and value:match("^[%w_.%-]+$") ~= nil
end

local function safe_device(value)
	return type(value) == "string" and #value > 0 and #value <= 15 and value:match("^[%w_.:%-]+$") ~= nil
end

local function list(value)
	if type(value) == "string" then return { value } end
	if type(value) == "table" then return value end
	return {}
end

local function interface_status(name)
	local ubus = require "ubus"
	local connection = ubus.connect()
	if not connection then return {} end
	local ok, status = pcall(connection.call, connection, "network.interface." .. name, "status", {})
	pcall(connection.close, connection)
	return ok and type(status) == "table" and status or {}
end

local function collect_inventory(uci, fs)
	local result = {
		available = false, firewall_available = false, dhcp_available = false,
		truncated = false, interfaces = {}, zones = {}, static_leases = {}
	}
	local network_ok = pcall(function()
		uci:foreach("network", "interface", function(section)
			if #result.interfaces >= 64 then result.truncated = true; return end
			local name = section[".name"]
			if not safe_name(name) then return end
			local device = section.device
			if type(device) ~= "string" or not safe_device(device) then device = section.ifname or "" end
			if device ~= "" and not safe_device(device) then device = "" end
			local status = interface_status(name)
			local l3_device = status.l3_device or status.device or device
			if not safe_device(l3_device) then l3_device = device end
			local ipv4 = section.ipaddr
			if type(ipv4) == "string" then ipv4 = { ipv4 } end
			if type(ipv4) ~= "table" then ipv4 = {} end
			result.interfaces[#result.interfaces + 1] = {
				name = name, protocol = type(section.proto) == "string" and section.proto or "",
				device = device, l3_device = l3_device, up = status.up == true,
				ipv4 = ipv4, netmask = section.netmask,
				firewall_zones = {}
			}
		end)
	end)
	result.available = network_ok and fs.access("/etc/config/network") == true

	local firewall_ok = pcall(function()
		uci:foreach("firewall", "zone", function(section)
			if #result.zones >= 32 then result.truncated = true; return end
			local name = section.name or section[".name"]
			if not safe_name(name) then return end
			local networks = {}
			for _, network in ipairs(list(section.network)) do
				if safe_name(network) then networks[#networks + 1] = network end
			end
			result.zones[#result.zones + 1] = {
				name = name, networks = networks, masquerade = section.masq == "1"
			}
			for _, iface in ipairs(result.interfaces) do
				for _, network in ipairs(networks) do
					if iface.name == network then
						iface.firewall_zones[#iface.firewall_zones + 1] = name
						break
					end
				end
			end
		end)
	end)
	result.firewall_available = firewall_ok and fs.access("/etc/config/firewall") == true

	local dhcp_ok = pcall(function()
		uci:foreach("dhcp", "host", function(section)
			if #result.static_leases >= 256 then result.truncated = true; return end
			result.static_leases[#result.static_leases + 1] = {
				section = section[".name"], name = section.name or section[".name"],
				mac = section.mac, ipv4 = section.ip
			}
		end)
	end)
	result.dhcp_available = dhcp_ok and fs.access("/etc/config/dhcp") == true
	return result
end

local function read_runtime(fs, jsonc)
	local raw = fs.readfile("/var/run/quantumgrid-client-policing.status.json")
	if type(raw) ~= "string" or #raw > 65536 then return nil end
	local ok, parsed = pcall(jsonc.parse, raw)
	if not ok or type(parsed) ~= "table" then return nil end
	parsed.stale = type(parsed.sampled_at) ~= "number" or os.time() - parsed.sampled_at > 300
	return parsed
end

local function read_saved(uci)
	local records, total = {}, 0
	local ok = pcall(function()
		uci:foreach("quantumgrid-qos", "client", function(section)
			total = total + 1
			if #records >= 32 then return end
			local name = section[".name"]
			if not safe_name(name) then return end
			records[#records + 1] = {
				section = name, slot = tonumber(section.slot), name = section.name,
				mac = section.mac, client_ip = section.client_ip,
				source_zone = section.source_zone, destination_zone = section.destination_zone,
				upload_kbps = section.upload_kbps or "", download_kbps = section.download_kbps or "",
				enabled = section.enabled or "0"
			}
		end)
	end)
	if not ok or total > 32 or total ~= #records then
		return nil, "The client policing UCI inventory is unavailable, oversized or malformed."
	end
	return records
end

local function audit(action, target, outcome, http)
	local ok, module = pcall(require, "luci.quantumgrid.audit")
	if not ok or type(module) ~= "table" or type(module.append) ~= "function" then return false end
	local write_ok, written = pcall(module.append, {
		timestamp = os.time(), actor = "root",
		remote_ip = http.getenv("REMOTE_ADDR") or "",
		action = action, target = target, outcome = outcome
	})
	return write_ok and written == true
end

local function run_worker(sys, fs, jsonc)
	local started = os.time()
	local ok, status = pcall(sys.call, "/usr/bin/quantumgrid-client-policing >/dev/null 2>&1")
	local runtime = read_runtime(fs, jsonc)
	if not ok or status ~= 0 or type(runtime) ~= "table" or
		runtime.available ~= true or runtime.ready ~= true or
		type(runtime.sampled_at) ~= "number" or runtime.sampled_at < started then
		return nil, runtime and runtime.error or "The policer worker did not publish fresh verified status."
	end
	return runtime
end

function action_client_policing()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local sys = require "luci.sys"
	local jsonc = require "luci.jsonc"
	local transport = require "luci.quantumgrid.management_transport"
	local uci = require("luci.model.uci").cursor()
	local manager = require "luci.quantumgrid.qos_policing"
	local method = http.getenv("REQUEST_METHOD")
	local host = http.getenv("HTTP_HOST")
	local origin = http.getenv("HTTP_ORIGIN")
	local scheme = http.getenv("HTTPS") == "on" and "https" or "http"

	if not transport.require_https(http) then return end
	if method == "GET" then
		local runtime = read_runtime(fs, jsonc)
		if fs.access("/etc/config/quantumgrid-qos") ~= true or fs.access("/usr/bin/quantumgrid-client-policing") ~= true then
			respond(http, nil, { ok = true, available = false, inventory_available = false, policies = {}, runtime = runtime,
				error = "Client policing configuration or worker is unavailable." })
			return
		end
		local records, read_error = read_saved(uci)
		if not records then
			respond(http, nil, { ok = true, available = true, inventory_available = false, policies = {}, runtime = runtime, error = read_error })
			return
		end
		local inventory = collect_inventory(uci, fs)
		if not inventory.available or not inventory.firewall_available or not inventory.dhcp_available or inventory.truncated then
			respond(http, nil, { ok = true, available = true, inventory_available = false, policies = {}, runtime = runtime,
				error = "Network, firewall or static DHCP reservation inventory is unavailable or truncated." })
			return
		end
		local policies, validation_error = manager.validate_saved_policies(records, inventory.zones, inventory.interfaces, inventory.static_leases)
		if not policies then
			respond(http, nil, { ok = true, available = true, inventory_available = false, policies = {}, runtime = runtime, error = validation_error })
			return
		end
		respond(http, nil, { ok = true, available = true, inventory_available = true, policies = policies, runtime = runtime })
		return
	end

	if method ~= "POST" then respond(http, 405, { ok = false, error = "GET or POST is required." }); return end
	if not host or origin ~= scheme .. "://" .. host then
		respond(http, 403, { ok = false, error = "A same-origin request is required." }); return
	end
	if http.formvalue("confirmed", true) ~= "1" then
		respond(http, 400, { ok = false, error = "Explicit confirmation is required before changing a client bandwidth policer." }); return
	end
	if fs.access("/etc/config/quantumgrid-qos") ~= true or
		fs.access("/etc/config/network") ~= true or fs.access("/etc/config/firewall") ~= true or
		fs.access("/etc/config/dhcp") ~= true or fs.access("/usr/bin/quantumgrid-client-policing") ~= true then
		respond(http, 503, { ok = false, error = "Client policing worker or required network/firewall/DHCP configuration is unavailable." }); return
	end

	local inventory = collect_inventory(uci, fs)
	if not inventory.available or not inventory.firewall_available or not inventory.dhcp_available or inventory.truncated then
		respond(http, 409, { ok = false, error = "Network, firewall or DHCP inventory is unavailable or truncated. No policy was changed." }); return
	end
	local records, read_error = read_saved(uci)
	if not records then respond(http, 409, { ok = false, error = read_error }); return end

	local operation = http.formvalue("operation", true)
	if operation == "add" then
		local existing, existing_error = manager.validate_saved_policies(records, inventory.zones, inventory.interfaces, inventory.static_leases)
		if not existing then respond(http, 409, { ok = false, error = existing_error }); return end
		if #existing >= 32 then respond(http, 409, { ok = false, error = "The 32-entry client policing inventory is full." }); return end
		local used = {}
		for _, policy in ipairs(existing) do used[policy.slot] = true end
		local slot
		for i = 1, 32 do if not used[i] then slot = i; break end end
		if not slot then respond(http, 409, { ok = false, error = "No client policing filter slots remain." }); return end
		local section = string.format("qg_rate_%02d", slot)
		local policy, validation_error = manager.validate_policy({
			section = section, slot = slot, name = http.formvalue("name", true),
			mac = http.formvalue("mac", true), client_ip = http.formvalue("client_ip", true),
			source_zone = http.formvalue("source_zone", true), destination_zone = http.formvalue("destination_zone", true),
			upload_kbps = http.formvalue("upload_kbps", true), download_kbps = http.formvalue("download_kbps", true)
		}, inventory.zones, inventory.interfaces, inventory.static_leases)
		if not policy then respond(http, 400, { ok = false, error = validation_error }); return end
		for _, saved in ipairs(existing) do
			if saved.mac == policy.mac or saved.client_ip == policy.client_ip then
				respond(http, 409, { ok = false, error = "A client policing policy already exists for this MAC or static reservation." }); return
			end
		end
		local values = {
			slot = tostring(slot), name = policy.name, mac = policy.mac,
			client_ip = policy.client_ip, source_zone = policy.source_zone,
			destination_zone = policy.destination_zone, enabled = "1"
		}
		if policy.upload_kbps then values.upload_kbps = tostring(policy.upload_kbps) end
		if policy.download_kbps then values.download_kbps = tostring(policy.download_kbps) end
		local create_ok, created = pcall(uci.section, uci, "quantumgrid-qos", "client", section, values)
		if not create_ok or created ~= section then
			pcall(uci.revert, uci, "quantumgrid-qos")
			respond(http, 500, { ok = false, error = "The client rate policy could not be staged in UCI." }); return
		end
		local commit_ok, committed = pcall(uci.commit, uci, "quantumgrid-qos")
		if not commit_ok or committed ~= true then
			pcall(uci.revert, uci, "quantumgrid-qos")
			respond(http, 500, { ok = false, error = "The client rate policy could not be committed." }); return
		end
		local runtime, worker_error = run_worker(sys, fs, jsonc)
		local active = false
		if runtime then
			for _, item in ipairs(runtime.policies or {}) do
				if item.section == section and item.mac == policy.mac and item.client_ip == policy.client_ip and
					item.upload_kbps == policy.upload_kbps and item.download_kbps == policy.download_kbps then active = true end
			end
		end
		if not active then
			local delete_ok, deleted = pcall(uci.delete, uci, "quantumgrid-qos", section)
			local rollback_commit_ok, rollback_committed = false, false
			if delete_ok and deleted == true then rollback_commit_ok, rollback_committed = pcall(uci.commit, uci, "quantumgrid-qos") end
			local rollback_runtime
			if rollback_commit_ok and rollback_committed == true then rollback_runtime = run_worker(sys, fs, jsonc) end
			local rolled_back = delete_ok and deleted == true and rollback_commit_ok and rollback_committed == true and type(rollback_runtime) == "table"
			audit("sqm.client-policing.add", section, "failed", http)
			respond(http, 502, { ok = false, error = rolled_back and
				("The policer was not verified and the UCI change was rolled back. " .. tostring(worker_error or "runtime policy mismatch."))
				or "The policer was not verified and rollback could not be confirmed.", rolled_back = rolled_back })
			return
		end
		audit("sqm.client-policing.add", section, "success", http)
		respond(http, nil, {
			ok = true, section = section, slot = slot, mac = policy.mac, client_ip = policy.client_ip,
			upload_kbps = policy.upload_kbps, download_kbps = policy.download_kbps,
			devices = policy.devices, mode = "drop_excess", runtime_verified = true
		})
		return
	end

	if operation == "remove" then
		local section = http.formvalue("section", true)
		if type(section) ~= "string" or not section:match("^qg_rate_%d%d$") then
			respond(http, 400, { ok = false, error = "Choose an existing QuantumGrid client rate policy." }); return
		end
		local snapshot_ok, snapshot = pcall(uci.get_all, uci, "quantumgrid-qos", section)
		if not snapshot_ok or type(snapshot) ~= "table" or snapshot[".type"] ~= "client" then
			respond(http, 404, { ok = false, error = "The selected client rate policy no longer exists." }); return
		end
		local previous = {}
		for option, value in pairs(snapshot) do
			if option ~= ".name" and option ~= ".type" and type(value) ~= "table" then previous[option] = value end
		end
		local delete_ok, deleted = pcall(uci.delete, uci, "quantumgrid-qos", section)
		if not delete_ok or deleted ~= true then
			pcall(uci.revert, uci, "quantumgrid-qos")
			respond(http, 500, { ok = false, error = "The client rate policy could not be staged for removal." }); return
		end
		local commit_ok, committed = pcall(uci.commit, uci, "quantumgrid-qos")
		if not commit_ok or committed ~= true then
			pcall(uci.revert, uci, "quantumgrid-qos")
			respond(http, 500, { ok = false, error = "The client rate policy removal could not be committed." }); return
		end
		local runtime, worker_error = run_worker(sys, fs, jsonc)
		local still_present = false
		if runtime then for _, item in ipairs(runtime.policies or {}) do if item.section == section then still_present = true end end end
		if not runtime or still_present then
			local restore_ok, restored = pcall(uci.section, uci, "quantumgrid-qos", "client", section, previous)
			local rollback_commit_ok, rollback_committed = false, false
			if restore_ok and restored == section then rollback_commit_ok, rollback_committed = pcall(uci.commit, uci, "quantumgrid-qos") end
			local rollback_runtime
			if rollback_commit_ok and rollback_committed == true then rollback_runtime = run_worker(sys, fs, jsonc) end
			local rolled_back = restore_ok and restored == section and rollback_commit_ok and rollback_committed == true and type(rollback_runtime) == "table"
			audit("sqm.client-policing.remove", section, "failed", http)
			respond(http, 502, { ok = false, error = rolled_back and
				("The policer removal was not verified and the saved policy was restored. " .. tostring(worker_error or "runtime policy mismatch."))
				or "The policer removal failed and rollback could not be confirmed.", rolled_back = rolled_back })
			return
		end
		audit("sqm.client-policing.remove", section, "success", http)
		respond(http, nil, { ok = true, section = section, removed = true, runtime_verified = true })
		return
	end
	respond(http, 400, { ok = false, error = "Choose the add or remove client policing operation." })
end

function index()
	entry({"admin", "services", "quantumgrid", "client-policing"}, call("action_client_policing")).leaf = true
end
