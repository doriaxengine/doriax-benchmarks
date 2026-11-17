#pragma once

#include "ScriptBase.h"
#include "Engine.h"
#include "ScriptProperty.h"

#include <chrono>
#include <string>
#include <vector>

// Spawns the objects of a run and times its frames, the same way in every run.
// BENCH_LANG picks the bundles: lua, cpp or off (the objects with no script).
// Its onUpdate runs first; a second one, added after every script's, ends the script timer.
class Bench : public doriax::ScriptBase {
public:
    DPROPERTY("Round")
    int round = 2; // 1 arena, 2 crowd, 3 paths, 4 rays

    DPROPERTY("Count")
    int count = 10000;

    Bench(doriax::Scene* scene, doriax::Entity entity);
    ~Bench();

    void onUpdate();

private:
    void spawn();
    void scriptsDone();
    void finish();

    std::string lang;
    std::string output;
    int warmup = 120;
    int frames = 600;
    int stepFps = 0;

    bool spawned = false;
    int frame = 0;
    std::vector<float> times;
    std::vector<float> scriptTimes;
    std::vector<float> frameCpu;
    std::vector<float> scriptCpu;
    double lastCpu = 0.0;
    double scriptsStartCpu = 0.0;
    std::string endTag;
    std::chrono::steady_clock::time_point last;
    std::chrono::steady_clock::time_point scriptsStart;
};
