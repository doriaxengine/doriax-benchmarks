#pragma once

#include "ScriptBase.h"
#include "Engine.h"
#include "ScriptProperty.h"

#include <cstdint>
#include <vector>

// Agents walk a maze. Every frame a few of them plan their way again with A*.
class Paths : public doriax::ScriptBase {
public:
    DPROPERTY("Agent Count")
    int agentCount = 400;

    DPROPERTY("Searches Per Frame")
    int searchesPerFrame = 80;

    DPROPERTY("Simulate")
    bool simulate = true;

    Paths(doriax::Scene* scene, doriax::Entity entity);
    ~Paths();

    void onUpdate();

private:
    struct Agent {
        doriax::Entity entity;
        double x = 0.0;
        double z = 0.0;
        int goal = 0;
        std::vector<int> path;
        size_t step = 0;
        bool idle = false;
    };

    uint32_t random(uint32_t n);
    int freeCell();
    void place(const Agent& agent);
    void build();
    bool search(int start, int goal, std::vector<int>& path);

    bool built = false;
    uint32_t seed = 2025;
    size_t turn = 0;
    int stamp = 0;
    std::vector<char> blocked;
    std::vector<Agent> agents;
    std::vector<int> g, from, open, closed, heap, heapF;
};
