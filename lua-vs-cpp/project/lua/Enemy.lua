-- Enemy.lua
-- Chases the player and keeps its own place in a ring around it

local Enemy = {
    properties = {
        {
            name = "speed",
            displayName = "Speed",
            type = "float",
            default = 4.0
        }
    }
}

function Enemy:init()
    self.object = Object(self.scene, self.entity)
    self.time = 0
    RegisterEngineEvent(self, "onUpdate")
end

function Enemy:onUpdate()
    if not self.player then
        self.player = Object(self.scene, self.scene:findEntity("Player"))
    end
    local dt = Engine.deltatime
    self.time = self.time + dt

    local target = self.player.position
    local p = self.object.position
    local slot = self.entity * 2.4 + self.time * 0.3
    local radius = 3 + (self.entity % 7) * 0.9
    local dx = target.x + math.cos(slot) * radius - p.x
    local dz = target.z + math.sin(slot) * radius - p.z
    local dist = math.sqrt(dx * dx + dz * dz)

    local x, z = p.x, p.z
    if dist > 0.05 then
        local step = math.min(self.speed * dt, dist)
        x = x + dx / dist * step
        z = z + dz / dist * step
    end
    local hop = math.abs(math.sin(self.time * 9 + self.entity)) * 0.3
    self.object:setPosition(x, 0.5 + hop, z)
    self.object:setRotation(0, math.deg(math.atan(target.x - x, target.z - z)), 0)
end

return Enemy
