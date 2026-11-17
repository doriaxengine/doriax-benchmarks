#include "Wave.h"

#include <cmath>

using namespace doriax;

Wave::Wave(Scene* scene, Entity entity): Object(scene, entity) {
    REGISTER_ENGINE_EVENT(onUpdate);
}

Wave::~Wave() {
    UNREGISTER_ENGINE_EVENT(onUpdate);
}

void Wave::onUpdate() {
    time += Engine::getDeltatime();
    Vector3 p = getPosition();
    float t = time * 2.0f + (p.x + p.z) * 0.15f;
    setPosition(p.x, std::sin(t) * height, p.z);
    setRotation(0.0f, t * 30.0f, 0.0f);
}
