#include "Boot.h"

#include "SceneManager.h"

#include <cstdlib>

using namespace doriax;

Boot::Boot(Scene* scene, Entity entity): ScriptBase(scene, entity) {
    REGISTER_ENGINE_EVENT(onUpdate);
}

Boot::~Boot() {
    UNREGISTER_ENGINE_EVENT(onUpdate);
}

void Boot::onUpdate() {
    if (loaded) return;
    loaded = true;
    const char* name = std::getenv("BENCH_SCENE");
    SceneManager::loadScene(name ? name : "Crowd");
}
