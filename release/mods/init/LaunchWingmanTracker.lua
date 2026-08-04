local WingmanTracker = require 'behaviors.WingmanTracker'

-- Register the wingman designation/tracking behavior at Jester launch.
mod_init[#mod_init+1] = function(jester)
	jester.behaviors[WingmanTracker] = WingmanTracker:new()
end
