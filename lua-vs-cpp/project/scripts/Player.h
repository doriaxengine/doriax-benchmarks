#pragma once

#include "Object.h"
#include "Engine.h"
#include "ScriptProperty.h"

// Runs a figure eight around the arena on its own, so every run is the same
class Player : public doriax::Object {
public:
    DPROPERTY("Speed")
    float speed = 0.5f;

    Player(doriax::Scene* scene, doriax::Entity entity);
    virtual ~Player();

    void onUpdate();

private:
    float time = 0.0f;
};
