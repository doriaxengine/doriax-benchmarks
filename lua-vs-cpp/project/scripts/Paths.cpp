#include "Paths.h"

#include "BundleManager.h"
#include "Object.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>

using namespace doriax;

namespace {
    const int WIDTH = 72;
    const int HEIGHT = 40;
    const double STEP = 1.0 / 60.0; // fixed step, so every run plans the same paths
    const double SPEED = 5.0;       // cells per second
    const int DX[4] = {1, -1, 0, 0};
    const int DZ[4] = {0, 0, 1, -1};
}

Paths::Paths(Scene* scene, Entity entity): ScriptBase(scene, entity) {
    REGISTER_ENGINE_EVENT(onUpdate);
}

Paths::~Paths() {
    UNREGISTER_ENGINE_EVENT(onUpdate);
}

// xorshift32, the same numbers as the Lua version
uint32_t Paths::random(uint32_t n) {
    seed ^= seed << 13;
    seed ^= seed >> 17;
    seed ^= seed << 5;
    return seed % n;
}

int Paths::freeCell() {
    while (true) {
        int cell = random(WIDTH * HEIGHT);
        if (!blocked[cell]) {
            return cell;
        }
    }
}

void Paths::place(const Agent& agent) {
    Object(getScene(), agent.entity).setPosition(agent.x - WIDTH / 2.0, 0.4f, agent.z - HEIGHT / 2.0);
}

void Paths::build() {
    Scene* scene = getScene();
    blocked.assign(WIDTH * HEIGHT, 0);

    for (int i = 0; i < 70; i++) {
        bool horizontal = random(2) == 0;
        int length = 3 + random(8);
        int x = random(WIDTH);
        int z = random(HEIGHT);
        int cells = 0;
        for (int k = 0; k < length; k++) {
            int cx = horizontal ? x + k : x;
            int cz = horizontal ? z : z + k;
            if (cx < WIDTH && cz < HEIGHT) {
                blocked[cz * WIDTH + cx] = 1;
                cells++;
            }
        }
        // one box per wall
        Object wall(scene, BundleManager::createBundle("assets/paths/Wall", scene));
        double lx = horizontal ? cells : 1;
        double lz = horizontal ? 1 : cells;
        wall.setScale(Vector3(lx, 1.0f, lz));
        wall.setPosition(x + lx / 2 - WIDTH / 2.0, 0.5f, z + lz / 2 - HEIGHT / 2.0);
    }

    for (int i = 0; i < agentCount; i++) {
        int cell = freeCell();
        Agent agent;
        agent.entity = BundleManager::createBundle("assets/paths/Agent", scene);
        agent.x = cell % WIDTH + 0.5;
        agent.z = cell / WIDTH + 0.5;
        agent.goal = freeCell();
        Object(scene, agent.entity).setScale(0.7f);
        place(agent);
        agents.push_back(agent);
    }

    size_t cells = WIDTH * HEIGHT;
    g.assign(cells, 0);
    from.assign(cells, 0);
    open.assign(cells, 0);
    closed.assign(cells, 0);
    heap.assign(cells * 4 + 1, 0);
    heapF.assign(cells * 4 + 1, 0);
}

// A* over the grid, four neighbors, Manhattan distance; false when there is no way
bool Paths::search(int start, int goal, std::vector<int>& path) {
    path.clear();
    stamp++;
    int goalX = goal % WIDTH, goalZ = goal / WIDTH;

    g[start] = 0;
    open[start] = stamp;
    int size = 1;
    heap[1] = start;
    heapF[1] = 0;

    while (size > 0) {
        // take the cell with the lowest f
        int cell = heap[1];
        int lastCell = heap[size], lastF = heapF[size];
        size--;
        if (size > 0) {
            int i = 1;
            while (true) {
                int child = i * 2;
                if (child > size) break;
                if (child < size && heapF[child + 1] < heapF[child]) {
                    child++;
                }
                if (heapF[child] >= lastF) break;
                heap[i] = heap[child];
                heapF[i] = heapF[child];
                i = child;
            }
            heap[i] = lastCell;
            heapF[i] = lastF;
        }

        if (cell == goal) {
            // walk back from the goal
            while (cell != start) {
                path.push_back(cell);
                cell = from[cell];
            }
            std::reverse(path.begin(), path.end());
            return true;
        }

        if (closed[cell] != stamp) {
            closed[cell] = stamp;
            int x = cell % WIDTH, z = cell / WIDTH;
            int cost = g[cell] + 1;
            for (int d = 0; d < 4; d++) {
                int nx = x + DX[d], nz = z + DZ[d];
                if (nx >= 0 && nx < WIDTH && nz >= 0 && nz < HEIGHT) {
                    int nb = nz * WIDTH + nx;
                    if (!blocked[nb] && closed[nb] != stamp && (open[nb] != stamp || cost < g[nb])) {
                        open[nb] = stamp;
                        g[nb] = cost;
                        from[nb] = cell;
                        int f = cost + std::abs(nx - goalX) + std::abs(nz - goalZ);
                        size++;
                        int i = size;
                        while (i > 1) {
                            int parent = i / 2;
                            if (heapF[parent] <= f) break;
                            heap[i] = heap[parent];
                            heapF[i] = heapF[parent];
                            i = parent;
                        }
                        heap[i] = nb;
                        heapF[i] = f;
                    }
                }
            }
        }
    }
    return false;
}

void Paths::onUpdate() {
    if (!built) {
        build();
        built = true;
    }
    if (!simulate) return;

    // a few agents plan again, in turn
    for (int s = 0; s < searchesPerFrame; s++) {
        Agent& agent = agents[turn];
        turn = (turn + 1) % agents.size();
        int here = (int)std::floor(agent.z) * WIDTH + (int)std::floor(agent.x);
        search(here, agent.goal, agent.path);
        agent.step = 0;
        agent.idle = false;
    }

    // every agent walks its path
    double reach = SPEED * STEP;
    for (Agent& agent : agents) {
        if (agent.step < agent.path.size()) {
            int cell = agent.path[agent.step];
            double tx = cell % WIDTH + 0.5;
            double tz = cell / WIDTH + 0.5;
            double dx = tx - agent.x, dz = tz - agent.z;
            double dist = std::sqrt(dx * dx + dz * dz);
            if (dist <= reach) {
                agent.x = tx;
                agent.z = tz;
                agent.step++;
            } else {
                agent.x += dx / dist * reach;
                agent.z += dz / dist * reach;
            }
        } else if (!agent.idle) {
            agent.goal = freeCell();
            agent.idle = true;
        }
        place(agent);
    }
}
