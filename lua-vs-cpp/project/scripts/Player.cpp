#include "Player.h"

#include <cmath>

using namespace doriax;

Player::Player(Scene* scene, Entity entity): Object(scene, entity) {
    REGISTER_ENGINE_EVENT(onUpdate);
}

Player::~Player() {
    UNREGISTER_ENGINE_EVENT(onUpdate);
}

void Player::onUpdate() {
    time += Engine::getDeltatime();
    float t = time * speed;
    // the way it runs, to face it
    float dx = 12.0f * std::cos(t);
    float dz = 14.0f * std::cos(2.0f * t);
    setPosition(12.0f * std::sin(t), 0.9f, 7.0f * std::sin(2.0f * t));
    setRotation(0.0f, std::atan2(dx, dz) * 57.29578f, 0.0f);
}
