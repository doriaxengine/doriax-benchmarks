#include "Enemy.h"

#include <algorithm>
#include <cmath>

using namespace doriax;

Enemy::Enemy(Scene* scene, Entity entity): Object(scene, entity) {
    REGISTER_ENGINE_EVENT(onUpdate);
}

Enemy::~Enemy() {
    UNREGISTER_ENGINE_EVENT(onUpdate);
}

void Enemy::onUpdate() {
    if (player == NULL_ENTITY) {
        player = getScene()->findEntity("Player");
    }
    float dt = Engine::getDeltatime();
    time += dt;

    Vector3 target = Object(getScene(), player).getPosition();
    Vector3 p = getPosition();
    float slot = getEntity() * 2.4f + time * 0.3f;
    float radius = 3.0f + (getEntity() % 7) * 0.9f;
    float dx = target.x + std::cos(slot) * radius - p.x;
    float dz = target.z + std::sin(slot) * radius - p.z;
    float dist = std::sqrt(dx * dx + dz * dz);

    float x = p.x, z = p.z;
    if (dist > 0.05f) {
        float step = std::min(speed * dt, dist);
        x += dx / dist * step;
        z += dz / dist * step;
    }
    float hop = std::fabs(std::sin(time * 9.0f + getEntity())) * 0.3f;
    setPosition(x, 0.5f + hop, z);
    setRotation(0.0f, std::atan2(target.x - x, target.z - z) * 57.29578f, 0.0f);
}
