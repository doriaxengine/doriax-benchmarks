#pragma once

#include "Object.h"
#include "Engine.h"
#include "ScriptProperty.h"

// Chases the player and keeps its own place in a ring around it
class Enemy : public doriax::Object {
public:
    DPROPERTY("Speed")
    float speed = 4.0f;

    Enemy(doriax::Scene* scene, doriax::Entity entity);
    virtual ~Enemy();

    void onUpdate();

private:
    doriax::Entity player = NULL_ENTITY;
    float time = 0.0f;
};
