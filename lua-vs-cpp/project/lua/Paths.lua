-- Paths.lua
-- Agents walk a maze. Every frame a few of them plan their way again with A*.

local Paths = {
    properties = {
        {
            name = "agentCount",
            displayName = "Agent Count",
            type = "int",
            default = 400
        },
        {
            name = "searchesPerFrame",
            displayName = "Searches Per Frame",
            type = "int",
            default = 80
        },
        {
            name = "simulate",
            displayName = "Simulate",
            type = "bool",
            default = true
        }
    }
}

local WIDTH, HEIGHT = 72, 40
local STEP = 1 / 60 -- fixed step, so every run plans the same paths
local SPEED = 5     -- cells per second
local DX = { 1, -1, 0, 0 }
local DZ = { 0, 0, 1, -1 }

-- xorshift32, the same numbers as the C++ version
local function random(self, n)
    local x = self.seed
    x = x ~ ((x << 13) & 0xFFFFFFFF)
    x = x ~ (x >> 17)
    x = x ~ ((x << 5) & 0xFFFFFFFF)
    self.seed = x
    return x % n
end

local function freeCell(self)
    while true do
        local cell = random(self, WIDTH * HEIGHT) + 1
        if not self.blocked[cell] then
            return cell
        end
    end
end

local function place(agent)
    agent.object:setPosition(agent.x - WIDTH / 2, 0.4, agent.z - HEIGHT / 2)
end

local function build(self)
    self.seed = 2025
    local blocked = {}
    for i = 1, WIDTH * HEIGHT do
        blocked[i] = false
    end
    self.blocked = blocked

    for _ = 1, 70 do
        local horizontal = random(self, 2) == 0
        local length = 3 + random(self, 8)
        local x = random(self, WIDTH)
        local z = random(self, HEIGHT)
        local cells = 0
        for k = 0, length - 1 do
            local cx = horizontal and x + k or x
            local cz = horizontal and z or z + k
            if cx < WIDTH and cz < HEIGHT then
                blocked[cz * WIDTH + cx + 1] = true
                cells = cells + 1
            end
        end
        -- one box per wall
        local wall = Object(self.scene, BundleManager.createBundle("assets/paths/Wall", self.scene))
        local lx = horizontal and cells or 1
        local lz = horizontal and 1 or cells
        wall.scale = Vector3(lx, 1, lz)
        wall:setPosition(x + lx / 2 - WIDTH / 2, 0.5, z + lz / 2 - HEIGHT / 2)
    end

    self.agents = {}
    for i = 1, self.agentCount do
        local cell = freeCell(self)
        local agent = {
            object = Object(self.scene, BundleManager.createBundle("assets/paths/Agent", self.scene)),
            x = (cell - 1) % WIDTH + 0.5,
            z = (cell - 1) // WIDTH + 0.5,
            goal = freeCell(self),
            path = {},
            step = 1,
            idle = false
        }
        agent.object:setScale(0.7)
        place(agent)
        self.agents[i] = agent
    end

    self.g, self.from, self.open, self.closed = {}, {}, {}, {}
    self.heap, self.heapF = {}, {}
    for i = 1, WIDTH * HEIGHT do
        self.g[i], self.from[i], self.open[i], self.closed[i] = 0, 0, 0, 0
    end
    self.stamp = 0
    self.turn = 1
end

-- A* over the grid, four neighbors, Manhattan distance; nil when there is no way
local function search(self, start, goal)
    local blocked, g, from, open, closed = self.blocked, self.g, self.from, self.open, self.closed
    local heap, heapF = self.heap, self.heapF
    local stamp = self.stamp + 1
    self.stamp = stamp
    local goalX, goalZ = (goal - 1) % WIDTH, (goal - 1) // WIDTH

    g[start] = 0
    open[start] = stamp
    local size = 1
    heap[1], heapF[1] = start, 0

    while size > 0 do
        -- take the cell with the lowest f
        local cell = heap[1]
        local lastCell, lastF = heap[size], heapF[size]
        size = size - 1
        if size > 0 then
            local i = 1
            while true do
                local child = i * 2
                if child > size then break end
                if child < size and heapF[child + 1] < heapF[child] then
                    child = child + 1
                end
                if heapF[child] >= lastF then break end
                heap[i], heapF[i] = heap[child], heapF[child]
                i = child
            end
            heap[i], heapF[i] = lastCell, lastF
        end

        if cell == goal then
            -- walk back from the goal
            local path, n = {}, 0
            while cell ~= start do
                n = n + 1
                path[n] = cell
                cell = from[cell]
            end
            for k = 1, n // 2 do
                path[k], path[n - k + 1] = path[n - k + 1], path[k]
            end
            return path
        end

        if closed[cell] ~= stamp then
            closed[cell] = stamp
            local x, z = (cell - 1) % WIDTH, (cell - 1) // WIDTH
            local cost = g[cell] + 1
            for d = 1, 4 do
                local nx, nz = x + DX[d], z + DZ[d]
                if nx >= 0 and nx < WIDTH and nz >= 0 and nz < HEIGHT then
                    local nb = nz * WIDTH + nx + 1
                    if not blocked[nb] and closed[nb] ~= stamp and (open[nb] ~= stamp or cost < g[nb]) then
                        open[nb] = stamp
                        g[nb] = cost
                        from[nb] = cell
                        local f = cost + math.abs(nx - goalX) + math.abs(nz - goalZ)
                        size = size + 1
                        local i = size
                        while i > 1 do
                            local parent = i // 2
                            if heapF[parent] <= f then break end
                            heap[i], heapF[i] = heap[parent], heapF[parent]
                            i = parent
                        end
                        heap[i], heapF[i] = nb, f
                    end
                end
            end
        end
    end
    return nil
end

function Paths:init()
    RegisterEngineEvent(self, "onUpdate")
end

function Paths:onUpdate()
    if not self.agents then
        build(self)
    end
    if not self.simulate then return end

    -- a few agents plan again, in turn
    local agents = self.agents
    for _ = 1, self.searchesPerFrame do
        local agent = agents[self.turn]
        self.turn = self.turn % #agents + 1
        local here = math.floor(agent.z) * WIDTH + math.floor(agent.x) + 1
        agent.path = search(self, here, agent.goal) or {}
        agent.step = 1
        agent.idle = false
    end

    -- every agent walks its path
    local reach = SPEED * STEP
    for i = 1, #agents do
        local agent = agents[i]
        local cell = agent.path[agent.step]
        if cell then
            local tx = (cell - 1) % WIDTH + 0.5
            local tz = (cell - 1) // WIDTH + 0.5
            local dx, dz = tx - agent.x, tz - agent.z
            local dist = math.sqrt(dx * dx + dz * dz)
            if dist <= reach then
                agent.x, agent.z = tx, tz
                agent.step = agent.step + 1
            else
                agent.x = agent.x + dx / dist * reach
                agent.z = agent.z + dz / dist * reach
            end
        elseif not agent.idle then
            agent.goal = freeCell(self)
            agent.idle = true
        end
        place(agent)
    end
end

return Paths
