#pragma once

#include "ScriptBase.h"
#include "Engine.h"
#include "Points.h"
#include "ScriptProperty.h"

#include <cstdint>
#include <memory>

// A scanner casts a ray for every point, every frame, and moves the point where it lands
class Rays : public doriax::ScriptBase {
public:
    DPROPERTY("Ray Count")
    int rayCount = 2000;

    DPROPERTY("Simulate")
    bool simulate = true;

    Rays(doriax::Scene* scene, doriax::Entity entity);
    ~Rays();

    void onUpdate();

private:
    uint32_t random(uint32_t n);
    void build();

    uint32_t seed = 7;
    double sweep = 0.0;
    std::unique_ptr<doriax::Points> points;
};
