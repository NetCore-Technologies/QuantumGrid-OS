module("luci.quantumgrid.acceleration", package.seeall)

local REQUIRED_COMPONENTS = {
	"EDMA device-tree node",
	"ESS / PPE switch device-tree node",
	"NSS core 0 device-tree node",
	"NSS core 1 device-tree node",
	"NSS core driver",
	"NSS datapath / EDMA driver",
	"Qualcomm SSDK",
	"NSS Enhanced Connection Manager",
	"NSS firmware core 0",
	"NSS firmware core 1",
	"Wi-Fi driver",
	"ath11k NSS offload parameter"
}

local REQUIRED_SET = {}
for _, name in ipairs(REQUIRED_COMPONENTS) do
	REQUIRED_SET[name] = true
end

local ALLOWED_KINDS = {
	["device-tree"] = true,
	["kernel-module"] = true,
	firmware = true
}

local function safe_text(value, maximum)
	if type(value) ~= "string" then return "" end
	return value:gsub("[%c]", " "):sub(1, maximum or 240)
end

function summarize(source)
	local result = {
		status = "not-detected",
		present_components = 0,
		required_components = #REQUIRED_COMPONENTS,
		offload_verified = false,
		components = {},
		note = "Component and device-tree presence only. This inventory does not verify NSS firmware boot, ath11k NSS integration, PPE flow programming, active EDMA queues, ECM offload state or packet counters. The experimental 25.12-nss profile disables generic packet steering/software and hardware flow offloading; do not re-enable those paths alongside NSS. DSA bridge-vlan filtering is not compatible with NSS Wi-Fi offload. End-to-end offload remains unverified until traffic-path counters and controlled benchmarks pass on the AW1000."
	}
	if type(source) ~= "table" then return result end

	local seen = {}
	for _, component in ipairs(source) do
		if type(component) == "table" then
			local name = safe_text(component.name, 96)
			local kind = component.kind
			if name ~= "" and ALLOWED_KINDS[kind] and not seen[name] then
				seen[name] = true
				local present = component.present == true
				table.insert(result.components, {
					name = name,
					kind = kind,
					present = present,
					detail = safe_text(component.detail, 240)
				})
				if REQUIRED_SET[name] and present then
					result.present_components = result.present_components + 1
				end
			end
		end
	end

	if result.present_components > 0 then
		result.status = "partial"
	end
	if result.present_components == result.required_components then
		result.status = "components-present-unverified"
	end
	table.sort(result.components, function(left, right)
		return left.name < right.name
	end)
	return result
end

return _M
