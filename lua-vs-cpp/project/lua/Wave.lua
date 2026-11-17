-- Wave.lua
-- Moves its cube up and down with its neighbors and turns it

local Wave = {
    properties = {
        {
            name = "height",
            displayName = "Height",
            type = "float",
            default = 1.2
        }
    }
}

function Wave:init()
    self.object = Object(self.scene, self.entity)
    self.time = 0
    RegisterEngineEvent(self, "onUpdate")
end

function Wave:onUpdate()
    self.time = self.time + Engine.deltatime
    local p = self.object.position
    local t = self.time * 2 + (p.x + p.z) * 0.15
    self.object:setPosition(p.x, math.sin(t) * self.height, p.z)
    self.object:setRotation(0, t * 30, 0)
end

return Wave
