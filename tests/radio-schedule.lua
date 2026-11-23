package.path = "files/usr/lib/lua/?.lua;" .. package.path
local schedule = require "luci.quantumgrid.radio_schedule"
local valid, err = schedule.validate({radio="radio0",enabled="1",days="1,2,3,4,5",start_time="08:00",end_time="22:00",confirmed="1"})
assert(valid,err)
assert(valid.configured and valid.valid and valid.enabled)
assert(valid.days_csv=="1,2,3,4,5" and valid.days_value=="1 2 3 4 5")
assert(schedule.is_active(valid,1,480))
assert(schedule.is_active(valid,5,1319))
assert(not schedule.is_active(valid,5,1320))
assert(not schedule.is_active(valid,6,600))
assert(schedule.desired_disabled(valid,1,479)==true)
assert(schedule.desired_disabled(valid,1,480)==false)
assert(schedule.desired_disabled(valid,6,600)==true)
local overnight=assert(schedule.validate({radio="radio1",enabled="1",days="5",start_time="22:00",end_time="06:00",confirmed="1"}))
assert(schedule.is_active(overnight,5,1320) and schedule.is_active(overnight,5,1439))
assert(schedule.is_active(overnight,6,0) and schedule.is_active(overnight,6,359))
assert(not schedule.is_active(overnight,6,360) and not schedule.is_active(overnight,7,120))
local sunday=assert(schedule.validate({radio="radio2",enabled="1",days="7",start_time="23:00",end_time="05:00",confirmed="1"}))
assert(schedule.is_active(sunday,7,1380) and schedule.is_active(sunday,1,120))
local disabled=assert(schedule.validate({radio="radio0",enabled="0",days="1,2,3,4,5",start_time="08:00",end_time="22:00",confirmed="1"}))
assert(schedule.desired_disabled(disabled,1,30)==nil,"disabled schedule preserves manual radio state")
local restored=schedule.from_config({[".type"]="schedule",radio="radio0",enabled="1",days="1 2 3 4 5",start_time="08:00",end_time="22:00"},"radio0")
assert(restored and restored.days_csv=="1,2,3,4,5")
assert(schedule.from_config({[".type"]="other",radio="radio0",enabled="1",days="1",start_time="08:00",end_time="22:00"},"radio0")==nil)
assert(schedule.from_config({[".type"]="schedule",radio="radio1",enabled="1",days="1",start_time="08:00",end_time="22:00"},"radio0")==nil)
for _, bad in ipairs({
 {radio="../radio0"},{enabled="true"},{confirmed="0"},{days=""},{days="0"},{days="8"},
 {days="1,1"},{days="1,,2"},{days="1, 8"},{start_time="24:00"},{start_time="8:00"},
 {end_time="12:60"},{end_time="08:00"}
}) do
 local candidate={radio="radio0",enabled="1",days="1,2",start_time="08:00",end_time="22:00",confirmed="1"}
 for key,value in pairs(bad) do candidate[key]=value end
 assert(schedule.validate(candidate)==nil,"invalid schedule input must fail closed")
end
for _, args in ipairs({{valid,0,1},{valid,8,1},{valid,1,-1},{valid,1,1440},{nil,1,10}}) do
 assert(schedule.is_active(args[1],args[2],args[3])==false)
end
print("radio-schedule: weekday, overnight, validation and manual-override tests passed")