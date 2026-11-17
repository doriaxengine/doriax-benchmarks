-- Rays.lua
-- A scanner casts a ray for every point, every frame, and moves the point where it lands

local Rays = {
    properties = {
        {
            name = "rayCount",
            displayName = "Ray Count",
            type = "int",
            default = 2000
        },
        {
            name = "simulate",
            displayName = "Simulate",
            type = "bool",
            default = true
        }
    }
}

local STEP = 1 / 60 -- fixed step, so every run casts the same rays
local RANGE = 40

-- xorshift32, the same numbers as the C++ version
local function random(self, n)
    local x = self.seed
    x = x ~ ((x << 13) & 0xFFFFFFFF)
    x = x ~ (x >> 17)
    x = x ~ ((x << 5) & 0xFFFFFFFF)
    self.seed = x
    return x % n
end

local function build(self)
    self.seed = 7
    for _ = 1, 160 do
        local angle = math.rad(random(self, 3600) / 10)
        local radius = 6 + random(self, 320) / 10
        -- the body is on the bundle's member, so that is the entity to place
        local root = BundleManager.createBundle("assets/rays/Pillar", self.scene)
        local pillar = Object(self.scene, self.scene:findEntity("Pillar", root))
        pillar:setPosition(math.cos(angle) * radius, 2, math.sin(angle) * radius)
        pillar:setRotation(0, random(self, 360), 0)
        pillar.scale = Vector3(1.2, 4, 1.2)
    end

    self.points = Points(self.scene)
    self.points.maxPoints = self.rayCount
    for _ = 1, self.rayCount do
        self.points:addPoint(Vector3(0, -100, 0), Vector4(0.35, 1, 0.75, 1), 0.4)
    end
    self.origin = Vector3(0, 1.5, 0)
    self.sweep = 0
end

function Rays:init()
    RegisterEngineEvent(self, "onUpdate")
end

function Rays:onUpdate()
    if not self.points then
        build(self)
    end
    if not self.simulate then return end

    self.sweep = self.sweep + 40 * STEP
    local origin, points, scene, count = self.origin, self.points, self.scene, self.rayCount
    for i = 0, count - 1 do
        local a = math.rad(i * 360 / count + self.sweep)
        local tilt = math.rad(math.sin(i * 0.37 + self.sweep * 0.1) * 3)
        local c = math.cos(tilt)
        local dir = Vector3(math.cos(a) * c * RANGE, math.sin(tilt) * RANGE, math.sin(a) * c * RANGE)
        local hit = Ray(origin, dir):intersects(scene, RayFilter.BODY_3D)
        if hit.hit then
            points:updatePoint(i, hit.point)
        else
            points:updatePoint(i, origin + dir)
        end
    end
end

return Rays
