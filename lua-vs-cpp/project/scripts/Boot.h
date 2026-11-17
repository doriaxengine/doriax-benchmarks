#pragma once

#include "ScriptBase.h"
#include "Engine.h"
#include "ScriptProperty.h"

// Loads the scene named by BENCH_SCENE (Crowd when it is not set)
class Boot : public doriax::ScriptBase {
public:
    Boot(doriax::Scene* scene, doriax::Entity entity);
    ~Boot();

    void onUpdate();

private:
    bool loaded = false;
};
