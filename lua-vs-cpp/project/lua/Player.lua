-- Player.lua
-- Runs a figure eight around the arena on its own, so every run is the same

local Player = {
    properties = {
        {
            name = "speed",
            displayName = "Speed",
            type = "float",
            default = 0.5
        }
    }
}

function Player:init()
    self.object = Object(self.scene, self.entity)
    self.time = 0
    RegisterEngineEvent(self, "onUpdate")
end

function Player:onUpdate()
    self.time = self.time + Engine.deltatime
    local t = self.time * self.speed
    -- the way it runs, to face it
    local dx = 12 * math.cos(t)
    local dz = 14 * math.cos(2 * t)
    self.object:setPosition(12 * math.sin(t), 0.9, 7 * math.sin(2 * t))
    self.object:setRotation(0, math.deg(math.atan(dx, dz)), 0)
end

return Player
