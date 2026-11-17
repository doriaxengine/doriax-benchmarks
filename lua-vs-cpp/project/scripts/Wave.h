#pragma once

#include "Object.h"
#include "Engine.h"
#include "ScriptProperty.h"

// Moves its cube up and down with its neighbors and turns it
class Wave : public doriax::Object {
public:
    DPROPERTY("Height")
    float height = 1.2f;

    Wave(doriax::Scene* scene, doriax::Entity entity);
    virtual ~Wave();

    void onUpdate();

private:
    float time = 0.0f;
};
